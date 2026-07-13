// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Network
import Testing
@testable import CocxyTerminal

private final class HTTPTestTransport: ProxyUpstreamTransport, @unchecked Sendable {
    let processIdentifier: Int32 = 43
    let diagnosticOutput = ""

    private let lock = NSLock()
    private let readinessError: ProxyUpstreamTransportError?
    private var isRunningStorage = true
    private var sentStorage: [Data] = []
    private var cancelledStorage = false
    private var automaticallyCompletesSendsStorage = true
    private var pendingSendCompletions: [
        @Sendable (Result<Void, any Error>) -> Void
    ] = []
    private var maximumPendingSendCountStorage = 0
    private var receiveRequestCountStorage = 0
    private var pendingReceiveCompletion: (
        @Sendable (Result<Data?, any Error>) -> Void
    )?
    private var closeWriteCountStorage = 0

    init(readinessError: ProxyUpstreamTransportError? = nil) {
        self.readinessError = readinessError
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunningStorage
    }

    var sentData: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return sentStorage
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelledStorage
    }

    var automaticallyCompletesSends: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return automaticallyCompletesSendsStorage
        }
        set {
            lock.lock()
            automaticallyCompletesSendsStorage = newValue
            lock.unlock()
        }
    }

    var maximumPendingSendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumPendingSendCountStorage
    }

    var receiveRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return receiveRequestCountStorage
    }

    var didCloseWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closeWriteCountStorage > 0
    }

    func waitUntilReady() async throws {
        if let readinessError { throw readinessError }
    }

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        lock.lock()
        sentStorage.append(data)
        let completesImmediately = automaticallyCompletesSendsStorage
        if !completesImmediately {
            pendingSendCompletions.append(completion)
            maximumPendingSendCountStorage = max(
                maximumPendingSendCountStorage,
                pendingSendCompletions.count
            )
        }
        lock.unlock()
        if completesImmediately {
            completion(.success(()))
        }
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        _ = maximumLength
        lock.lock()
        guard pendingReceiveCompletion == nil else {
            lock.unlock()
            completion(.failure(ProxyUpstreamTransportError.receiveAlreadyPending))
            return
        }
        receiveRequestCountStorage += 1
        pendingReceiveCompletion = completion
        lock.unlock()
    }

    func closeWrite() {
        lock.lock()
        closeWriteCountStorage += 1
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelledStorage = true
        isRunningStorage = false
        let sendCompletions = pendingSendCompletions
        pendingSendCompletions.removeAll()
        let receiveCompletion = pendingReceiveCompletion
        pendingReceiveCompletion = nil
        lock.unlock()
        for completion in sendCompletions {
            completion(.failure(ProxyUpstreamTransportError.closed))
        }
        receiveCompletion?(.failure(ProxyUpstreamTransportError.closed))
    }

    func completeNextSend() {
        lock.lock()
        let completion = pendingSendCompletions.isEmpty
            ? nil
            : pendingSendCompletions.removeFirst()
        lock.unlock()
        completion?(.success(()))
    }

    func completeReceive(_ result: Result<Data?, any Error>) {
        lock.lock()
        let completion = pendingReceiveCompletion
        pendingReceiveCompletion = nil
        lock.unlock()
        completion?(result)
    }
}

@MainActor
private final class HTTPTestForwarder: PortForwarding {
    let leaseID = UUID()
    var currentLeaseID: UUID?
    private(set) var openedTargets: [ProxyTarget] = []
    private(set) var transports: [HTTPTestTransport] = []
    private(set) weak var lastTransport: HTTPTestTransport?
    var nextReadinessError: ProxyUpstreamTransportError?

    init() {
        currentLeaseID = leaseID
    }

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        _ = profileID
        return currentLeaseID
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        _ = forward
        _ = profileID
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        _ = forward
        _ = profileID
    }

    func openProxyTransport(
        to target: ProxyTarget,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> any ProxyUpstreamTransport {
        _ = profileID
        guard currentLeaseID == expectedConnectionLeaseID else {
            throw SSHMultiplexerError.notConnected
        }
        let transport = HTTPTestTransport(readinessError: nextReadinessError)
        openedTargets.append(target)
        transports.append(transport)
        lastTransport = transport
        return transport
    }

    func releaseRecordedTransports() {
        transports.removeAll()
    }
}

