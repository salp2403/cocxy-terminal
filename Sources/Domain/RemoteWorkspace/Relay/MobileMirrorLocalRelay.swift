// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorLocalRelay.swift - Private-network bridge to a loopback gateway.

import Darwin
import Dispatch
import Foundation

struct MobileMirrorLocalRelayLease: Equatable, Sendable {
    let id: UUID
    let address: String
    let port: UInt16
}

enum MobileMirrorLocalRelayError: Error, Equatable, LocalizedError {
    case noPrivateNetwork
    case invalidGatewayPort
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .noPrivateNetwork:
            return MobileMirrorError.noPrivateNetwork.localizedDescription
        case .invalidGatewayPort:
            return "The local mobile gateway port is invalid."
        case .socketCreationFailed(let code):
            return "Could not create the private mobile relay (\(code))."
        case .bindFailed(let code):
            return "Could not bind the private mobile relay (\(code))."
        case .listenFailed(let code):
            return "Could not start the private mobile relay (\(code))."
        case .portUnavailable:
            return "The private mobile relay did not receive a port."
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

    static let idleTimeout: TimeInterval = 45

    private let id = UUID()
    private let gatewayPort: UInt16
    private let preambleSecret: String
    private let addressProvider: AddressProvider
    private let bindAddressPolicy: BindAddressPolicy
    private let peerAddressNormalizer: PeerAddressNormalizer
    private let connectionLimits: MobileMirrorConnectionLimits
    private let connectionIdleTimeout: TimeInterval
    private let listenerQueue = DispatchQueue(label: "dev.cocxy.mobile.relay.listener")
    private let workerQueue = DispatchQueue(
        label: "dev.cocxy.mobile.relay.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var listenerSource: DispatchSourceRead?
    private var connections: [UUID: MobileMirrorLocalRelayConnection] = [:]
    private var connectionPolicy: MobileMirrorConnectionPolicy
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
        connectionLimits: MobileMirrorConnectionLimits = .default,
        connectionIdleTimeout: TimeInterval = MobileMirrorLocalRelay.idleTimeout
    ) {
        self.gatewayPort = gatewayPort
        self.preambleSecret = preambleSecret
        self.addressProvider = addressProvider
        self.bindAddressPolicy = bindAddressPolicy
        self.peerAddressNormalizer = peerAddressNormalizer
        self.connectionLimits = connectionLimits
        self.connectionIdleTimeout = max(1, connectionIdleTimeout)
        self.connectionPolicy = MobileMirrorConnectionPolicy(limits: connectionLimits)
    }

    func start() throws -> MobileMirrorLocalRelayLease {
        lock.lock()
        defer { lock.unlock() }
        if let lease { return lease }
        guard gatewayPort > 0 else { throw MobileMirrorLocalRelayError.invalidGatewayPort }
        guard let bindAddress = addressProvider(),
              bindAddressPolicy(bindAddress) else {
            throw MobileMirrorLocalRelayError.noPrivateNetwork
        }

        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw MobileMirrorLocalRelayError.socketCreationFailed(errno)
        }
        var ownsDescriptor = true
        defer { if ownsDescriptor { Darwin.close(descriptor) } }
        var one: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw MobileMirrorLocalRelayError.socketCreationFailed(errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        guard inet_pton(AF_INET, bindAddress, &address.sin_addr) == 1 else {
            throw MobileMirrorLocalRelayError.noPrivateNetwork
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw MobileMirrorLocalRelayError.bindFailed(errno) }
        guard Darwin.listen(descriptor, Int32(max(1, connectionLimits.maximumTotal))) == 0 else {
            throw MobileMirrorLocalRelayError.listenFailed(errno)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0, bound.sin_port != 0 else {
            throw MobileMirrorLocalRelayError.portUnavailable
        }

        let resolved = MobileMirrorLocalRelayLease(
            id: id,
            address: bindAddress,
            port: UInt16(bigEndian: bound.sin_port)
        )
        lease = resolved
        ownsDescriptor = false
        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: listenerQueue
        )
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections(from: descriptor)
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        listenerSource = source
        source.resume()
        return resolved
    }

    func stop() {
        let source: DispatchSourceRead?
        let activeConnections: [MobileMirrorLocalRelayConnection]
        lock.lock()
        source = listenerSource
        listenerSource = nil
        lease = nil
        activeConnections = Array(connections.values)
        connections.removeAll()
        connectionPolicy.reset()
        lock.unlock()
        source?.cancel()
        activeConnections.forEach { $0.close() }
    }

