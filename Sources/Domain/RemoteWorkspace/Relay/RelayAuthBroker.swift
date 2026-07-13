// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuthBroker.swift - Wire protocol handshake for relay channel authentication.

import Darwin
import Dispatch
import Foundation
import Network

// MARK: - Relay Auth Broker Contract

enum RelayAuthBrokerError: Error, LocalizedError, Equatable {
    case alreadyRunning
    case listenerPortUnavailable
    case portQuarantineUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Relay authentication broker is already running"
        case .listenerPortUnavailable:
            return "Relay authentication broker did not receive a listening port"
        case .portQuarantineUnavailable:
            return "Relay authentication broker could not reserve its failed listening port"
        }
    }
}

@MainActor
protocol RelayAuthBrokering: AnyObject {
    var listeningPort: UInt16? { get }
    func startOnEphemeralLoopbackPort() async throws -> UInt16
    func updateAuthorization(token: RelayToken, acl: RelayACL)
    func setConnectionCountHandler(_ handler: ((Int) -> Void)?)
    func setFailureHandler(_ handler: ((any Error) -> Void)?)
    func deactivate()
    func stop()
}

// MARK: - Relay Handshake

/// Implements the binary wire protocol for relay authentication.
///
/// ## Wire Format
///
/// ```
/// Bytes 0-3:    Payload length (big-endian uint32) — always 40
/// Bytes 4-19:   Channel UUID (16 bytes, big-endian)
/// Bytes 20-27:  Timestamp (8 bytes, Unix epoch, big-endian)
/// Bytes 28-43:  Random nonce (16 bytes)
/// Bytes 44-75:  HMAC-SHA256(bytes 4-43, channel_secret)
/// ```
///
/// ## Validation Steps
///
/// 1. Check data length (minimum 76 bytes).
/// 2. Read and verify payload length field.
/// 3. Extract channel UUID and verify it matches.
/// 4. Extract timestamp and verify it's within ±60 seconds.
/// 5. Compute HMAC over payload and verify against signature.
/// 6. Check replay tracker for duplicate nonces.
enum RelayHandshake {

    // MARK: - Constants

    static let nonceSize = 16

    /// Expected payload size: 16 (UUID) + 8 (timestamp) + 16 (nonce) = 40 bytes.
    static let payloadSize = 40

    /// Total handshake size: 4 (length) + 40 (payload) + 32 (HMAC) = 76 bytes.
    static let totalSize = 76

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
    /// - Returns: The complete 76-byte handshake data.
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

        var generator = SystemRandomNumberGenerator()
        let nonce = Data((0..<nonceSize).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        })
        data.append(nonce)

        // HMAC-SHA256 over the payload (bytes 4-43).
        let payload = data[4..<44]
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
        let payload = Data(data[4..<44])
        let nonce = Data(data[28..<44])
        let receivedSignature = Data(data[44..<76])
        guard token.validate(payload: payload, signature: receivedSignature) else {
            return .rejected(.invalidSignature)
        }

        // Replay check.
        if let tracker = replayTracker {
            guard tracker.pointee.isAllowed(timestamp: timestamp, nonce: nonce) else {
                return .rejected(.replayDetected)
            }
        }

        return .accepted
    }
}

// MARK: - Failed-Port Quarantine

/// Owns a loopback TCP port synchronously so a failed broker port cannot be
/// reassigned while its remote SSH listener may still exist.
@MainActor
final class RelayPortQuarantine {
    private var readSource: DispatchSourceRead?
    private(set) var listeningPort: UInt16?

    @discardableResult
    func start(on requestedPort: UInt16) -> UInt16? {
        guard readSource == nil else { return nil }

        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var ownsDescriptor = true
        defer {
            if ownsDescriptor {
                Darwin.close(descriptor)
            }
        }

        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0
        else {
            return nil
        }

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(requestedPort).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0, Darwin.listen(descriptor, SOMAXCONN) == 0 else {
            return nil
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.getsockname(descriptor, socketAddress, &boundAddressLength)
            }
        }
        guard nameResult == 0 else { return nil }

        let port = UInt16(bigEndian: boundAddress.sin_port)
        guard port > 0, requestedPort == 0 || requestedPort == port else { return nil }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: .main
        )
        source.setEventHandler {
            while true {
                let connection = Darwin.accept(descriptor, nil, nil)
                if connection >= 0 {
                    Darwin.close(connection)
                    continue
                }
                if errno == EINTR { continue }
                break
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }

        readSource = source
        listeningPort = port
        ownsDescriptor = false
        source.resume()
        return port
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        listeningPort = nil
    }

    deinit {
        readSource?.cancel()
    }
}

