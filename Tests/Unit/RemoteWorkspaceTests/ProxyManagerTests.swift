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
    var cancelledPorts: [RemoteConnectionProfile.PortForward] = []
    var shouldThrow = false

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        if shouldThrow {
            throw SSHMultiplexerError.connectionFailed("Mock forward error")
        }
        forwardedPorts.append(forward)
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        cancelledPorts.append(forward)
    }
}

// MARK: - ProxyManager Tests

@Suite("ProxyManager")
struct ProxyManagerTests {

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

    @Test("enableSOCKS then enableHTTPConnect shows both ports")
    @MainActor func enableBoth() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        try await manager.enableHTTPConnect(port: 8888, profileID: profileID)
        #expect(manager.state == .active(socksPort: 1080, httpPort: 8888))
    }

    @Test("enableHTTPConnect without SOCKS throws error")
    @MainActor func httpWithoutSOCKS() async {
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: MockPortForwarder()
        )
        do {
            try await manager.enableHTTPConnect(port: 8888, profileID: UUID())
            Issue.record("Expected socksNotActive error")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("disable clears both SOCKS and HTTP Connect")
    @MainActor func disableClearsBoth() async throws {
        let forwarder = MockPortForwarder()
        let manager = ProxyManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let profileID = UUID()
        try await manager.enableSOCKS(port: 1080, profileID: profileID)
        try await manager.enableHTTPConnect(port: 8888, profileID: profileID)
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