private final class HTTPTestContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

@MainActor
private func connectHTTPTestClient(
    to port: Int,
    host: NWEndpoint.Host = .ipv4(.loopback)
) async throws -> NWConnection {
    let connection = NWConnection(
        host: host,
        port: NWEndpoint.Port(rawValue: UInt16(port))!,
        using: .tcp
    )
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let gate = HTTPTestContinuationGate()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard gate.claim() else { return }
                continuation.resume()
            case .failed(let error):
                guard gate.claim() else { return }
                continuation.resume(throwing: error)
            case .cancelled:
                guard gate.claim() else { return }
                continuation.resume(throwing: CancellationError())
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    return connection
}

@MainActor
private func sendHTTPRequest(_ data: Data, on connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        })
    }
}

@MainActor
private func finishHTTPRequestWrites(_ data: Data, on connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(
            content: data,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        )
    }
}

@MainActor
private func receiveHTTPResponse(on connection: NWConnection) async throws -> String {
    let data = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Data, any Error>) in
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: data ?? Data())
            }
        }
    }
    return String(decoding: data, as: UTF8.self)
}

@MainActor
private func httpTestConnectionObservedClosure(_ connection: NWConnection) async -> Bool {
    await withCheckedContinuation { continuation in
        let gate = HTTPTestContinuationGate()
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) {
            data, _, isComplete, error in
            guard gate.claim() else { return }
            continuation.resume(returning: error != nil || isComplete || data == nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard gate.claim() else { return }
            continuation.resume(returning: false)
        }
    }
}