    private func acceptAvailableConnections(from listener: Int32) {
        while true {
            var remote = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &remote) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listener, $0, &length)
                }
            }
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard let numericAddress = Self.numericIPv4(remote),
                  let remoteAddress = peerAddressNormalizer(numericAddress),
                  MobileMirrorPrivateNetworkAddress.isPrivateIPv4(remoteAddress),
                  reserveConnectionSlot(for: remoteAddress) else {
                Darwin.close(client)
                continue
            }
            Self.configureSocket(client, receiveTimeout: min(15, connectionIdleTimeout))
            workerQueue.async { [weak self] in
                guard let self else {
                    Darwin.close(client)
                    return
                }
                self.openConnection(client: client, remoteAddress: remoteAddress)
            }
        }
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

    private func openConnection(client: Int32, remoteAddress: String) {
        let connectionID = UUID()
        let connection: MobileMirrorLocalRelayConnection
        do {
            connection = try MobileMirrorLocalRelayConnection(
                client: client,
                gatewayPort: gatewayPort,
                remoteAddress: remoteAddress,
                preamble: MobileMirrorRelayPreamble.encode(
                    secret: preambleSecret,
                    remoteAddress: remoteAddress
                ),
                queue: workerQueue,
                idleTimeout: connectionIdleTimeout,
                onClose: { [weak self] in self?.removeConnection(connectionID) }
            )
        } catch {
            Darwin.close(client)
            lock.lock()
            connectionPolicy.release(address: remoteAddress)
            lock.unlock()
            return
        }
        lock.lock()
        guard lease != nil else {
            connectionPolicy.release(address: remoteAddress)
            lock.unlock()
            connection.start()
            connection.close()
            return
        }
        connections[connectionID] = connection
        lock.unlock()
        connection.start()
    }

    private func removeConnection(_ id: UUID) {
        lock.lock()
        let remoteAddress = connections.removeValue(forKey: id)?.remoteAddress
        if let remoteAddress { connectionPolicy.release(address: remoteAddress) }
        lock.unlock()
    }

    fileprivate static func configureSocket(_ descriptor: Int32, receiveTimeout: TimeInterval) {
        var one: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        setsockopt(descriptor, SOL_SOCKET, SO_KEEPALIVE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var keepalive: Int32 = 15
        setsockopt(descriptor, IPPROTO_TCP, TCP_KEEPALIVE, &keepalive, socklen_t(MemoryLayout.size(ofValue: keepalive)))
        var interval: Int32 = 5
        setsockopt(descriptor, IPPROTO_TCP, TCP_KEEPINTVL, &interval, socklen_t(MemoryLayout.size(ofValue: interval)))
        var probes: Int32 = 3
        setsockopt(descriptor, IPPROTO_TCP, TCP_KEEPCNT, &probes, socklen_t(MemoryLayout.size(ofValue: probes)))
        let seconds = floor(receiveTimeout)
        var timeout = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((receiveTimeout - seconds) * 1_000_000)
        )
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) }
    }

    private static func numericIPv4(_ storage: sockaddr_storage) -> String? {
        guard storage.ss_family == sa_family_t(AF_INET) else { return nil }
        var copy = storage
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipv4 in
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var address = ipv4.pointee.sin_addr
                guard inet_ntop(
                    AF_INET,
                    &address,
                    &buffer,
                    socklen_t(buffer.count)
                ) != nil else { return nil }
                return String(cString: buffer)
            }
        }
    }
}

private final class MobileMirrorLocalRelayConnection: @unchecked Sendable {
    let remoteAddress: String

    private let client: Int32
    private let upstream: Int32
    private let queue: DispatchQueue
    private let idleTimeout: TimeInterval
    private let onClose: @Sendable () -> Void
    private let lock = NSLock()
    private var completedDirections = 0
    private var isClosing = false
    private var didNotifyClose = false
    private var lastActivity = ProcessInfo.processInfo.systemUptime

    init(
        client: Int32,
        gatewayPort: UInt16,
        remoteAddress: String,
        preamble: Data,
        queue: DispatchQueue,
        idleTimeout: TimeInterval,
        onClose: @escaping @Sendable () -> Void
    ) throws {
        self.client = client
        self.remoteAddress = remoteAddress
        self.queue = queue
        self.idleTimeout = idleTimeout
        self.onClose = onClose
        let upstream = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard upstream >= 0 else {
            throw MobileMirrorLocalRelayError.socketCreationFailed(errno)
        }
        self.upstream = upstream
        MobileMirrorLocalRelay.configureSocket(upstream, receiveTimeout: min(15, idleTimeout))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = gatewayPort.bigEndian
        inet_pton(AF_INET, MobileMirrorGateway.loopbackAddress, &address.sin_addr)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(upstream, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0, Self.sendAll(preamble, to: upstream) else {
            Darwin.close(upstream)
            throw MobileMirrorError.unavailable
        }
    }

    func start() {
        queue.async { [self] in pump(from: client, to: upstream) }
        queue.async { [self] in pump(from: upstream, to: client) }
    }

    func close() {
        requestClose()
    }

    private func pump(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = Darwin.recv(source, &buffer, buffer.count, 0)
            if count > 0 {
                recordActivity()
                guard Self.sendAll(Data(buffer[0..<count]), to: destination) else {
                    requestClose()
                    break
                }
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count < 0, (errno == EAGAIN || errno == EWOULDBLOCK), !hasExpired {
                continue
            }
            requestClose()
            break
        }
        finishDirection()
    }

    private func requestClose() {
        lock.lock()
        guard !isClosing else {
            lock.unlock()
            return
        }
        isClosing = true
        lock.unlock()
        Darwin.shutdown(client, SHUT_RDWR)
        Darwin.shutdown(upstream, SHUT_RDWR)
    }

    private func recordActivity() {
        lock.lock()
        lastActivity = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    private var hasExpired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastActivity >= idleTimeout
    }

    private func finishDirection() {
        var shouldClose = false
        lock.lock()
        completedDirections += 1
        if completedDirections == 2, !didNotifyClose {
            didNotifyClose = true
            shouldClose = true
        }
        lock.unlock()
        guard shouldClose else { return }
        Darwin.close(client)
        Darwin.close(upstream)
        onClose()
    }

    private static func sendAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return true }
            var sent = 0
            while sent < rawBuffer.count {
                let result = Darwin.send(descriptor, base.advanced(by: sent), rawBuffer.count - sent, 0)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                sent += result
            }
            return true
        }
    }
}
