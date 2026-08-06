// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorLocalRelay.swift - Private-network bridge to a loopback gateway.

import Darwin
import Dispatch
import Foundation
import Network
import Security

struct MobileMirrorLocalRelayLease: Equatable, Sendable {
    let id: UUID
    let address: String
    let port: UInt16
}

enum MobileMirrorLocalRelayError: Error, Equatable, LocalizedError {
    case noPrivateNetwork
    case invalidGatewayPort
    case alreadyStarting
    case tlsIdentityUnavailable
    case listenerUnavailable

    var errorDescription: String? {
        localizedDescription(using: AppLocalizer(languagePreference: .english))
    }

    func localizedDescription(using localizer: AppLocalizer) -> String {
        switch self {
        case .noPrivateNetwork:
            return localizer.string(
                "mobile.mirror.error.noPrivateNetwork",
                fallback: "No private local network is available."
            )
        case .invalidGatewayPort:
            return localizer.string(
                "mobile.mirror.error.invalidGatewayPort",
                fallback: "The local mobile gateway port is invalid."
            )
        case .alreadyStarting:
            return localizer.string(
                "mobile.mirror.error.alreadyStarting",
                fallback: "The private mobile relay is already starting."
            )
        case .tlsIdentityUnavailable:
            return localizer.string(
                "mobile.mirror.error.tlsIdentityUnavailable",
                fallback: "Could not create encryption for the private mobile relay."
            )
        case .listenerUnavailable:
            return localizer.string(
                "mobile.mirror.error.listenerUnavailable",
                fallback: "Could not start the private mobile relay."
            )
        }
    }
}

enum MobileMirrorRelayPreambleError: Error, Equatable {
    case malformed
    case invalidSecret
    case invalidAddress
}

enum MobileMirrorRelayPreamble {
    static let maximumBytes = 512
    private static let prefix = Data("COCXY-RELAY/1 ".utf8)

    static func encode(secret: String, remoteAddress: String) -> Data {
        let encodedAddress = MobileMirrorPairingAuthority.base64URL(Data(remoteAddress.utf8))
        return Data("COCXY-RELAY/1 \(secret) \(encodedAddress)\r\n".utf8)
    }

    static func consumeIfComplete(
        from data: inout Data,
        expectedSecret: String
    ) throws -> String? {
        let comparedCount = min(data.count, prefix.count)
        guard prefix.prefix(comparedCount).elementsEqual(data.prefix(comparedCount)) else {
            throw MobileMirrorRelayPreambleError.malformed
        }
        guard let boundary = data.range(of: Data("\r\n".utf8)) else {
            guard data.count <= maximumBytes else {
                throw MobileMirrorRelayPreambleError.malformed
            }
            return nil
        }
        guard boundary.upperBound <= maximumBytes,
              let line = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
            throw MobileMirrorRelayPreambleError.malformed
        }
        let components = line.split(separator: " ", omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "COCXY-RELAY/1" else {
            throw MobileMirrorRelayPreambleError.malformed
        }
        let suppliedSecret = String(components[1])
        guard constantTimeEqual(suppliedSecret, expectedSecret) else {
            throw MobileMirrorRelayPreambleError.invalidSecret
        }
        guard let addressData = MobileMirrorPairingAuthority.decodeBase64URL(
            String(components[2])
        ), let address = String(data: addressData, encoding: .utf8),
              address.utf8.count <= 64,
              MobileMirrorPrivateNetworkAddress.isPrivateIPv4(address) else {
            throw MobileMirrorRelayPreambleError.invalidAddress
        }
        data.removeSubrange(..<boundary.upperBound)
        return address
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let comparisonCount = max(left.count, right.count)
        var difference = UInt64(left.count ^ right.count)
        for index in 0..<comparisonCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= UInt64(leftByte ^ rightByte)
        }
        return difference == 0
    }
}

