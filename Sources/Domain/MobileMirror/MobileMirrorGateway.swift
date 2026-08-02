// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorGateway.swift - Private-LAN HTTP and WebSocket relay.

import Darwin
import Dispatch
import Foundation

enum MobileMirrorGatewayError: Error, Equatable, LocalizedError {
    case invalidBindAddress
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBindAddress: return "The mobile mirror requires a private IPv4 address."
        case .socketCreationFailed(let code): return "Could not create the local listener (\(code))."
        case .bindFailed(let code): return "Could not bind the local listener (\(code))."
        case .listenFailed(let code): return "Could not start the local listener (\(code))."
        case .portUnavailable: return "The local listener did not receive a port."
        }
    }
}

final class MobileMirrorEventHub: @unchecked Sendable {
    private struct Client {
        let descriptor: Int32
        let close: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var clients: [Int32: Client] = [:]
    private let heartbeatQueue = DispatchQueue(label: "dev.cocxy.mobile.events")
    private var heartbeat: DispatchSourceTimer?

    func add(descriptor: Int32, close: @escaping @Sendable () -> Void) {
        lock.lock()
        clients[descriptor] = Client(descriptor: descriptor, close: close)
        let needsHeartbeat = heartbeat == nil
        lock.unlock()
        if needsHeartbeat { startHeartbeat() }
        publish(event: "state", data: "{}")
    }

    func publish(event: String, data: String) {
        guard event.utf8.count <= 64,
              event.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              data.utf8.count <= 16 * 1_024,
              !data.contains("\r"),
              !data.contains("\n") else {
            return
        }
        send(Data("event: \(event)\ndata: \(data)\n\n".utf8))
    }

    func stop() {
        heartbeatQueue.sync {
            heartbeat?.cancel()
            heartbeat = nil
        }
        let current: [Client]
        lock.lock()
        current = Array(clients.values)
        clients.removeAll()
        lock.unlock()
        current.forEach { $0.close() }
    }

    private func startHeartbeat() {
        heartbeatQueue.async { [weak self] in
            guard let self, self.heartbeat == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.heartbeatQueue)
            timer.schedule(deadline: .now() + 15, repeating: 15)
            timer.setEventHandler { [weak self] in
                self?.send(Data(": keep-alive\n\n".utf8))
            }
            self.heartbeat = timer
            timer.resume()
        }
    }

    private func send(_ data: Data) {
        let current: [Client]
        lock.lock()
        current = Array(clients.values)
        lock.unlock()
        var failed: [Client] = []
        for client in current where !MobileMirrorGateway.sendAll(data, to: client.descriptor) {
            failed.append(client)
        }
        guard !failed.isEmpty else { return }
        lock.lock()
        for client in failed {
            clients.removeValue(forKey: client.descriptor)
        }
        lock.unlock()
        failed.forEach { $0.close() }
    }
}

final class MobileMirrorGateway: @unchecked Sendable {
    typealias RouteHandler = @Sendable (
        MobileMirrorHTTPRequest,
        MobileMirrorClientIdentity
    ) async -> MobileMirrorHTTPRouteResult

    static let maximumConnections = 16

    let bindAddress: String
    let eventHub: MobileMirrorEventHub

