// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyManagerTests.swift - Tests for ProxyManager state machine and lifecycle.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Test Doubles

/// Mock port forwarder that records calls without real SSH.
@MainActor
final class MockPortForwarder: PortForwarding {

    var forwardedPorts: [RemoteConnectionProfile.PortForward] = []
    var forwardedProfileIDs: [UUID] = []
    var cancelledPorts: [RemoteConnectionProfile.PortForward] = []
    var cancelledProfileIDs: [UUID] = []
    var shouldThrow = false
    var shouldThrowOnCancel = false
    var currentConnectionLeaseID: UUID? = UUID()

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        _ = profileID
        return currentConnectionLeaseID
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        if shouldThrow {
            throw SSHMultiplexerError.connectionFailed("Mock forward error")
        }
        forwardedPorts.append(forward)
        forwardedProfileIDs.append(profileID)
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        if shouldThrowOnCancel {
            throw SSHMultiplexerError.forwardFailed("Mock cancellation error")
        }
        cancelledPorts.append(forward)
        cancelledProfileIDs.append(profileID)
    }
}

@MainActor
private final class HTTPConnectStartGate {
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]

    func wait(port: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations[port] = continuation
        }
    }

    func isWaiting(port: Int) -> Bool {
        continuations[port] != nil
    }

    func resume(port: Int) {
        continuations.removeValue(forKey: port)?.resume()
    }
}

@MainActor
private final class MockHTTPConnectProxy: HTTPConnectProxyLifecycle {
    let port: Int
    let gate: HTTPConnectStartGate
    private(set) var activeConnectionCount = 0
    private(set) var activateCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var releaseCallCount = 0
    var shouldThrowOnStop = false

    init(port: Int, gate: HTTPConnectStartGate) {
        self.port = port
        self.gate = gate
    }

    func start() async throws {
        try await gate.wait(port: port)
    }

    func activate() {
        activateCallCount += 1
    }

    func stop() throws {
        stopCallCount += 1
        if shouldThrowOnStop {
            throw SSHMultiplexerError.forwardFailed("Mock HTTP cleanup error")
        }
    }

    func releaseAfterSessionTermination() {
        releaseCallCount += 1
    }
}

// MARK: - ProxyManager Tests

@Suite("ProxyManager")
struct ProxyManagerTests {

    private static let portLock = NSLock()
    private static var nextHTTPPort = 38888

    private static func uniqueHTTPConnectPort() -> Int {
        portLock.lock()
        defer { portLock.unlock() }
        let port = nextHTTPPort
        nextHTTPPort += 1
        return port
    }

    @Test("Initial state is off")
    @MainActor func initialState() {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        #expect(manager.state == .off)
        _ = forwarder // retain
    }

