// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuthBroker.swift - Wire protocol handshake for relay channel authentication.

import Foundation
import Network

// MARK: - Relay Handshake

/// Implements the binary wire protocol for relay authentication.
///
/// ## Wire Format
///
/// ```
/// Bytes 0-3:    Payload length (big-endian uint32) — always 24
/// Bytes 4-19:   Channel UUID (16 bytes, big-endian)
/// Bytes 20-27:  Timestamp (8 bytes, Unix epoch, big-endian)
/// Bytes 28-59:  HMAC-SHA256(bytes 4-27, channel_secret)
/// ```
///
/// ## Validation Steps
///
/// 1. Check data length (minimum 60 bytes).
/// 2. Read and verify payload length field.
/// 3. Extract channel UUID and verify it matches.
/// 4. Extract timestamp and verify it's within ±60 seconds.
/// 5. Compute HMAC over payload and verify against signature.
/// 6. Check replay tracker for duplicate timestamps.
enum RelayHandshake {

    // MARK: - Constants

    /// Expected payload size: 16 (UUID) + 8 (timestamp) = 24 bytes.
    static let payloadSize = 24

    /// Total handshake size: 4 (length) + 24 (payload) + 32 (HMAC) = 60 bytes.
    static let totalSize = 60

    /// Maximum clock skew tolerance in seconds.
    static let timestampTolerance: UInt64 = 60

    // MARK: - Validation Result

    enum ValidationResult: Equatable, Sendable {
        case accepted
        case rejected(RejectionReason)
    }

    enum RejectionReason: Equatable, Sendable {
        case malformed
        case channelMismatch
        case timestampExpired
        case invalidSignature
        case replayDetected
    }

    // MARK: - Build Handshake

    /// Constructs a binary handshake for sending to the relay.
    ///
    /// - Parameters:
    ///   - channelID: The UUID of the relay channel.
    ///   - timestamp: Unix epoch seconds (current time).
    ///   - token: The channel's authentication token.
    /// - Returns: The complete 60-byte handshake data.
    static func build(channelID: UUID, timestamp: UInt64, token: RelayToken) -> Data {
        var data = Data()

        // Payload length (big-endian uint32).
        var payloadLen = UInt32(payloadSize).bigEndian
        data.append(Data(bytes: &payloadLen, count: 4))

        // Channel UUID (16 bytes).
        let uuidBytes = withUnsafeBytes(of: channelID.uuid) { Data($0) }
        data.append(uuidBytes)

        // Timestamp (big-endian uint64).
        var tsBigEndian = timestamp.bigEndian
        data.append(Data(bytes: &tsBigEndian, count: 8))

        // HMAC-SHA256 over the payload (bytes 4-27).
        let payload = data[4..<28]
        let signature = token.sign(payload)
        data.append(signature)

        return data
    }

    // MARK: - Validate Handshake

    /// Validates an incoming handshake.
    ///
    /// - Parameters:
    ///   - data: The raw bytes received from the connection.
    ///   - expectedChannelID: The UUID this relay expects.
    ///   - token: The channel's authentication token.
    ///   - replayTracker: Optional tracker for replay prevention.
    /// - Returns: `.accepted` or `.rejected(reason)`.
    static func validate(
        data: Data,
        expectedChannelID: UUID,
        token: RelayToken,
        replayTracker: UnsafeMutablePointer<ReplayTracker>?
    ) -> ValidationResult {
        // Check minimum size.
        guard data.count >= totalSize else { return .rejected(.malformed) }

        // Read payload length.
        let payloadLen = Data(data[0..<4]).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        guard payloadLen == UInt32(payloadSize) else { return .rejected(.malformed) }

        // Extract channel UUID.
        let receivedUUID = Data(data[4..<20]).withUnsafeBytes { buf -> UUID in
            let raw = buf.loadUnaligned(as: uuid_t.self)
            return UUID(uuid: raw)
        }
        guard receivedUUID == expectedChannelID else { return .rejected(.channelMismatch) }

        // Extract timestamp.
        let timestamp = Data(data[20..<28]).withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).bigEndian
        }
        let now = UInt64(Date().timeIntervalSince1970)
        let diff = timestamp > now ? timestamp - now : now - timestamp
        guard diff <= timestampTolerance else { return .rejected(.timestampExpired) }

        // Verify HMAC.
        let payload = Data(data[4..<28])
        let receivedSignature = Data(data[28..<60])
        guard token.validate(payload: payload, signature: receivedSignature) else {
            return .rejected(.invalidSignature)
        }

        // Replay check.
        if let tracker = replayTracker {
            guard tracker.pointee.isAllowed(timestamp) else {
                return .rejected(.replayDetected)
            }
        }

        return .accepted
    }
}

// MARK: - Relay Auth Broker

/// Validates incoming connections on a relay channel's local port.
///
/// Listens on the NWListener port assigned to the reverse tunnel.
/// For each connection, reads the handshake, validates it, and either
/// relays bidirectionally or rejects with an audit log entry.
@MainActor
final class RelayAuthBroker {

    private let channelID: UUID
    private let token: RelayToken
    private let acl: RelayACL
    private let auditLog: RelayAuditLog?
    private let targetHost: String
    private let targetPort: UInt16
    private var listener: NWListener?
    private var replayTracker = ReplayTracker(windowSeconds: 60)