    private let requestedPort: UInt16
    private let routeHandler: RouteHandler
    private let allowsLoopbackForTesting: Bool
    private let listenerQueue = DispatchQueue(label: "dev.cocxy.mobile.listener")
    private let workerQueue = DispatchQueue(
        label: "dev.cocxy.mobile.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateLock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var clientDescriptors: Set<Int32> = []
    private(set) var port: UInt16?

    init(
        bindAddress: String,
        requestedPort: UInt16 = 0,
        eventHub: MobileMirrorEventHub = MobileMirrorEventHub(),
        allowsLoopbackForTesting: Bool = false,
        routeHandler: @escaping RouteHandler
    ) {
        self.bindAddress = bindAddress
        self.requestedPort = requestedPort
        self.eventHub = eventHub
        self.allowsLoopbackForTesting = allowsLoopbackForTesting
        self.routeHandler = routeHandler
    }

    @discardableResult
    func start() throws -> UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let port { return port }
        guard Self.isPrivateIPv4(bindAddress)
                || (allowsLoopbackForTesting && bindAddress == "127.0.0.1") else {
            throw MobileMirrorGatewayError.invalidBindAddress
        }

        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw MobileMirrorGatewayError.socketCreationFailed(errno)
        }
        var ownsDescriptor = true
        defer { if ownsDescriptor { Darwin.close(descriptor) } }
        var one: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw MobileMirrorGatewayError.socketCreationFailed(errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requestedPort.bigEndian
        guard inet_pton(AF_INET, bindAddress, &address.sin_addr) == 1 else {
            throw MobileMirrorGatewayError.invalidBindAddress
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw MobileMirrorGatewayError.bindFailed(errno) }
        guard Darwin.listen(descriptor, Int32(Self.maximumConnections)) == 0 else {
            throw MobileMirrorGatewayError.listenFailed(errno)
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0, bound.sin_port != 0 else {
            throw MobileMirrorGatewayError.portUnavailable
        }
        let resolvedPort = UInt16(bigEndian: bound.sin_port)
        listenerDescriptor = descriptor
        port = resolvedPort
        ownsDescriptor = false

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: listenerQueue)
        source.setEventHandler { [weak self] in self?.acceptAvailableConnections() }
        source.setCancelHandler { Darwin.close(descriptor) }
        listenerSource = source
        source.resume()
        return resolvedPort
    }

    func stop() {
        let source: DispatchSourceRead?
        let clients: [Int32]
        stateLock.lock()
        source = listenerSource
        listenerSource = nil
        listenerDescriptor = -1
        port = nil
        clients = Array(clientDescriptors)
        clientDescriptors.removeAll()
        stateLock.unlock()
        source?.cancel()
        clients.forEach {
            Darwin.shutdown($0, SHUT_RDWR)
            Darwin.close($0)
        }
        eventHub.stop()
    }