// MARK: - Relay Auth Broker

/// Validates incoming connections on a relay channel's local port.
///
/// Listens on an OS-assigned loopback port used as the mandatory target of
/// the reverse tunnel. For each connection, reads the handshake, validates
/// it, and either relays bidirectionally or rejects with an audit log entry.
@MainActor
final class RelayAuthBroker: RelayAuthBrokering {

    private final class ListenerStartupGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    @MainActor
    private final class DuplexRelayState {
        private var completedDirections = 0
        private var isClosed = false

        func completeDirection() -> Bool {
            guard !isClosed else { return false }
            completedDirections += 1
            if completedDirections < 2 { return false }
            isClosed = true
            return true
        }

        func closeForFailure() -> Bool {
            guard !isClosed else { return false }
            isClosed = true
            return true
        }

        func invalidate() {
            isClosed = true
        }
    }

    private let channelID: UUID
    private var token: RelayToken
    private var acl: RelayACL
    private let auditLog: RelayAuditLog?
    private let targetHost: String
    private let targetPort: UInt16
    private let handshakeTimeoutNanoseconds: UInt64
    private let maxPendingHandshakes: Int
    private var listener: NWListener?
    private var portQuarantine: RelayPortQuarantine?
    private var replayTracker = ReplayTracker(windowSeconds: 60)
    private var trackedConnections: [ObjectIdentifier: NWConnection] = [:]
    private var activeRelays: [ObjectIdentifier: DuplexRelayState] = [:]
    private var pendingHandshakes: Set<ObjectIdentifier> = []
    private var handshakeTimeoutTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var connectionCountHandler: ((Int) -> Void)?
    private var failureHandler: ((any Error) -> Void)?
    private var acceptsConnections = true