enum MobileMirrorPrivateNetworkAddress {
    static func current() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var candidates: [(priority: Int, name: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == sa_family_t(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  interface.ifa_flags & UInt32(IFF_POINTOPOINT) == 0 else {
                continue
            }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"), !name.hasPrefix("ap") else {
                continue
            }
            var address = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let converted = socketAddress.withMemoryRebound(
                to: sockaddr_in.self,
                capacity: 1
            ) { ipv4 in
                inet_ntop(AF_INET, &ipv4.pointee.sin_addr, &address, socklen_t(address.count))
            }
            guard converted != nil else { continue }
            let value = String(cString: address)
            guard isPrivateIPv4(value) else { continue }
            let priority = name == "en0" ? 0 : (name.hasPrefix("en") ? 1 : 2)
            candidates.append((priority, name, value))
        }
        return candidates.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.address < $1.address
        }.first?.address
    }

    static func isPrivateIPv4(_ value: String) -> Bool {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return false }
        let host = UInt32(bigEndian: address.s_addr)
        let first = UInt8((host >> 24) & 0xff)
        let second = UInt8((host >> 16) & 0xff)
        return first == 10
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
    }
}

final class MobileMirrorLocalRelay: @unchecked Sendable {
    typealias AddressProvider = @Sendable () -> String?
    typealias BindAddressPolicy = @Sendable (String) -> Bool
    typealias PeerAddressNormalizer = @Sendable (String) -> String?
    typealias TLSIdentityProvider = @Sendable (String) throws -> MobileMirrorEphemeralTLSIdentity

    static let idleTimeout: TimeInterval = 45
    private static let handshakeTimeout: TimeInterval = 8