    static func privateIPv4Addresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var candidates: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET),
               flags & IFF_UP != 0,
               flags & IFF_RUNNING != 0,
               flags & IFF_LOOPBACK == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let value = String(cString: host)
                    if isPrivateIPv4(value) {
                        candidates.append((String(cString: interface.ifa_name), value))
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return Array(Set(candidates.map(\.address))).sorted { lhs, rhs in
            let lhsName = candidates.first { $0.address == lhs }?.name ?? ""
            let rhsName = candidates.first { $0.address == rhs }?.name ?? ""
            let lhsRank = lhsName == "en0" ? 0 : (lhsName.hasPrefix("en") ? 1 : 2)
            let rhsRank = rhsName == "en0" ? 0 : (rhsName.hasPrefix("en") ? 1 : 2)
            return lhsRank == rhsRank ? lhs < rhs : lhsRank < rhsRank
        }
    }

    static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 169 && parts[1] == 254)
    }

    private func acceptAvailableConnections() {
        while true {
            var remote = sockaddr_storage()
            var remoteLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let descriptor = withUnsafeMutablePointer(to: &remote) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listenerDescriptor, $0, &remoteLength)
                }
            }
            if descriptor < 0 {
                if errno == EINTR { continue }
                return
            }
            configureClientSocket(descriptor)
            stateLock.lock()
            let canAccept = clientDescriptors.count < Self.maximumConnections
            if canAccept { clientDescriptors.insert(descriptor) }
            stateLock.unlock()
            guard canAccept else {
                Darwin.close(descriptor)
                continue
            }
            let remoteAddress = Self.numericAddress(remote) ?? "local-network"
            workerQueue.async { [weak self] in
                self?.readRequest(from: descriptor, remoteAddress: remoteAddress)
            }
        }
    }

    private func configureClientSocket(_ descriptor: Int32) {
        var one: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) }
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }

    private func readRequest(from descriptor: Int32, remoteAddress: String) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        do {
            while true {
                if let request = try MobileMirrorHTTPRequest.parseIfComplete(data) {
                    let identity = MobileMirrorClientIdentity(
                        remoteAddress: remoteAddress,
                        userAgent: request.userAgent
                    )
                    Task { [weak self] in
                        guard let self else { return }
                        let result = await self.routeHandler(request, identity)
                        self.workerQueue.async {
                            self.complete(request: request, result: result, descriptor: descriptor)
                        }
                    }
                    return
                }
                let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw MobileMirrorHTTPError.malformedRequest }
                data.append(buffer, count: count)
            }
        } catch {
            respond(.error("Invalid local request.", status: 400), to: descriptor)
        }
    }

    private func complete(
        request: MobileMirrorHTTPRequest,
        result: MobileMirrorHTTPRouteResult,
        descriptor: Int32
    ) {
        switch result {
        case .response(let response):
            respond(response, to: descriptor)
        case .eventStream:
            let response = Data(
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n".utf8
            )
            guard Self.sendAll(response, to: descriptor) else {
                finish(descriptor)
                return
            }
            eventHub.add(descriptor: descriptor) { [weak self] in self?.finish(descriptor) }
        case .proxy(let target):
            proxy(request: request, to: target, client: descriptor)
        }
    }

    private func respond(_ response: MobileMirrorHTTPResponse, to descriptor: Int32) {
        _ = Self.sendAll(response.encoded(), to: descriptor)
        finish(descriptor)
    }

    private func proxy(
        request: MobileMirrorHTTPRequest,
        to target: MobileMirrorProxyTarget,
        client: Int32
    ) {
        let upstream = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard upstream >= 0 else {
            respond(.error("Terminal stream is unavailable.", status: 503), to: client)
            return
        }
        configureClientSocket(upstream)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = target.port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(upstream, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0,
              Self.sendAll(rewrittenRequest(request, target: target), to: upstream) else {
            Darwin.close(upstream)
            respond(.error("Terminal stream is unavailable.", status: 503), to: client)
            return
        }

        var noTimeout = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &noTimeout, socklen_t(MemoryLayout.size(ofValue: noTimeout)))
        setsockopt(upstream, SOL_SOCKET, SO_RCVTIMEO, &noTimeout, socklen_t(MemoryLayout.size(ofValue: noTimeout)))
        let lifetime = MobileMirrorProxyLifetime(
            client: client,
            upstream: upstream,
            closeClient: { [weak self] in self?.finish(client) }
        )
        workerQueue.async { Self.pump(from: client, to: upstream); lifetime.close() }
        workerQueue.async { Self.pump(from: upstream, to: client); lifetime.close() }
    }

    private func rewrittenRequest(
        _ request: MobileMirrorHTTPRequest,
        target: MobileMirrorProxyTarget
    ) -> Data {
        let excluded = Set([
            "authorization", "cookie", "host", "origin", "x-cocxy-timestamp",
            "x-cocxy-nonce", "x-cocxy-signature", "content-length",
        ])
        var value = "\(request.method) \(target.rewrittenPath) \(request.version)\r\n"
        for key in request.headers.keys.sorted() where !excluded.contains(key) {
            value += "\(key): \(request.headers[key] ?? "")\r\n"
        }
        value += "Host: 127.0.0.1:\(target.port)\r\n"
        value += "Origin: http://127.0.0.1:\(target.port)\r\n"
        value += "Authorization: Bearer \(target.bearerToken)\r\n"
        if !request.body.isEmpty {
            value += "Content-Length: \(request.body.count)\r\n"
        }
        value += "\r\n"
        return Data(value.utf8) + request.body
    }

    private func finish(_ descriptor: Int32) {
        stateLock.lock()
        let owned = clientDescriptors.remove(descriptor) != nil
        stateLock.unlock()
        guard owned else { return }
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    static func sendAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(descriptor, base.advanced(by: sent), data.count - sent, 0)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                sent += result
            }
            return true
        }
    }

    private static func pump(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while true {
            let count = Darwin.recv(source, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return }
            let data = Data(buffer.prefix(count))
            guard sendAll(data, to: destination) else { return }
        }
    }

    private static func numericAddress(_ storage: sockaddr_storage) -> String? {
        var copy = storage
        let length = socklen_t(copy.ss_len)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo(
                    $0,
                    length,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }
        }
        return result == 0 ? String(cString: host) : nil
    }
}

private final class MobileMirrorProxyLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let client: Int32
    private let upstream: Int32
    private let closeClient: @Sendable () -> Void
    private var closed = false

    init(client: Int32, upstream: Int32, closeClient: @escaping @Sendable () -> Void) {
        self.client = client
        self.upstream = upstream
        self.closeClient = closeClient
    }

    func close() {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        lock.unlock()
        Darwin.shutdown(client, SHUT_RDWR)
        Darwin.shutdown(upstream, SHUT_RDWR)
        Darwin.close(upstream)
        closeClient()
    }
}