    /// Number of currently active connections.
    private(set) var activeConnections: Int = 0

    /// Creates an auth broker for a relay channel.
    ///
    /// - Parameters:
    ///   - channelID: The channel this broker authenticates for.
    ///   - token: HMAC token for handshake validation.
    ///   - acl: Access control list.
    ///   - targetHost: Local service host to relay to (e.g., "localhost").
    ///   - targetPort: Local service port to relay to.
    ///   - auditLog: Optional audit logger.
    init(
        channelID: UUID,
        token: RelayToken,
        acl: RelayACL,
        targetHost: String = "localhost",
        targetPort: UInt16 = 0,
        auditLog: RelayAuditLog? = nil
    ) {
        self.channelID = channelID
        self.token = token
        self.acl = acl
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.auditLog = auditLog
    }

    /// Starts listening on the given port.
    func start(port: UInt16) throws {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: .tcp, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    /// Stops listening and cleans up.
    func stop() {
        listener?.cancel()
        listener = nil
        activeConnections = 0
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        // Read the handshake (60 bytes).
        connection.receive(minimumIncompleteLength: RelayHandshake.totalSize,
                          maximumLength: RelayHandshake.totalSize) {
            [weak self] data, _, _, error in

            Task { @MainActor in
                guard let self else { return }

                let earlyRemoteHost = self.extractRemoteHost(from: connection)

                guard let data, data.count >= RelayHandshake.totalSize else {
                    self.auditLog?.log(.connectionRejected(
                        channelID: self.channelID,
                        remoteHost: earlyRemoteHost,
                        reason: "Incomplete handshake"
                    ))
                    connection.cancel()
                    return
                }

                let result = RelayHandshake.validate(
                    data: data,
                    expectedChannelID: self.channelID,
                    token: self.token,
                    replayTracker: &self.replayTracker
                )

                // Extract remote host from the NWConnection endpoint.
                let remoteHost = self.extractRemoteHost(from: connection)

                switch result {
                case .accepted:
                    // Enforce ACL: host filtering + connection limit.
                    guard self.acl.evaluate(processName: "", remoteHost: remoteHost) else {
                        self.auditLog?.log(.connectionRejected(
                            channelID: self.channelID,
                            remoteHost: remoteHost,
                            reason: "ACL denied host"
                        ))
                        connection.cancel()
                        return
                    }
                    guard self.acl.canAcceptConnection(currentCount: self.activeConnections) else {
                        self.auditLog?.log(.connectionRejected(
                            channelID: self.channelID,
                            remoteHost: remoteHost,
                            reason: "Max connections exceeded"
                        ))
                        connection.cancel()
                        return
                    }
                    self.activeConnections += 1
                    self.auditLog?.log(.connectionAccepted(
                        channelID: self.channelID,
                        remoteHost: remoteHost
                    ))
                    self.relayToTarget(clientConnection: connection)

                case .rejected(let reason):
                    self.auditLog?.log(.connectionRejected(
                        channelID: self.channelID,
                        remoteHost: remoteHost,
                        reason: "\(reason)"
                    ))
                    connection.cancel()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Extracts the remote host address from an NWConnection endpoint.
    private func extractRemoteHost(from connection: NWConnection) -> String {
        guard let endpoint = connection.currentPath?.remoteEndpoint else {
            return "unknown"
        }
        switch endpoint {
        case .hostPort(let host, _):
            return "\(host)"
        default:
            return "unknown"
        }
    }

    // MARK: - Bidirectional Relay

    /// Connects to the target local service and pipes bytes bidirectionally.
    private func relayToTarget(clientConnection: NWConnection) {
        guard targetPort > 0 else {
            clientConnection.cancel()
            activeConnections = max(0, activeConnections - 1)
            return
        }

        let target = NWConnection(
            host: NWEndpoint.Host(targetHost),
            port: NWEndpoint.Port(rawValue: targetPort)!,
            using: .tcp
        )

        target.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    let closed = RelayCloseFlag()
                    self.pipeData(from: clientConnection, to: target, closeFlag: closed)
                    self.pipeData(from: target, to: clientConnection, closeFlag: closed)
                case .failed, .cancelled:
                    clientConnection.cancel()
                    self.activeConnections = max(0, self.activeConnections - 1)
                default:
                    break
                }
            }
        }

        target.start(queue: .main)
    }

    /// Continuously reads from `source` and writes to `dest`.
    private func pipeData(
        from source: NWConnection,
        to dest: NWConnection,
        closeFlag: RelayCloseFlag
    ) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            data, _, isComplete, error in
            if let data, !data.isEmpty {
                dest.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        source.cancel()
                        dest.cancel()
                        Task { @MainActor [weak self] in
                            self?.finishRelay(closeFlag)
                        }
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.pipeData(from: source, to: dest, closeFlag: closeFlag)
                    }
                })
            } else if isComplete || error != nil {
                source.cancel()
                dest.cancel()
                Task { @MainActor [weak self] in
                    self?.finishRelay(closeFlag)
                }
            }
        }
    }

    private func finishRelay(_ closeFlag: RelayCloseFlag) {
        guard closeFlag.close() else { return }
        activeConnections = max(0, activeConnections - 1)
    }
}