@Suite("Authenticated HTTP CONNECT proxy", .serialized)
struct HTTPConnectProxyTests {
    private static func availableLoopbackPort() throws -> Int {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: 0,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var result = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &result) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return Int(UInt16(bigEndian: result.sin_port))
    }

    @Test("HTTP broker does not retain its SSH authority")
    @MainActor func doesNotRetainForwarder() throws {
        var forwarder: HTTPTestForwarder? = HTTPTestForwarder()
        weak let weakForwarder = forwarder
        let leaseID = try #require(forwarder?.leaseID)
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "ephemeral"),
            forwarder: try #require(forwarder),
            profileID: UUID(),
            connectionLeaseID: leaseID
        )

        forwarder = nil

        #expect(weakForwarder == nil)
        withExtendedLifetime(proxy) {}
    }

    @Test("CONNECT parser validates HTTP shape, host, and port")
    func parserValidation() throws {
        #expect(try HTTPConnectParser.parse(requestLine: "CONNECT example.com:443 HTTP/1.1") ==
            .init(host: "example.com", port: 443))
        #expect(try HTTPConnectParser.parse(requestLine: "CONNECT [::1]:8443 HTTP/1.0") ==
            .init(host: "::1", port: 8443))
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: "GET / HTTP/1.1")
        }
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: "CONNECT -oBad:443 HTTP/1.1")
        }
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: "CONNECT example.com:0 HTTP/1.1")
        }
    }

    @Test("Header authenticator requires one exact Basic capability")
    func headerAuthentication() {
        let credentials = ProxyCredentials(password: "current-secret")
        let authorized = Data((
            "CONNECT example.com:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        ).utf8)
        #expect(HTTPConnectAuthenticator.authenticate(
            headerData: authorized,
            credentials: credentials
        ) == .authorized(requestLine: "CONNECT example.com:443 HTTP/1.1"))
        #expect(HTTPConnectAuthenticator.authenticate(
            headerData: Data("CONNECT example.com:443 HTTP/1.1\r\n\r\n".utf8),
            credentials: credentials
        ) == .authenticationRequired)
        #expect(HTTPConnectAuthenticator.authenticate(
            headerData: Data((
                "CONNECT example.com:443 HTTP/1.1\r\n" +
                "Proxy-Authorization: Basic not-base64\r\n\r\n"
            ).utf8),
            credentials: credentials
        ) == .authenticationRequired)
    }

    @Test("Missing credentials return 407 without opening a destination")
    @MainActor func rejectsMissingCredentials() async throws {
        let forwarder = HTTPTestForwarder()
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "current-secret"),
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }

        try await sendHTTPRequest(
            Data("CONNECT internal.example:443 HTTP/1.1\r\nHost: internal.example\r\n\r\n".utf8),
            on: client
        )
        let response = try await receiveHTTPResponse(on: client)
        #expect(response.hasPrefix("HTTP/1.1 407"))
        #expect(response.contains("Proxy-Authenticate: Basic"))
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Stale credentials are rejected before target parsing")
    @MainActor func rejectsStaleCredentials() async throws {
        let forwarder = HTTPTestForwarder()
        let current = ProxyCredentials(password: "current-secret")
        let stale = ProxyCredentials(password: "previous-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: current,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }

        let request =
            "CONNECT -oBad:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(stale.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: client)
        #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 407"))
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Valid credentials open one direct stream and preserve pipelined bytes")
    @MainActor func authenticatedConnect() async throws {
        let forwarder = HTTPTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }

        let payload = Data([0x16, 0x03, 0x01, 0x00])
        var request = Data((
            "CONNECT internal.example:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        ).utf8)
        request.append(payload)
        try await sendHTTPRequest(request, on: client)
        #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 200"))
        #expect(forwarder.openedTargets == [try ProxyTarget(host: "internal.example", port: 443)])

        for _ in 0..<50 where forwarder.transports.first?.sentData.isEmpty != false {
            await Task.yield()
        }
        #expect(forwarder.transports.first?.sentData == [payload])
    }

    @Test("Pending unauthenticated clients cannot lock out a valid HTTP client")
    @MainActor func pendingAuthenticationSaturationEvictsOldestClient() async throws {
        let forwarder = HTTPTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }

        var pendingClients: [NWConnection] = []
        defer { pendingClients.forEach { $0.cancel() } }
        for _ in 0..<HTTPConnectProxy.maximumPendingAuthenticationConnections {
            pendingClients.append(try await connectHTTPTestClient(to: proxy.port))
        }
        for _ in 0..<100
            where proxy.activeConnectionCount < HTTPConnectProxy.maximumPendingAuthenticationConnections {
            await Task.yield()
        }
        #expect(proxy.activeConnectionCount == HTTPConnectProxy.maximumPendingAuthenticationConnections)

        let authenticatedClient = try await connectHTTPTestClient(to: proxy.port)
        defer { authenticatedClient.cancel() }
        let request = "CONNECT internal.example:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: authenticatedClient)

        #expect(try await receiveHTTPResponse(on: authenticatedClient).hasPrefix("HTTP/1.1 200"))
        #expect(forwarder.openedTargets == [try ProxyTarget(host: "internal.example", port: 443)])
        #expect(
            proxy.activeConnectionCount == HTTPConnectProxy.maximumPendingAuthenticationConnections
        )
        #expect(try await httpTestConnectionObservedClosure(#require(pendingClients.first)))
    }

    @Test("Unauthenticated HTTP clients expire at the bounded authentication deadline")
    @MainActor func pendingAuthenticationExpires() async throws {
        let forwarder = HTTPTestForwarder()
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "current-secret"),
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID,
            authenticationTimeoutNanoseconds: 20_000_000
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }

        for _ in 0..<100 where proxy.activeConnectionCount == 0 {
            await Task.yield()
        }
        #expect(proxy.activeConnectionCount == 1)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(proxy.activeConnectionCount == 0)
        #expect(await httpTestConnectionObservedClosure(client))
    }

    @Test("Upstream readiness failure returns 502 before CONNECT success")
    @MainActor func rejectsUnreadyUpstream() async throws {
        let forwarder = HTTPTestForwarder()
        forwarder.nextReadinessError = .closed
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }

        let request = "CONNECT internal.example:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: client)

        #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 502"))
        #expect(forwarder.openedTargets == [try ProxyTarget(host: "internal.example", port: 443)])
        for _ in 0..<50 where forwarder.transports.first?.wasCancelled != true {
            await Task.yield()
        }
        #expect(forwarder.transports.first?.wasCancelled == true)
    }

    @Test("Both loopback families reject unauthenticated clients")
    @MainActor func exactLoopbackFamilies() async throws {
        let forwarder = HTTPTestForwarder()
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "secret"),
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }

        for host in [NWEndpoint.Host.ipv4(.loopback), .ipv6(.loopback)] {
            let client = try await connectHTTPTestClient(to: proxy.port, host: host)
            try await sendHTTPRequest(
                Data("CONNECT example.com:443 HTTP/1.1\r\n\r\n".utf8),
                on: client
            )
            #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 407"))
            client.cancel()
        }
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Relay applies backpressure before reading the next client chunk")
    @MainActor func relayClientBackpressure() async throws {
        let forwarder = HTTPTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }
        let request = "CONNECT internal.example:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: client)
        #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 200"))
        let transport = try #require(forwarder.transports.first)
        transport.automaticallyCompletesSends = false

        let first = Data("first-client-chunk".utf8)
        let second = Data("second-client-chunk".utf8)
        try await sendHTTPRequest(first, on: client)
        for _ in 0..<100 where transport.sentData.count < 1 {
            await Task.yield()
        }
        #expect(transport.sentData == [first])

        try await sendHTTPRequest(second, on: client)
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(transport.sentData == [first])
        #expect(transport.maximumPendingSendCount == 1)

        transport.completeNextSend()
        for _ in 0..<100 where transport.sentData.count < 2 {
            await Task.yield()
        }
        #expect(transport.sentData == [first, second])
        #expect(transport.maximumPendingSendCount == 1)
        transport.completeNextSend()
    }

    @Test("Client half-close preserves the upstream response and remote EOF")
    @MainActor func relayHalfClose() async throws {
        let forwarder = HTTPTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }
        let request = "CONNECT internal.example:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: client)
        #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 200"))
        let transport = try #require(forwarder.transports.first)
        let clientPayload = Data("request-before-half-close".utf8)

        try await finishHTTPRequestWrites(clientPayload, on: client)
        for _ in 0..<100 where !transport.didCloseWrite {
            await Task.yield()
        }
        #expect(transport.sentData == [clientPayload])
        #expect(transport.didCloseWrite)

        let upstreamPayload = Data("response-after-half-close".utf8)
        transport.completeReceive(.success(upstreamPayload))
        #expect(
            try await receiveHTTPResponse(on: client)
                == String(decoding: upstreamPayload, as: UTF8.self)
        )
        for _ in 0..<100 where transport.receiveRequestCount < 2 {
            await Task.yield()
        }
        #expect(transport.receiveRequestCount == 2)

        transport.completeReceive(.success(nil))
        #expect(await httpTestConnectionObservedClosure(client))
        for _ in 0..<100 where proxy.activeConnectionCount != 0 {
            await Task.yield()
        }
        #expect(proxy.activeConnectionCount == 0)
        #expect(transport.wasCancelled)
    }

    @Test("Stop revokes accepted clients and direct streams")
    @MainActor func stopRevokesConnections() async throws {
        let forwarder = HTTPTestForwarder()
        let credentials = ProxyCredentials(password: "secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        let client = try await connectHTTPTestClient(to: proxy.port)
        defer { client.cancel() }
        let request =
            "CONNECT example.com:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: client)
        _ = try await receiveHTTPResponse(on: client)
        let transport = try #require(forwarder.transports.first)

        proxy.stop()
        #expect(proxy.activeConnectionCount == 0)
        #expect(transport.wasCancelled)
    }

    @Test("Stopping a relaying session releases its transport")
    @MainActor func stopReleasesRelayingSession() async throws {
        let forwarder = HTTPTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        let client = try await connectHTTPTestClient(to: proxy.port)
        let request = "CONNECT internal.example:443 HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(credentials.basicAuthorizationValue)\r\n\r\n"
        try await sendHTTPRequest(Data(request.utf8), on: client)
        #expect(try await receiveHTTPResponse(on: client).hasPrefix("HTTP/1.1 200"))
        #expect(forwarder.lastTransport != nil)
        forwarder.releaseRecordedTransports()

        proxy.stop()
        client.cancel()

        #expect(forwarder.lastTransport == nil)
    }
}
