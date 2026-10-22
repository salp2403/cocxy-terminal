// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorGateway.swift - Loopback HTTP gateway behind private transports.

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
    typealias LocalizationProvider = @Sendable () -> MobileMirrorWebLocalization

    static let maximumConnections = 16
    static let loopbackAddress = "127.0.0.1"

    private struct ClientState {
        var admittedAddress: String?
    }

    let bindAddress = MobileMirrorGateway.loopbackAddress
    let eventHub: MobileMirrorEventHub

    private let requestedPort: UInt16
    private let routeHandler: RouteHandler
    private let clientIdentityLabel: String?
    private let trustedRelaySecret: String?
    private let requestTimeout: TimeInterval
    private let maximumPendingConnections: Int
    private let monotonicNow: @Sendable () -> TimeInterval
    private let localization: LocalizationProvider
    private let listenerQueue = DispatchQueue(label: "dev.cocxy.mobile.listener")
    private let workerQueue = DispatchQueue(
        label: "dev.cocxy.mobile.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateLock = NSLock()
    private var listenerSource: DispatchSourceRead?
    private var clientDescriptors: [Int32: ClientState] = [:]
    private var connectionPolicy: MobileMirrorConnectionPolicy
    private(set) var port: UInt16?

    init(
        requestedPort: UInt16 = 0,
        eventHub: MobileMirrorEventHub = MobileMirrorEventHub(),
        clientIdentityLabel: String? = nil,
        trustedRelaySecret: String? = nil,
        requestTimeout: TimeInterval = 8,
        connectionLimits: MobileMirrorConnectionLimits = .default,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        localization: @escaping LocalizationProvider = { .english },
        routeHandler: @escaping RouteHandler
    ) {
        self.requestedPort = requestedPort
        self.eventHub = eventHub
        self.clientIdentityLabel = clientIdentityLabel
        self.trustedRelaySecret = trustedRelaySecret
        self.requestTimeout = requestTimeout.isFinite
            ? min(60, max(0.05, requestTimeout))
            : 8
        self.maximumPendingConnections = max(1, connectionLimits.maximumTotal)
        self.connectionPolicy = MobileMirrorConnectionPolicy(limits: connectionLimits)
        self.monotonicNow = monotonicNow
        self.localization = localization
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
        port = resolvedPort
        ownsDescriptor = false

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: listenerQueue)
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections(from: descriptor)
        }
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
        port = nil
        for descriptor in clientDescriptors.keys {
            Darwin.shutdown(descriptor, SHUT_RDWR)
        }
        stateLock.unlock()
        source?.cancel()
        eventHub.stop()
    }

    private func acceptAvailableConnections(from listener: Int32) {
        while true {
            var remote = sockaddr_storage()
            var remoteLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let descriptor = withUnsafeMutablePointer(to: &remote) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listener, $0, &remoteLength)
                }
            }
            if descriptor < 0 {
                if errno == EINTR { continue }
                return
            }
            configureClientSocket(descriptor)
            let remoteAddress = Self.numericAddress(remote) ?? "unknown"
            stateLock.lock()
            guard port != nil,
                  clientDescriptors.count < maximumPendingConnections else {
                stateLock.unlock()
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
                continue
            }
            let decision = trustedRelaySecret == nil
                ? connectionPolicy.admit(address: remoteAddress, now: monotonicNow())
                : .accepted
            if decision == .accepted {
                clientDescriptors[descriptor] = ClientState(
                    admittedAddress: trustedRelaySecret == nil ? remoteAddress : nil
                )
            }
            stateLock.unlock()
            guard decision == .accepted else {
                _ = Self.sendAll(
                    failureResponse(.rateLimited).encoded(),
                    to: descriptor
                )
                Darwin.shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
                continue
            }
            workerQueue.async { [self] in
                readRequest(from: descriptor, remoteAddress: remoteAddress)
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
        var relayedRemoteAddress: String?
        var consumedRelayPreamble = trustedRelaySecret == nil
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        let deadline = MobileMirrorRequestDeadline(
            startedAt: monotonicNow(),
            timeout: requestTimeout
        )
        do {
            while true {
                if !consumedRelayPreamble, let trustedRelaySecret {
                    guard let address = try MobileMirrorRelayPreamble.consumeIfComplete(
                        from: &data,
                        expectedSecret: trustedRelaySecret
                    ) else {
                        try receiveMoreRequestData(
                            into: &data,
                            buffer: &buffer,
                            descriptor: descriptor,
                            deadline: deadline
                        )
                        continue
                    }
                    relayedRemoteAddress = address
                    consumedRelayPreamble = true
                    guard admitRelayedConnection(descriptor, address: address) else {
                        respond(failureResponse(.rateLimited), to: descriptor)
                        return
                    }
                }
                if let request = try MobileMirrorHTTPRequest.parseIfComplete(data) {
                    let identity = MobileMirrorClientIdentity(
                        remoteAddress: relayedRemoteAddress
                            ?? clientIdentityLabel
                            ?? remoteAddress,
                        userAgent: request.userAgent
                    )
                    route(
                        request: request,
                        identity: identity,
                        descriptor: descriptor
                    )
                    return
                }
                try receiveMoreRequestData(
                    into: &data,
                    buffer: &buffer,
                    descriptor: descriptor,
                    deadline: deadline
                )
            }
        } catch {
            respond(failureResponse(.malformedRequest), to: descriptor)
        }
    }

    private func receiveMoreRequestData(
        into data: inout Data,
        buffer: inout [UInt8],
        descriptor: Int32,
        deadline: MobileMirrorRequestDeadline
    ) throws {
        while true {
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
            return
        }
    }

    private func admitRelayedConnection(_ descriptor: Int32, address: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard port != nil,
              let client = clientDescriptors[descriptor],
              client.admittedAddress == nil,
              connectionPolicy.admit(address: address, now: monotonicNow()) == .accepted else {
            return false
        }
        clientDescriptors[descriptor]?.admittedAddress = address
        return true
    }

    private func route(
        request: MobileMirrorHTTPRequest,
        identity: MobileMirrorClientIdentity,
        descriptor: Int32
    ) {
        let completion = MobileMirrorRouteCompletion { [self] outcome in
            workerQueue.async { [self] in
                switch outcome {
                case .result(let result):
                    complete(request: request, result: result, descriptor: descriptor)
                case .timedOut:
                    respond(failureResponse(.timedOut), to: descriptor)
                }
            }
        }
        let handler = routeHandler
        let routeTask = Task { [weak completion] in
            let result = await handler(request, identity)
            completion?.resolve(.result(result))
        }
        completion.install(routeTask: routeTask)
        let timeoutNanoseconds = UInt64(requestTimeout * 1_000_000_000)
        let timeoutTask = Task { [completion] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            await completion.cancelRouteAndWait()
        }
        completion.install(timeoutTask: timeoutTask)
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
            eventHub.add(
                descriptor: descriptor,
                afterEventID: request.headers["last-event-id"].flatMap(UInt64.init)
            ) { [self] in
                finish(descriptor)
            }
            monitorEventStreamClosure(descriptor)
        case .proxy(let target):
            proxy(request: request, to: target, client: descriptor)
        }
    }

    private func failureResponse(_ failure: MobileMirrorFailure) -> MobileMirrorHTTPResponse {
        failure.response(using: localization())
    }

    private func respond(_ response: MobileMirrorHTTPResponse, to descriptor: Int32) {
        _ = Self.sendAll(response.encoded(), to: descriptor)
        finish(descriptor)
    }

    private func monitorEventStreamClosure(_ descriptor: Int32) {
        workerQueue.async { [self] in
            var byte: UInt8 = 0
            while true {
                let count = Darwin.recv(descriptor, &byte, 1, MSG_PEEK)
                if count < 0, errno == EINTR { continue }
                eventHub.disconnect(descriptor: descriptor)
                finish(descriptor)
                return
            }
        }
    }

    private func proxy(
        request: MobileMirrorHTTPRequest,
        to target: MobileMirrorProxyTarget,
        client: Int32
    ) {
        let upstream = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard upstream >= 0 else {
            respond(failureResponse(.terminalProxyUnavailable), to: client)
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
            respond(failureResponse(.terminalProxyUnavailable), to: client)
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
            respond(failureResponse(.terminalProxyUnavailable), to: client)
            return
        }
        pumpDescriptors.forEach { _ = fcntl($0, F_SETFD, FD_CLOEXEC) }
        let lifetime = MobileMirrorProxyLifetime(
            upstream: upstream,
            closeClient: { [self] in finish(client) }
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
            "x-cocxy-nonce", "x-cocxy-signature", "x-cocxy-terminal-key",
            "content-length",
        ])
        var value = "\(request.method) \(target.rewrittenPath) \(request.version)\r\n"
        for key in request.headers.keys.sorted() where !excluded.contains(key) {
            value += "\(key): \(request.headers[key] ?? "")\r\n"
        }
        value += "Host: 127.0.0.1:\(target.port)\r\n"
        value += "Origin: http://127.0.0.1:\(target.port)\r\n"
        value += "Authorization: Bearer \(target.bearerToken)\r\n"
        if let key = target.terminalEncryptionKey {
            value += "X-Cocxy-Terminal-Key: \(MobileMirrorPairingAuthority.base64URL(key))\r\n"
        }
        if !request.body.isEmpty {
            value += "Content-Length: \(request.body.count)\r\n"
        }
        value += "\r\n"
        return Data(value.utf8) + request.body
    }

    private func finish(_ descriptor: Int32) {
        stateLock.lock()
        let client = clientDescriptors.removeValue(forKey: descriptor)
        if let remoteAddress = client?.admittedAddress {
            connectionPolicy.release(address: remoteAddress)
        }
        stateLock.unlock()
        guard client != nil else { return }
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