    private final class StartupGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }

    private let id = UUID()
    private let gatewayPort: UInt16
    private let preambleSecret: String
    private let addressProvider: AddressProvider
    private let bindAddressPolicy: BindAddressPolicy
    private let peerAddressNormalizer: PeerAddressNormalizer
    private let tlsIdentityProvider: TLSIdentityProvider
    private let connectionLimits: MobileMirrorConnectionLimits
    private let connectionIdleTimeout: TimeInterval
    private let listenerQueue = DispatchQueue(label: "dev.cocxy.mobile.relay.listener")
    private let lock = NSLock()
    private var listener: NWListener?
    private var tlsIdentity: MobileMirrorEphemeralTLSIdentity?
    private var connections: [UUID: MobileMirrorLocalRelayConnection] = [:]
    private var connectionPolicy: MobileMirrorConnectionPolicy
    private var isStarting = false
    private(set) var lease: MobileMirrorLocalRelayLease?

    init(
        gatewayPort: UInt16,
        preambleSecret: String,
        addressProvider: @escaping AddressProvider = {
            MobileMirrorPrivateNetworkAddress.current()
        },
        bindAddressPolicy: @escaping BindAddressPolicy = {
            MobileMirrorPrivateNetworkAddress.isPrivateIPv4($0)
        },
        peerAddressNormalizer: @escaping PeerAddressNormalizer = { $0 },
        tlsIdentityProvider: @escaping TLSIdentityProvider = {
            try MobileMirrorEphemeralTLSIdentity.generate(bindAddress: $0)
        },
        connectionLimits: MobileMirrorConnectionLimits = .default,
        connectionIdleTimeout: TimeInterval = MobileMirrorLocalRelay.idleTimeout
    ) {
        self.gatewayPort = gatewayPort
        self.preambleSecret = preambleSecret
        self.addressProvider = addressProvider
        self.bindAddressPolicy = bindAddressPolicy
        self.peerAddressNormalizer = peerAddressNormalizer
        self.tlsIdentityProvider = tlsIdentityProvider
        self.connectionLimits = connectionLimits
        self.connectionIdleTimeout = max(1, connectionIdleTimeout)
        self.connectionPolicy = MobileMirrorConnectionPolicy(limits: connectionLimits)
    }

    func start() async throws -> MobileMirrorLocalRelayLease {
        if let existingLease = try beginStart() { return existingLease }

        guard gatewayPort > 0 else {
            finishFailedStart()
            throw MobileMirrorLocalRelayError.invalidGatewayPort
        }
        guard let bindAddress = addressProvider(),
              bindAddressPolicy(bindAddress) else {
            finishFailedStart()
            throw MobileMirrorLocalRelayError.noPrivateNetwork
        }

        let identity: MobileMirrorEphemeralTLSIdentity
        do {
            identity = try tlsIdentityProvider(bindAddress)
        } catch {
            finishFailedStart()
            throw MobileMirrorLocalRelayError.tlsIdentityUnavailable
        }

        let candidate: NWListener
        do {
            candidate = try Self.makeListener(bindAddress: bindAddress, identity: identity)
        } catch {
            identity.removeFromKeychain()
            finishFailedStart()
            throw MobileMirrorLocalRelayError.listenerUnavailable
        }

        guard install(listener: candidate, identity: identity) else {
            candidate.cancel()
            identity.removeFromKeychain()
            throw CancellationError()
        }

        candidate.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        let startupGate = StartupGate()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<MobileMirrorLocalRelayLease, any Error>) in
                    candidate.stateUpdateHandler = { [weak self] state in
                        guard let self else {
                            guard startupGate.claim() else { return }
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        switch state {
                        case .ready:
                            guard startupGate.claim() else { return }
                            guard let port = candidate.port?.rawValue, port > 0,
                                  let lease = self.finishSuccessfulStart(
                                    listener: candidate,
                                    identity: identity,
                                    bindAddress: bindAddress,
                                    port: port
                                  ) else {
                                self.discard(listener: candidate, identity: identity)
                                continuation.resume(
                                    throwing: MobileMirrorLocalRelayError.listenerUnavailable
                                )
                                return
                            }
                            continuation.resume(returning: lease)
                        case .failed:
                            if startupGate.claim() {
                                self.discard(listener: candidate, identity: identity)
                                continuation.resume(
                                    throwing: MobileMirrorLocalRelayError.listenerUnavailable
                                )
                            } else {
                                self.stopIfCurrent(candidate)
                            }
                        case .cancelled:
                            guard startupGate.claim() else { return }
                            self.discard(listener: candidate, identity: identity)
                            continuation.resume(throwing: CancellationError())
                        default:
                            break
                        }
                    }
                    candidate.start(queue: listenerQueue)
                }
            } onCancel: {
                candidate.cancel()
            }
        } catch {
            discard(listener: candidate, identity: identity)
            throw error
        }
    }

    func stop() {
        let candidate: NWListener?
        let identity: MobileMirrorEphemeralTLSIdentity?
        let activeConnections: [MobileMirrorLocalRelayConnection]
        lock.lock()
        candidate = listener
        listener = nil
        identity = tlsIdentity
        tlsIdentity = nil
        lease = nil
        isStarting = false
        activeConnections = Array(connections.values)
        connections.removeAll()
        connectionPolicy.reset()
        lock.unlock()

        candidate?.stateUpdateHandler = nil
        candidate?.newConnectionHandler = nil
        candidate?.cancel()
        activeConnections.forEach { $0.close() }
        identity?.removeFromKeychain()
    }

    private static func makeListener(
        bindAddress: String,
        identity: MobileMirrorEphemeralTLSIdentity
    ) throws -> NWListener {
        let tlsOptions = NWProtocolTLS.Options()
        guard let localIdentity = sec_identity_create(identity.identity) else {
            throw MobileMirrorLocalRelayError.tlsIdentityUnavailable
        }
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            localIdentity
        )
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )
        sec_protocol_options_set_max_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3
        tcpOptions.connectionTimeout = Int(handshakeTimeout)

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(bindAddress),
            port: .any
        )
        return try NWListener(using: parameters)
    }

    private func beginStart() throws -> MobileMirrorLocalRelayLease? {
        lock.lock()
        defer { lock.unlock() }
        if let lease { return lease }
        guard !isStarting else { throw MobileMirrorLocalRelayError.alreadyStarting }
        isStarting = true
        return nil
    }

    private func install(
        listener candidate: NWListener,
        identity: MobileMirrorEphemeralTLSIdentity
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isStarting else { return false }
        listener = candidate
        tlsIdentity = identity
        return true
    }

    private func finishSuccessfulStart(
        listener candidate: NWListener,
        identity: MobileMirrorEphemeralTLSIdentity,
        bindAddress: String,
        port: UInt16
    ) -> MobileMirrorLocalRelayLease? {
        lock.lock()
        defer { lock.unlock() }
        guard listener === candidate, tlsIdentity === identity, isStarting else {
            return nil
        }
        let resolved = MobileMirrorLocalRelayLease(
            id: id,
            address: bindAddress,
            port: port
        )
        lease = resolved
        isStarting = false
        return resolved
    }

    private func finishFailedStart() {
        lock.lock()
        isStarting = false
        lock.unlock()
    }

    private func discard(
        listener candidate: NWListener,
        identity: MobileMirrorEphemeralTLSIdentity
    ) {
        var shouldRemoveIdentity = false
        lock.lock()
        if listener === candidate {
            listener = nil
            lease = nil
            isStarting = false
        }
        if tlsIdentity === identity {
            tlsIdentity = nil
            shouldRemoveIdentity = true
        }
        lock.unlock()

        candidate.stateUpdateHandler = nil
        candidate.newConnectionHandler = nil
        candidate.cancel()
        if shouldRemoveIdentity {
            identity.removeFromKeychain()
        }
    }

    private func stopIfCurrent(_ candidate: NWListener) {
        lock.lock()
        let isCurrent = listener === candidate
        lock.unlock()
        if isCurrent { stop() }
    }

    private func handleConnection(_ client: NWConnection) {
        guard let numericAddress = Self.numericIPv4(client),
              let remoteAddress = peerAddressNormalizer(numericAddress),
              MobileMirrorPrivateNetworkAddress.isPrivateIPv4(remoteAddress),
              reserveConnectionSlot(for: remoteAddress) else {
            client.cancel()
            return
        }

        let connectionID = UUID()
        let connection = MobileMirrorLocalRelayConnection(
            client: client,
            gatewayPort: gatewayPort,
            remoteAddress: remoteAddress,
            preamble: MobileMirrorRelayPreamble.encode(
                secret: preambleSecret,
                remoteAddress: remoteAddress
            ),
            idleTimeout: connectionIdleTimeout,
            handshakeTimeout: Self.handshakeTimeout,
            onClose: { [weak self] in self?.removeConnection(connectionID) }
        )

        lock.lock()
        guard lease != nil, listener != nil else {
            connectionPolicy.release(address: remoteAddress)
            lock.unlock()
            connection.close()
            return
        }
        connections[connectionID] = connection
        lock.unlock()
        connection.start()
    }

    private func reserveConnectionSlot(for remoteAddress: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard lease != nil else { return false }
        return connectionPolicy.admit(
            address: remoteAddress,
            now: ProcessInfo.processInfo.systemUptime
        ) == .accepted
    }

    private func removeConnection(_ id: UUID) {
        lock.lock()
        let remoteAddress = connections.removeValue(forKey: id)?.remoteAddress
        if let remoteAddress {
            connectionPolicy.release(address: remoteAddress)
        }
        lock.unlock()
    }

    static func numericIPv4(bytes: Data) -> String? {
        guard bytes.count == 4 else { return nil }
        return bytes.map(String.init).joined(separator: ".")
    }

    private static func numericIPv4(_ connection: NWConnection) -> String? {
        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case .hostPort(let host, _) = endpoint,
              case .ipv4(let address) = host else {
            return nil
        }
        return numericIPv4(bytes: address.rawValue)
    }
}
