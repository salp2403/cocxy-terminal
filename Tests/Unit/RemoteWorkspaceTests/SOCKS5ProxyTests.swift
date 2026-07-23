// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Network
import Testing
@testable import CocxyTerminal

private final class SOCKSTestTransport: ProxyUpstreamTransport, @unchecked Sendable {
    let processIdentifier: Int32 = 42
    var isRunning = true
    let diagnosticOutput = ""
    private(set) var wasCancelled = false
    private let readinessError: ProxyUpstreamTransportError?

    init(readinessError: ProxyUpstreamTransportError? = nil) {
        self.readinessError = readinessError
    }

    func waitUntilReady() async throws {
        if let readinessError { throw readinessError }
    }

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        _ = data
        completion(.success(()))
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        _ = maximumLength
        _ = completion
    }

    func closeWrite() {}

    func cancel() {
        wasCancelled = true
        isRunning = false
    }
}

@MainActor
private final class SOCKSTestForwarder: PortForwarding {
    let leaseID = UUID()
    private(set) var openedTargets: [ProxyTarget] = []
    private(set) weak var lastTransport: SOCKSTestTransport?
    var nextReadinessError: ProxyUpstreamTransportError?
    var retainsOpenedTransports = false
    private(set) var retainedTransports: [SOCKSTestTransport] = []

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        _ = profileID
        return leaseID
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
        guard expectedConnectionLeaseID == leaseID else {
            throw SSHMultiplexerError.notConnected
        }
        let transport = SOCKSTestTransport(readinessError: nextReadinessError)
        openedTargets.append(target)
        lastTransport = transport
        if retainsOpenedTransports {
            retainedTransports.append(transport)
        }
        return transport
    }
}

private final class SOCKSTestContinuationGate: @unchecked Sendable {
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
private func connectSOCKSTestClient(
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
        let gate = SOCKSTestContinuationGate()
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
private func sendSOCKSTestData(_ data: Data, on connection: NWConnection) async throws {
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
private func receiveSOCKSTestData(count: Int, on connection: NWConnection) async throws -> Data {
    var result = Data()
    while result.count < count {
        let next = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, any Error>) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: count - result.count
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
        result.append(next)
    }
    return result
}

@MainActor
private func socksTestConnectionObservedClosure(_ connection: NWConnection) async -> Bool {
    await withCheckedContinuation { continuation in
        let gate = SOCKSTestContinuationGate()
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

@Suite("Authenticated SOCKS5 proxy", .serialized)
struct SOCKS5ProxyTests {
    private static func availableLoopbackPort() throws -> Int {
        try LoopbackTestPortAllocator.freshPort()
    }

    private static func canRebindIPv4(port: Int) -> Bool {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        enableReuseOptions(on: descriptor)

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: UInt16(port).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func canRebindIPv6(port: Int) -> Bool {
        let descriptor = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        enableReuseOptions(on: descriptor)

        var address = sockaddr_in6(
            sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: UInt16(port).bigEndian,
            sin6_flowinfo: 0,
            sin6_addr: in6addr_loopback,
            sin6_scope_id: 0
        )
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }

    private static func enableReuseOptions(on descriptor: Int32) {
        var enabled: Int32 = 1
        withUnsafePointer(to: &enabled) { pointer in
            _ = Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_REUSEADDR,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            )
            _ = Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_REUSEPORT,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
    }

    @Test("SOCKS broker does not retain its SSH authority")
    @MainActor func doesNotRetainForwarder() throws {
        var forwarder: SOCKSTestForwarder? = SOCKSTestForwarder()
        weak let weakForwarder = forwarder
        let leaseID = try #require(forwarder?.leaseID)
        let proxy = SOCKS5Proxy(
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

    @Test("No-auth method is rejected before any destination is opened")
    @MainActor func rejectsNoAuthentication() async throws {
        let forwarder = SOCKSTestForwarder()
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "current-secret"),
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectSOCKSTestClient(to: proxy.port)
        defer { client.cancel() }

        try await sendSOCKSTestData(
            Data([0x05, 0x01, 0x00, 0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80]),
            on: client
        )
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x05, 0xff]))
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Invalid listener ports throw instead of trapping")
    @MainActor func rejectsInvalidListenerPorts() async {
        for port in [-1, 65_536] {
            let listeners = LoopbackTCPListenerGroup(port: port)
            await #expect(throws: POSIXError.self) {
                try await listeners.start()
            }
        }
    }

    @Test("Listener delivery backlog is bounded before MainActor admission")
    @MainActor func boundsPreActorConnectionDeliveries() {
        let limiter = LoopbackConnectionDeliveryLimiter(
            limit: LoopbackTCPListenerGroup.maximumQueuedConnectionDeliveries
        )

        for _ in 0..<LoopbackTCPListenerGroup.maximumQueuedConnectionDeliveries {
            #expect(limiter.acquire())
        }
        #expect(!limiter.acquire())
        #expect(
            limiter.pendingCount == LoopbackTCPListenerGroup.maximumQueuedConnectionDeliveries
        )

        limiter.release()
        #expect(limiter.acquire())
        #expect(
            limiter.pendingCount == LoopbackTCPListenerGroup.maximumQueuedConnectionDeliveries
        )
    }

    @Test("Stopping either listener during startup resumes the pending activation")
    @MainActor func stoppingDuringListenerStartup() async throws {
        for cancellationIndex in [0, 1] {
            let listeners = LoopbackTCPListenerGroup(port: try Self.availableLoopbackPort())
            listeners.listenerWillStart = { index in
                if index == cancellationIndex {
                    listeners.stop()
                }
            }

            await #expect(throws: CancellationError.self) {
                try await listeners.start()
            }
            listeners.listenerWillStart = nil
            listeners.stop()
            #expect(!listeners.isReady)
        }
    }

