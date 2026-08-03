// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorGateway.swift - Loopback HTTP and WebSocket relay behind SSH.

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
        case .invalidBindAddress: return "The mobile mirror listener must use loopback."
        case .socketCreationFailed(let code): return "Could not create the local listener (\(code))."
        case .bindFailed(let code): return "Could not bind the local listener (\(code))."
        case .listenFailed(let code): return "Could not start the local listener (\(code))."
        case .portUnavailable: return "The local listener did not receive a port."
        }
    }
}

final class MobileMirrorGateway: @unchecked Sendable {
    typealias RouteHandler = @Sendable (
        MobileMirrorHTTPRequest,
        MobileMirrorClientIdentity
    ) async -> MobileMirrorHTTPRouteResult

    static let maximumConnections = 16
    static let loopbackAddress = "127.0.0.1"

    let bindAddress = MobileMirrorGateway.loopbackAddress
    let eventHub: MobileMirrorEventHub

    private let requestedPort: UInt16
    private let routeHandler: RouteHandler
    private let clientIdentityLabel: String?
    private let requestTimeout: TimeInterval
    private let monotonicNow: @Sendable () -> TimeInterval
    private let listenerQueue = DispatchQueue(label: "dev.cocxy.mobile.listener")
    private let workerQueue = DispatchQueue(
        label: "dev.cocxy.mobile.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateLock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var clientDescriptors: [Int32: String] = [:]
    private var connectionPolicy: MobileMirrorConnectionPolicy
    private(set) var port: UInt16?

    init(
        requestedPort: UInt16 = 0,
        eventHub: MobileMirrorEventHub = MobileMirrorEventHub(),
        clientIdentityLabel: String? = nil,
        requestTimeout: TimeInterval = 8,
        connectionLimits: MobileMirrorConnectionLimits = .default,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        routeHandler: @escaping RouteHandler
    ) {
        self.requestedPort = requestedPort
        self.eventHub = eventHub
        self.clientIdentityLabel = clientIdentityLabel
        self.requestTimeout = max(0.05, requestTimeout)
        self.connectionPolicy = MobileMirrorConnectionPolicy(limits: connectionLimits)
        self.monotonicNow = monotonicNow
        self.routeHandler = routeHandler
    }

    @discardableResult
    func start() throws -> UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let port { return port }
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
        stateLock.lock()
        source = listenerSource
        listenerSource = nil
        listenerDescriptor = -1
        port = nil
        for descriptor in clientDescriptors.keys {
            Darwin.shutdown(descriptor, SHUT_RDWR)
        }
        stateLock.unlock()
        source?.cancel()
        eventHub.stop()
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
            let remoteAddress = Self.numericAddress(remote) ?? "unknown"
            stateLock.lock()
            let decision = connectionPolicy.admit(
                address: remoteAddress,
                now: monotonicNow()
            )
            if decision == .accepted {
                clientDescriptors[descriptor] = remoteAddress
            }
            stateLock.unlock()
            guard decision == .accepted else {
                _ = Self.sendAll(
                    MobileMirrorHTTPResponse.error(
                        "Too many local requests.",
                        status: 429
                    ).encoded(),
                    to: descriptor
                )
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
                continue
            }
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
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }

    private func readRequest(from descriptor: Int32, remoteAddress: String) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        let deadline = MobileMirrorRequestDeadline(
            startedAt: monotonicNow(),
            timeout: requestTimeout
        )
        do {
            while true {
                if let request = try MobileMirrorHTTPRequest.parseIfComplete(data) {
                    let identity = MobileMirrorClientIdentity(
                        remoteAddress: clientIdentityLabel ?? remoteAddress,
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
                guard let timeout = deadline.remainingPollMilliseconds(at: monotonicNow()) else {
                    throw MobileMirrorHTTPError.malformedRequest
                }
                var descriptorPoll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let pollResult = Darwin.poll(&descriptorPoll, 1, timeout)
                if pollResult < 0, errno == EINTR { continue }
                guard pollResult > 0, descriptorPoll.revents & Int16(POLLIN) != 0 else {
                    throw MobileMirrorHTTPError.malformedRequest
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
        let clientInput = Darwin.dup(client)
        let upstreamOutput = Darwin.dup(upstream)
        let upstreamInput = Darwin.dup(upstream)
        let clientOutput = Darwin.dup(client)
        let pumpDescriptors = [clientInput, upstreamOutput, upstreamInput, clientOutput]
        guard pumpDescriptors.allSatisfy({ $0 >= 0 }) else {
            pumpDescriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
            Darwin.close(upstream)
            respond(.error("Terminal stream is unavailable.", status: 503), to: client)
            return
        }
        pumpDescriptors.forEach { _ = fcntl($0, F_SETFD, FD_CLOEXEC) }
        let lifetime = MobileMirrorProxyLifetime(
            upstream: upstream,
            closeClient: { [weak self] in self?.finish(client) }
        )
        workerQueue.async {
            Self.pump(from: clientInput, to: upstreamOutput)
            Darwin.close(clientInput)
            Darwin.close(upstreamOutput)
            lifetime.close()
        }
        workerQueue.async {
            Self.pump(from: upstreamInput, to: clientOutput)
            Darwin.close(upstreamInput)
            Darwin.close(clientOutput)
            lifetime.close()
        }
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
        let remoteAddress = clientDescriptors.removeValue(forKey: descriptor)
        if let remoteAddress {
            connectionPolicy.release(address: remoteAddress)
        }
        stateLock.unlock()
        guard remoteAddress != nil else { return }
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
    private let upstream: Int32
    private let closeClient: @Sendable () -> Void
    private var closed = false

    init(upstream: Int32, closeClient: @escaping @Sendable () -> Void) {
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
        Darwin.shutdown(upstream, SHUT_RDWR)
        Darwin.close(upstream)
        closeClient()
    }
}