    @Test("enableSOCKS transitions to active with correct port")
    @MainActor func enableSOCKS() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        try await manager.enableSOCKS(port: 1080, profileID: UUID())
        #expect(manager.state == .active(socksPort: 1080, httpPort: nil))
        #expect(forwarder.forwardedPorts.count == 1)
        if case .dynamic(let port) = forwarder.forwardedPorts.first {
            #expect(port == 1080)
        } else {
            Issue.record("Expected dynamic forward")
        }
    }

    @Test("enableSOCKS failure transitions to failing state")
    @MainActor func enableSOCKSFailure() async {
        let forwarder = MockPortForwarder()
        forwarder.shouldThrow = true
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        do {
            try await manager.enableSOCKS(port: 1080, profileID: UUID())
            Issue.record("Expected error to be thrown")
        } catch {
            // SSHMultiplexerError string includes the case name.
            if case .failing = manager.state {
                // State correctly transitioned to failing.
            } else {
                Issue.record("Expected .failing state, got \(manager.state)")
            }
        }
    }

    @Test("disable returns to off and cancels forward")
    @MainActor func disable() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        await manager.disable(profileID: profileID)
        #expect(manager.state == .off)
        #expect(forwarder.cancelledPorts.count == 1)
    }

    @Test("disable when already off is safe no-op")
    @MainActor func disableWhenOff() async {
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: MockPortForwarder()
        )
        await manager.disable(profileID: UUID())
        #expect(manager.state == .off)
    }

    @Test("failed disable retains exact SOCKS ownership for retry")
    @MainActor func disableCancellationFailureIsRetryable() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        let tunnelID = try #require(tunnelManager.listTunnels(for: profileID).first?.id)
        forwarder.shouldThrowOnCancel = true

        await manager.disable(profileID: profileID)

        #expect(manager.hasTrackedSOCKSForward)
        #expect(tunnelManager.listTunnels(for: profileID).map(\.id) == [tunnelID])
        guard case .failing = manager.state else {
            Issue.record("Expected failed cancellation to remain visible")
            return
        }

        forwarder.shouldThrowOnCancel = false
        await manager.disable(profileID: profileID)
        #expect(!manager.hasTrackedSOCKSForward)
        #expect(manager.state == .off)
        #expect(tunnelManager.listTunnels(for: profileID).isEmpty)
    }

    @Test("disable retains ownership when the forwarder is unavailable")
    @MainActor func disableWithoutForwarderRetainsOwnership() async throws {
        var forwarder: MockPortForwarder? = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: try #require(forwarder)
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        let tunnelID = try #require(tunnelManager.listTunnels(for: profileID).first?.id)

        forwarder = nil
        await manager.disable(profileID: profileID)

        #expect(manager.hasTrackedSOCKSForward)
        #expect(tunnelManager.listTunnels(for: profileID).map(\.id) == [tunnelID])
        guard case .failing = manager.state else {
            Issue.record("Expected unavailable cleanup authority to remain visible")
            return
        }
    }

    @Test("disable for another profile is a no-op")
    @MainActor func disableForWrongProfile() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let ownerProfileID = UUID()
        let otherProfileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: ownerProfileID)
        let tunnelID = try #require(
            tunnelManager.listTunnels(for: ownerProfileID).first?.id
        )

        await manager.disable(profileID: otherProfileID)

        #expect(manager.state == .active(socksPort: 1080, httpPort: nil))
        #expect(forwarder.cancelledPorts.isEmpty)
        #expect(tunnelManager.listTunnels(for: ownerProfileID).map(\.id) == [tunnelID])

        await manager.disable(profileID: ownerProfileID)
    }

    @Test("disable does not cancel an old forward on a replacement lease")
    @MainActor func disableWithStaleLease() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let profileID = UUID()
        let originalLeaseID = UUID()
        forwarder.currentConnectionLeaseID = originalLeaseID
        try await manager.enableSOCKS(port: 1080, profileID: profileID)

        forwarder.currentConnectionLeaseID = UUID()
        await manager.disable(profileID: profileID)

        #expect(forwarder.cancelledPorts.isEmpty)
        #expect(manager.state == .off)
        #expect(tunnelManager.listTunnels(for: profileID).isEmpty)
    }

    @Test("new SOCKS owner replaces the prior owner with exact cleanup")
    @MainActor func enableSOCKSReplacesPriorOwner() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: firstProfileID)
        let firstTunnelID = try #require(
            tunnelManager.listTunnels(for: firstProfileID).first?.id
        )

        try await manager.enableSOCKS(port: 1081, profileID: secondProfileID)

        #expect(forwarder.forwardedPorts == [.dynamic(localPort: 1080), .dynamic(localPort: 1081)])
        #expect(forwarder.forwardedProfileIDs == [firstProfileID, secondProfileID])
        #expect(forwarder.cancelledPorts == [.dynamic(localPort: 1080)])
        #expect(forwarder.cancelledProfileIDs == [firstProfileID])
        #expect(!tunnelManager.listTunnels(for: firstProfileID).contains { $0.id == firstTunnelID })
        #expect(tunnelManager.listTunnels(for: secondProfileID).count == 1)
        #expect(manager.state == .active(socksPort: 1081, httpPort: nil))

        await manager.disable(profileID: secondProfileID)
    }

    @Test("failed owner cleanup leaves the prior forward tracked and blocks replacement")
    @MainActor func enableSOCKSCleanupFailure() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: firstProfileID)
        let firstTunnelID = try #require(
            tunnelManager.listTunnels(for: firstProfileID).first?.id
        )
        forwarder.shouldThrowOnCancel = true

        do {
            try await manager.enableSOCKS(port: 1081, profileID: secondProfileID)
            Issue.record("Expected prior owner cleanup to fail")
        } catch {
            #expect(error is SSHMultiplexerError)
        }

        #expect(forwarder.forwardedPorts == [.dynamic(localPort: 1080)])
        #expect(forwarder.cancelledPorts.isEmpty)
        #expect(tunnelManager.listTunnels(for: firstProfileID).map(\.id) == [firstTunnelID])
        #expect(tunnelManager.listTunnels(for: secondProfileID).isEmpty)
        guard case .failing = manager.state else {
            Issue.record("Expected failed replacement cleanup to remain visible")
            return
        }

        forwarder.shouldThrowOnCancel = false
        await manager.disable(profileID: firstProfileID)
    }

    @Test("enableSOCKS then enableHTTPConnect shows both ports")
    @MainActor func enableBoth() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let profileID = UUID()
        let httpPort = Self.uniqueHTTPConnectPort()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        try await manager.enableHTTPConnect(port: httpPort, profileID: profileID)
        #expect(manager.state == .active(socksPort: 1080, httpPort: httpPort))
        await manager.disable(profileID: profileID)
    }

    @Test("concurrent HTTP CONNECT starts keep only the newest listener")
    @MainActor func concurrentHTTPConnectStarts() async throws {
        let forwarder = MockPortForwarder()
        let gate = HTTPConnectStartGate()
        var proxies: [MockHTTPConnectProxy] = []
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder,
            httpConnectProxyFactory: { port, _, _, _ in
                let proxy = MockHTTPConnectProxy(port: port, gate: gate)
                proxies.append(proxy)
                return proxy
            }
        )
        let profileID = UUID()
        let firstPort = Self.uniqueHTTPConnectPort()
        let secondPort = Self.uniqueHTTPConnectPort()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)

        let firstStart = Task { @MainActor in
            try await manager.enableHTTPConnect(port: firstPort, profileID: profileID)
        }
        for _ in 0..<50 where !gate.isWaiting(port: firstPort) {
            await Task.yield()
        }
        #expect(gate.isWaiting(port: firstPort))

        let secondStart = Task { @MainActor in
            try await manager.enableHTTPConnect(port: secondPort, profileID: profileID)
        }
        for _ in 0..<50 where !gate.isWaiting(port: secondPort) {
            await Task.yield()
        }
        #expect(gate.isWaiting(port: secondPort))
        #expect(proxies.first?.stopCallCount == 1)
        #expect(proxies.first?.activateCallCount == 0)

        gate.resume(port: secondPort)
        try await secondStart.value
        gate.resume(port: firstPort)
        do {
            try await firstStart.value
            Issue.record("Expected the superseded listener start to be rejected")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        }

        #expect(manager.httpConnectProxy?.port == secondPort)
        #expect(proxies.count == 2)
        #expect(proxies[0].activateCallCount == 0)
        #expect(proxies[1].activateCallCount == 1)
        #expect(proxies[0].stopCallCount == 1)
        #expect(proxies[1].stopCallCount == 0)

        await manager.disable(profileID: profileID)
        #expect(proxies[1].stopCallCount == 1)
    }

    @Test("HTTP cleanup failure retains ownership and blocks SOCKS cancellation")
    @MainActor func httpCleanupFailureIsRetryable() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let gate = HTTPConnectStartGate()
        var proxies: [MockHTTPConnectProxy] = []
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder,
            httpConnectProxyFactory: { port, _, _, _ in
                let proxy = MockHTTPConnectProxy(port: port, gate: gate)
                proxies.append(proxy)
                return proxy
            }
        )
        let profileID = UUID()
        let httpPort = Self.uniqueHTTPConnectPort()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        let tunnelID = try #require(tunnelManager.listTunnels(for: profileID).first?.id)

        let start = Task { @MainActor in
            try await manager.enableHTTPConnect(port: httpPort, profileID: profileID)
        }
        for _ in 0..<50 where !gate.isWaiting(port: httpPort) {
            await Task.yield()
        }
        #expect(gate.isWaiting(port: httpPort))
        gate.resume(port: httpPort)
        try await start.value

        let proxy = try #require(proxies.first)
        proxy.shouldThrowOnStop = true
        await manager.disable(profileID: profileID)

        #expect(proxy.stopCallCount == 1)
        #expect(manager.httpConnectProxy?.port == httpPort)
        #expect(manager.hasTrackedSOCKSForward)
        #expect(forwarder.cancelledPorts.isEmpty)
        #expect(tunnelManager.listTunnels(for: profileID).map(\.id) == [tunnelID])
        guard case .failing = manager.state else {
            Issue.record("Expected HTTP cleanup failure to remain visible")
            return
        }

        proxy.shouldThrowOnStop = false
        await manager.disable(profileID: profileID)
        #expect(proxy.stopCallCount == 2)
        #expect(manager.httpConnectProxy == nil)
        #expect(forwarder.cancelledPorts == [.dynamic(localPort: 1080)])
        #expect(manager.state == .off)
        #expect(tunnelManager.listTunnels(for: profileID).isEmpty)
    }

    @Test("proven SSH termination releases retained HTTP ownership without cancellation")
    @MainActor func releaseHTTPAfterSessionTermination() async throws {
        let forwarder = MockPortForwarder()
        let gate = HTTPConnectStartGate()
        var proxies: [MockHTTPConnectProxy] = []
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder,
            httpConnectProxyFactory: { port, _, _, _ in
                let proxy = MockHTTPConnectProxy(port: port, gate: gate)
                proxies.append(proxy)
                return proxy
            }
        )
        let profileID = UUID()
        let connectionLeaseID = try #require(forwarder.currentConnectionLeaseID)
        let httpPort = Self.uniqueHTTPConnectPort()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)

        let start = Task { @MainActor in
            try await manager.enableHTTPConnect(port: httpPort, profileID: profileID)
        }
        for _ in 0..<50 where !gate.isWaiting(port: httpPort) {
            await Task.yield()
        }
        #expect(gate.isWaiting(port: httpPort))
        gate.resume(port: httpPort)
        try await start.value

        let proxy = try #require(proxies.first)
        proxy.shouldThrowOnStop = true
        manager.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        #expect(proxy.stopCallCount == 1)
        #expect(manager.httpConnectProxy?.port == httpPort)

        manager.releaseAfterSessionTermination(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        #expect(proxy.releaseCallCount == 1)
        #expect(manager.httpConnectProxy == nil)
        #expect(forwarder.cancelledPorts.isEmpty)
        #expect(manager.state == .off)
    }

    @Test("enableHTTPConnect without SOCKS throws error")
    @MainActor func httpWithoutSOCKS() async {
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: MockPortForwarder()
        )
        do {
            try await manager.enableHTTPConnect(port: Self.uniqueHTTPConnectPort(), profileID: UUID())
            Issue.record("Expected socksNotActive error")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("HTTP CONNECT requires the active SOCKS owner and lease")
    @MainActor func httpRequiresSOCKSOwnership() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let ownerProfileID = UUID()
        let originalLeaseID = try #require(forwarder.currentConnectionLeaseID)
        try await manager.enableSOCKS(port: 1080, profileID: ownerProfileID)

        do {
            try await manager.enableHTTPConnect(
                port: Self.uniqueHTTPConnectPort(),
                profileID: UUID()
            )
            Issue.record("Expected a different profile to be rejected")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        forwarder.currentConnectionLeaseID = UUID()
        do {
            try await manager.enableHTTPConnect(
                port: Self.uniqueHTTPConnectPort(),
                profileID: ownerProfileID
            )
            Issue.record("Expected a replacement lease to be rejected")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(manager.httpConnectProxy == nil)
        forwarder.currentConnectionLeaseID = originalLeaseID
        await manager.disable(profileID: ownerProfileID)
    }

    @Test("disable clears both SOCKS and HTTP Connect")
    @MainActor func disableClearsBoth() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let profileID = UUID()
        let httpPort = Self.uniqueHTTPConnectPort()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        try await manager.enableHTTPConnect(port: httpPort, profileID: profileID)
        await manager.disable(profileID: profileID)
        #expect(manager.state == .off)
        #expect(forwarder.cancelledPorts.count == 1)
    }

    @Test("healthCheck returns false when off")
    @MainActor func healthCheckWhenOff() async {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let result = await manager.healthCheck()
        #expect(!result)
        _ = forwarder // retain
    }

    @Test("healthCheck returns true when active")
    @MainActor func healthCheckWhenActive() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        try await manager.enableSOCKS(port: 1080, profileID: UUID())
        let result = await manager.healthCheck()
        #expect(result)
    }

    @Test("tunnel manager tracks active tunnel")
    @MainActor func tunnelManagerTracking() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        let tunnels = tunnelManager.listTunnels(for: profileID)
        #expect(tunnels.count == 1)
    }

    @Test("disable removes tunnels from tunnel manager")
    @MainActor func disableRemovesTunnels() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        await manager.disable(profileID: profileID)
        let tunnels = tunnelManager.listTunnels(for: profileID)
        #expect(tunnels.isEmpty)
    }

    @Test("disable removes only the proxy tunnel ID")
    @MainActor func disableRemovesOnlyProxyTunnel() async throws {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        let profileID = UUID()
        let unrelatedForward = RemoteConnectionProfile.PortForward.local(
            localPort: 3000,
            remotePort: 3000
        )
        let unrelatedTunnel = tunnelManager.addTunnel(
            forward: unrelatedForward,
            for: profileID
        )
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        let proxyTunnel = try #require(
            tunnelManager.listTunnels(for: profileID).first { $0.id != unrelatedTunnel.id }
        )

        await manager.disable(profileID: profileID)

        let remainingTunnels = tunnelManager.listTunnels(for: profileID)
        #expect(remainingTunnels.map(\.id) == [unrelatedTunnel.id])
        #expect(remainingTunnels.first?.forward == unrelatedForward)
        #expect(!remainingTunnels.contains { $0.id == proxyTunnel.id })
        #expect(forwarder.cancelledPorts == [.dynamic(localPort: 1080)])
        #expect(forwarder.cancelledProfileIDs == [profileID])
    }

    @Test("ProxyState equality works correctly")
    func stateEquality() {
        #expect(ProxyState.off == ProxyState.off)
        #expect(ProxyState.starting == ProxyState.starting)
        #expect(ProxyState.active(socksPort: 1080, httpPort: nil) == ProxyState.active(socksPort: 1080, httpPort: nil))
        #expect(ProxyState.active(socksPort: 1080, httpPort: 8888) != ProxyState.active(socksPort: 1080, httpPort: nil))
        #expect(ProxyState.failing(reason: "test") == ProxyState.failing(reason: "test"))
        #expect(ProxyState.failover == ProxyState.failover)
    }

    @Test("ProxyError equality works correctly")
    func errorEquality() {
        #expect(ProxyError.socksNotActive == ProxyError.socksNotActive)
        #expect(ProxyError.httpConnectFailed("a") == ProxyError.httpConnectFailed("a"))
        #expect(ProxyError.systemProxyFailed("x") != ProxyError.systemProxyFailed("y"))
    }
}