    @Test("Cancelling startup tears down either pending loopback listener")
    @MainActor func cancellingDuringListenerStartup() async throws {
        for cancellationIndex in [0, 1] {
            let listeners = LoopbackTCPListenerGroup(port: try Self.availableLoopbackPort())
            var startupTask: Task<Void, any Error>?
            listeners.listenerWillStart = { index in
                guard index == cancellationIndex else { return }
                Task { @MainActor in
                    startupTask?.cancel()
                }
            }
            startupTask = Task { @MainActor in
                await Task.yield()
                try await listeners.start()
            }

            let task = try #require(startupTask)
            await #expect(throws: CancellationError.self) {
                try await task.value
            }
            listeners.listenerWillStart = nil
            listeners.stop()
            #expect(!listeners.isReady)
        }
    }

    @Test("A stopped listener generation cannot resume and orphan its sibling")
    @MainActor func stoppedGenerationCannotResumeStartup() async throws {
        let port = try Self.availableLoopbackPort()
        let listeners = LoopbackTCPListenerGroup(port: port)
        listeners.listenerDidBecomeReady = { index in
            if index == 0 {
                listeners.stop()
            }
        }

        await #expect(throws: CancellationError.self) {
            try await listeners.start()
        }
        listeners.listenerDidBecomeReady = nil
        #expect(!listeners.isReady)
        #expect(Self.canRebindIPv4(port: port))
        #expect(Self.canRebindIPv6(port: port))
    }

    @Test("Wrong and stale passwords are rejected before CONNECT parsing")
    @MainActor func rejectsWrongPassword() async throws {
        let forwarder = SOCKSTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectSOCKSTestClient(to: proxy.port)
        defer { client.cancel() }

        try await sendSOCKSTestData(Data([0x05, 0x01, 0x02]), on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x05, 0x02]))
        let username = Data(ProxyCredentials.username.utf8)
        let stalePassword = Data("previous-secret".utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(stalePassword.count))
        authentication.append(stalePassword)
        authentication.append(Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80]))
        try await sendSOCKSTestData(authentication, on: client)

        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x01, 0x01]))
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Exact credentials open one validated direct transport")
    @MainActor func authenticatedConnect() async throws {
        let forwarder = SOCKSTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectSOCKSTestClient(to: proxy.port)
        defer { client.cancel() }

        try await sendSOCKSTestData(Data([0x05, 0x01, 0x02]), on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x05, 0x02]))
        let username = Data(ProxyCredentials.username.utf8)
        let password = Data(credentials.password.utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(password.count))
        authentication.append(password)
        try await sendSOCKSTestData(authentication, on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x01, 0x00]))

        let domain = Data("internal.example".utf8)
        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(domain.count)])
        request.append(domain)
        request.append(contentsOf: [0x01, 0xbb])
        try await sendSOCKSTestData(request, on: client)
        #expect(try await receiveSOCKSTestData(count: 10, on: client)[1] == 0x00)
        #expect(forwarder.openedTargets == [try ProxyTarget(host: "internal.example", port: 443)])
    }

    @Test("Pending unauthenticated clients cannot lock out a valid SOCKS client")
    @MainActor func pendingAuthenticationSaturationEvictsOldestClient() async throws {
        let forwarder = SOCKSTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = SOCKS5Proxy(
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
        for _ in 0..<SOCKS5Proxy.maximumPendingAuthenticationConnections {
            pendingClients.append(try await connectSOCKSTestClient(to: proxy.port))
        }
        for _ in 0..<100
            where proxy.activeConnectionCount < SOCKS5Proxy.maximumPendingAuthenticationConnections {
            await Task.yield()
        }
        #expect(proxy.activeConnectionCount == SOCKS5Proxy.maximumPendingAuthenticationConnections)

        let authenticatedClient = try await connectSOCKSTestClient(to: proxy.port)
        defer { authenticatedClient.cancel() }
        try await sendSOCKSTestData(Data([0x05, 0x01, 0x02]), on: authenticatedClient)
        #expect(
            try await receiveSOCKSTestData(count: 2, on: authenticatedClient)
                == Data([0x05, 0x02])
        )

        let username = Data(ProxyCredentials.username.utf8)
        let password = Data(credentials.password.utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(password.count))
        authentication.append(password)
        try await sendSOCKSTestData(authentication, on: authenticatedClient)
        #expect(
            try await receiveSOCKSTestData(count: 2, on: authenticatedClient)
                == Data([0x01, 0x00])
        )

        try await sendSOCKSTestData(
            Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x01, 0xbb]),
            on: authenticatedClient
        )
        #expect(try await receiveSOCKSTestData(count: 10, on: authenticatedClient)[1] == 0x00)
        #expect(forwarder.openedTargets == [try ProxyTarget(host: "127.0.0.1", port: 443)])
        #expect(
            proxy.activeConnectionCount == SOCKS5Proxy.maximumPendingAuthenticationConnections
        )
        #expect(try await socksTestConnectionObservedClosure(#require(pendingClients.first)))
    }

    @Test("A scoped proxy rejects authenticated requests for another target")
    @MainActor func rejectsTargetOutsideCapabilityScope() async throws {
        let forwarder = SOCKSTestForwarder()
        let credentials = ProxyCredentials(password: "route-secret")
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID,
            allowedTargets: [try ProxyTarget(host: "localhost", port: 3_000)]
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectSOCKSTestClient(to: proxy.port)
        defer { client.cancel() }

        try await sendSOCKSTestData(Data([0x05, 0x01, 0x02]), on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x05, 0x02]))
        let username = Data(ProxyCredentials.username.utf8)
        let password = Data(credentials.password.utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(password.count))
        authentication.append(password)
        try await sendSOCKSTestData(authentication, on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x01, 0x00]))

        let domain = Data("localhost".utf8)
        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(domain.count)])
        request.append(domain)
        request.append(contentsOf: [0x0b, 0xb9]) // 3001, outside the approved route.
        try await sendSOCKSTestData(request, on: client)

        let reply = try await receiveSOCKSTestData(count: 10, on: client)
        #expect(reply[1] == 0x02)
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Unauthenticated SOCKS clients expire at the bounded authentication deadline")
    @MainActor func pendingAuthenticationExpires() async throws {
        let forwarder = SOCKSTestForwarder()
        let proxy = SOCKS5Proxy(
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
        let client = try await connectSOCKSTestClient(to: proxy.port)
        defer { client.cancel() }

        for _ in 0..<100 where proxy.activeConnectionCount == 0 {
            await Task.yield()
        }
        #expect(proxy.activeConnectionCount == 1)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(proxy.activeConnectionCount == 0)
        #expect(await socksTestConnectionObservedClosure(client))
    }

    @Test("Upstream readiness failure is reported before SOCKS success")
    @MainActor func rejectsUnreadyUpstream() async throws {
        let forwarder = SOCKSTestForwarder()
        forwarder.nextReadinessError = .closed
        forwarder.retainsOpenedTransports = true
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }
        let client = try await connectSOCKSTestClient(to: proxy.port)
        defer { client.cancel() }

        try await sendSOCKSTestData(Data([0x05, 0x01, 0x02]), on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x05, 0x02]))
        let username = Data(ProxyCredentials.username.utf8)
        let password = Data(credentials.password.utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(password.count))
        authentication.append(password)
        try await sendSOCKSTestData(authentication, on: client)
        #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x01, 0x00]))

        try await sendSOCKSTestData(
            Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x01, 0xbb]),
            on: client
        )
        let reply = try await receiveSOCKSTestData(count: 10, on: client)
        #expect(reply[1] == 0x01)
        #expect(forwarder.openedTargets == [try ProxyTarget(host: "127.0.0.1", port: 443)])
        for _ in 0..<50 where forwarder.retainedTransports.first?.wasCancelled != true {
            await Task.yield()
        }
        #expect(forwarder.retainedTransports.first?.wasCancelled == true)
    }

    @Test("Both exact loopback families accept authenticated-protocol clients")
    @MainActor func supportsIPv4AndIPv6Loopback() async throws {
        let forwarder = SOCKSTestForwarder()
        let proxy = SOCKS5Proxy(
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
            let client = try await connectSOCKSTestClient(to: proxy.port, host: host)
            try await sendSOCKSTestData(Data([0x05, 0x01, 0x00]), on: client)
            #expect(try await receiveSOCKSTestData(count: 2, on: client) == Data([0x05, 0xff]))
            client.cancel()
        }
        #expect(forwarder.openedTargets.isEmpty)
    }

    @Test("Stopping a relaying session releases its transport")
    @MainActor func stopReleasesRelayingSession() async throws {
        let forwarder = SOCKSTestForwarder()
        let credentials = ProxyCredentials(password: "current-secret")
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: credentials,
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        let client = try await connectSOCKSTestClient(to: proxy.port)

        try await sendSOCKSTestData(Data([0x05, 0x01, 0x02]), on: client)
        _ = try await receiveSOCKSTestData(count: 2, on: client)
        let username = Data(ProxyCredentials.username.utf8)
        let password = Data(credentials.password.utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(password.count))
        authentication.append(password)
        try await sendSOCKSTestData(authentication, on: client)
        _ = try await receiveSOCKSTestData(count: 2, on: client)
        try await sendSOCKSTestData(
            Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80]),
            on: client
        )
        _ = try await receiveSOCKSTestData(count: 10, on: client)
        #expect(forwarder.lastTransport != nil)

        proxy.stop()
        client.cancel()

        #expect(forwarder.lastTransport == nil)
    }

    @Test("Exact listeners reject a competing local port rebind")
    @MainActor func rejectsCompetingRebind() async throws {
        let forwarder = SOCKSTestForwarder()
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "secret"),
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }

        #expect(!Self.canRebindIPv4(port: proxy.port))
        #expect(!Self.canRebindIPv6(port: proxy.port))
    }

    @Test("Kernel reports only exact IPv4 and IPv6 loopback listeners")
    @MainActor func kernelReportsExactLoopbackBindings() async throws {
        let forwarder = SOCKSTestForwarder()
        let proxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: ProxyCredentials(password: "secret"),
            forwarder: forwarder,
            profileID: UUID(),
            connectionLeaseID: forwarder.leaseID
        )
        try await proxy.start()
        proxy.activate()
        defer { proxy.stop() }

        let result = try SystemProcessExecutor().execute(
            command: "/usr/sbin/lsof",
            arguments: [
                "-nP",
                "-a",
                "-p", "\(getpid())",
                "-iTCP:\(proxy.port)",
                "-sTCP:LISTEN",
                "-Fn",
            ]
        )
        #expect(result.exitCode == 0)
        let endpoints = Set(
            result.stdout.split(separator: "\n")
                .filter { $0.first == "n" }
                .map { String($0.dropFirst()) }
        )
        #expect(endpoints == ["127.0.0.1:\(proxy.port)", "[::1]:\(proxy.port)"])
    }
}