    private(set) var listeningPort: UInt16?

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
        auditLog: RelayAuditLog? = nil,
        handshakeTimeoutNanoseconds: UInt64 = 10_000_000_000,
        maxPendingHandshakes: Int = 32
    ) {
        self.channelID = channelID
        self.token = token
        self.acl = acl
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.auditLog = auditLog
        self.handshakeTimeoutNanoseconds = handshakeTimeoutNanoseconds
        self.maxPendingHandshakes = max(1, maxPendingHandshakes)
    }

    /// Starts on an OS-assigned loopback port and returns only after the listener is ready.
    func startOnEphemeralLoopbackPort() async throws -> UInt16 {
        guard listener == nil else { throw RelayAuthBrokerError.alreadyRunning }
        acceptsConnections = true

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: .any
        )
        let candidate = try NWListener(using: parameters)
        listener = candidate

        candidate.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<UInt16, any Error>) in
                    let gate = ListenerStartupGate()

                    candidate.stateUpdateHandler = { [weak self] state in
                        Task { @MainActor in
                            guard let self else {
                                guard gate.claim() else { return }
                                continuation.resume(throwing: CancellationError())
                                return
                            }

                            switch state {
                            case .ready:
                                guard gate.claim() else { return }
                                guard let port = candidate.port?.rawValue, port > 0 else {
                                    self.listener = nil
                                    candidate.cancel()
                                    continuation.resume(
                                        throwing: RelayAuthBrokerError.listenerPortUnavailable
                                    )
                                    return
                                }
                                self.listeningPort = port
                                continuation.resume(returning: port)
                            case .failed(let error):
                                let failedPort = self.listeningPort
                                self.listener = nil
                                self.listeningPort = nil
                                if gate.claim() {
                                    continuation.resume(throwing: error)
                                } else if let failedPort {
                                    self.acceptsConnections = false
                                    self.revokeAllConnections()
                                    if self.reserveFailedPort(failedPort) {
                                        self.failureHandler?(error)
                                    } else {
                                        self.failureHandler?(
                                            RelayAuthBrokerError.portQuarantineUnavailable
                                        )
                                    }
                                }
                            case .cancelled:
                                self.listener = nil
                                self.listeningPort = nil
                                guard gate.claim() else { return }
                                continuation.resume(throwing: CancellationError())
                            default:
                                break
                            }
                        }
                    }

                    candidate.start(queue: .main)
                }
            } onCancel: {
                candidate.cancel()
            }
        } catch {
            if listener === candidate {
                listener = nil
                listeningPort = nil
                candidate.cancel()
            }
            throw error
        }
    }

    /// Replaces the token and ACL consulted by all subsequent handshakes.
    func updateAuthorization(token: RelayToken, acl: RelayACL) {
        let tokenChanged = self.token.secret != token.secret
        if tokenChanged {
            revokeAllConnections()
        }
        self.token = token
        self.acl = acl
        if tokenChanged {
            replayTracker = ReplayTracker(windowSeconds: 60)
        }
    }

    func setConnectionCountHandler(_ handler: ((Int) -> Void)?) {
        connectionCountHandler = handler
    }

    func setFailureHandler(_ handler: ((any Error) -> Void)?) {
        failureHandler = handler
    }

    /// Denies all traffic while retaining the bound port for a cancellation retry.
    func deactivate() {
        acceptsConnections = false
        revokeAllConnections()
    }

    /// Stops listening and cleans up.
    func stop() {
        acceptsConnections = false
        listener?.cancel()
        listener = nil
        portQuarantine?.stop()
        portQuarantine = nil
        listeningPort = nil
        revokeAllConnections()
        connectionCountHandler = nil
        failureHandler = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        guard acceptsConnections else {
            connection.cancel()
            return
        }
        let connectionID = ObjectIdentifier(connection)
        guard pendingHandshakes.count < maxPendingHandshakes else {
            auditLog?.log(.connectionRejected(
                channelID: channelID,
                remoteHost: extractRemoteHost(from: connection),
                reason: "Pending handshake limit exceeded"
            ))
            connection.cancel()
            return
        }

        track(connection)
        pendingHandshakes.insert(connectionID)
        scheduleHandshakeTimeout(for: connection, id: connectionID)
        connection.start(queue: .main)

        // Read the fixed-size authenticated handshake.
        connection.receive(minimumIncompleteLength: RelayHandshake.totalSize,
                          maximumLength: RelayHandshake.totalSize) {
            [weak self] data, _, _, error in

            Task { @MainActor in
                guard let self else { return }
                guard self.acceptsConnections,
                      self.pendingHandshakes.contains(connectionID),
                      self.isTracked(connection)
                else {
                    self.cancelAndForget(connection)
                    return
                }
                self.finishPendingHandshake(id: connectionID)

                let earlyRemoteHost = self.extractRemoteHost(from: connection)

                guard let data, data.count >= RelayHandshake.totalSize else {
                    self.auditLog?.log(.connectionRejected(
                        channelID: self.channelID,
                        remoteHost: earlyRemoteHost,
                        reason: "Incomplete handshake"
                    ))
                    self.cancelAndForget(connection)
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
                    // SSH does not preserve the remote process or host identity at this hop.
                    // Enforce only policy backed by observable broker state.
                    guard self.acl.canAcceptConnection(currentCount: self.activeConnections) else {
                        self.auditLog?.log(.connectionRejected(
                            channelID: self.channelID,
                            remoteHost: remoteHost,
                            reason: "Max connections exceeded"
                        ))
                        self.cancelAndForget(connection)
                        return
                    }
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
                    self.cancelAndForget(connection)
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
        let relayState = DuplexRelayState()
        registerRelay(relayState)
        guard targetPort > 0 else {
            finishRelay(relayState, first: clientConnection, second: nil)
            return
        }

        let target = NWConnection(
            host: NWEndpoint.Host(targetHost),
            port: NWEndpoint.Port(rawValue: targetPort)!,
            using: .tcp
        )
        track(target)

        target.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard self.isAuthorizedRelay(
                        relayState,
                        first: clientConnection,
                        second: target
                    ) else {
                        self.cancelAndForget(clientConnection)
                        self.cancelAndForget(target)
                        return
                    }
                    self.pipeData(from: clientConnection, to: target, relayState: relayState)
                    self.pipeData(from: target, to: clientConnection, relayState: relayState)
                case .failed, .cancelled:
                    self.finishRelay(relayState, first: clientConnection, second: target)
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
        relayState: DuplexRelayState
    ) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else {
                    source.cancel()
                    dest.cancel()
                    return
                }
                guard self.isAuthorizedRelay(
                    relayState,
                    first: source,
                    second: dest
                ) else {
                    self.cancelAndForget(source)
                    self.cancelAndForget(dest)
                    return
                }

                if error != nil {
                    self.finishRelay(relayState, first: source, second: dest)
                    return
                }

                if let data, !data.isEmpty {
                    dest.send(content: data, completion: .contentProcessed { sendError in
                        Task { @MainActor [weak self] in
                            guard let self else {
                                source.cancel()
                                dest.cancel()
                                return
                            }
                            guard self.isAuthorizedRelay(
                                relayState,
                                first: source,
                                second: dest
                            ) else {
                                self.cancelAndForget(source)
                                self.cancelAndForget(dest)
                                return
                            }
                            if sendError != nil {
                                self.finishRelay(relayState, first: source, second: dest)
                            } else if isComplete {
                                self.finishRelayDirection(
                                    relayState,
                                    source: source,
                                    dest: dest
                                )
                            } else {
                                self.pipeData(from: source, to: dest, relayState: relayState)
                            }
                        }
                    })
                } else if isComplete {
                    self.finishRelayDirection(relayState, source: source, dest: dest)
                }
            }
        }
    }

    private func finishRelay(
        _ relayState: DuplexRelayState,
        first: NWConnection,
        second: NWConnection?
    ) {
        guard relayState.closeForFailure() else { return }
        cancelAndForget(first)
        if let second {
            cancelAndForget(second)
        }
        unregisterRelay(relayState)
    }

    private func finishRelayDirection(
        _ relayState: DuplexRelayState,
        source: NWConnection,
        dest: NWConnection
    ) {
        guard isAuthorizedRelay(relayState, first: source, second: dest) else {
            cancelAndForget(source)
            cancelAndForget(dest)
            return
        }
        dest.send(
            content: nil,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.isAuthorizedRelay(
                        relayState,
                        first: source,
                        second: dest
                    ) else {
                        self.cancelAndForget(source)
                        self.cancelAndForget(dest)
                        return
                    }
                    if error != nil {
                        self.finishRelay(relayState, first: source, second: dest)
                    } else if relayState.completeDirection() {
                        self.cancelAndForget(source)
                        self.cancelAndForget(dest)
                        self.unregisterRelay(relayState)
                    }
                }
            }
        )
    }

    private func track(_ connection: NWConnection) {
        trackedConnections[ObjectIdentifier(connection)] = connection
    }

    private func isTracked(_ connection: NWConnection) -> Bool {
        trackedConnections[ObjectIdentifier(connection)] != nil
    }

    private func isAuthorizedRelay(
        _ relayState: DuplexRelayState,
        first: NWConnection,
        second: NWConnection
    ) -> Bool {
        acceptsConnections
            && activeRelays[ObjectIdentifier(relayState)] === relayState
            && isTracked(first)
            && isTracked(second)
    }

    private func cancelAndForget(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        finishPendingHandshake(id: connectionID)
        trackedConnections.removeValue(forKey: connectionID)
        connection.cancel()
    }

    private func scheduleHandshakeTimeout(for connection: NWConnection, id: ObjectIdentifier) {
        handshakeTimeoutTasks[id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.handshakeTimeoutNanoseconds ?? 0)
            } catch {
                return
            }
            guard let self, self.pendingHandshakes.contains(id) else { return }
            self.auditLog?.log(.connectionRejected(
                channelID: self.channelID,
                remoteHost: self.extractRemoteHost(from: connection),
                reason: "Handshake timed out"
            ))
            self.cancelAndForget(connection)
        }
    }

    private func finishPendingHandshake(id: ObjectIdentifier) {
        pendingHandshakes.remove(id)
        handshakeTimeoutTasks.removeValue(forKey: id)?.cancel()
    }

    private func updateActiveConnections(_ count: Int) {
        activeConnections = count
        connectionCountHandler?(count)
    }

    private func registerRelay(_ relayState: DuplexRelayState) {
        activeRelays[ObjectIdentifier(relayState)] = relayState
        updateActiveConnections(activeRelays.count)
    }

    private func unregisterRelay(_ relayState: DuplexRelayState) {
        guard activeRelays.removeValue(forKey: ObjectIdentifier(relayState)) != nil else {
            return
        }
        updateActiveConnections(activeRelays.count)
    }

    private func revokeAllConnections() {
        for task in handshakeTimeoutTasks.values {
            task.cancel()
        }
        handshakeTimeoutTasks.removeAll()
        pendingHandshakes.removeAll()

        let connections = Array(trackedConnections.values)
        trackedConnections.removeAll()
        for connection in connections {
            connection.cancel()
        }

        for relayState in activeRelays.values {
            relayState.invalidate()
        }
        activeRelays.removeAll()
        updateActiveConnections(0)
    }

    @discardableResult
    private func reserveFailedPort(_ port: UInt16) -> Bool {
        portQuarantine?.stop()
        let quarantine = RelayPortQuarantine()
        guard quarantine.start(on: port) == port else { return false }
        portQuarantine = quarantine
        listeningPort = port
        return true
    }
}
