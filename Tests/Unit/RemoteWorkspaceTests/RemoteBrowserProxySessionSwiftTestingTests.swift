// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteBrowserProxySessionSwiftTestingTests.swift - Scoped browser proxy lifecycle tests.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
private final class RemoteBrowserSessionForwarder: PortForwarding {
    var leaseID: UUID?

    init(leaseID: UUID? = UUID()) {
        self.leaseID = leaseID
    }

    func connectionLeaseID(for profileID: UUID) -> UUID? { leaseID }
    func forwardPort(_ forward: RemoteConnectionProfile.PortForward, for profileID: UUID) throws {}
    func cancelForward(_ forward: RemoteConnectionProfile.PortForward, for profileID: UUID) throws {}
}

@MainActor
private final class RemoteBrowserSessionProxy: SOCKS5ProxyLifecycle {
    let port: Int
    var activeConnectionCount = 0
    var isReady = false
    var failureHandler: (@MainActor @Sendable (String) -> Void)?
    var startError: (any Error)?
    var onStart: (() -> Void)?
    private(set) var activateCallCount = 0
    private(set) var stopCallCount = 0

    init(port: Int) {
        self.port = port
    }

    func start() async throws {
        onStart?()
        if let startError { throw startError }
        isReady = true
    }

    func activate() {
        activateCallCount += 1
    }

    func stop() {
        stopCallCount += 1
        isReady = false
    }

    func releaseAfterSessionTermination() {
        stop()
    }
}

@MainActor
private final class RemoteBrowserSessionProxyRecorder {
    var failingPorts = Set<Int>()
    var onStart: ((Int) -> Void)?
    private(set) var proxies: [RemoteBrowserSessionProxy] = []
    private(set) var targetMappings: [[ProxyTarget: ProxyTarget]] = []

    func make(
        port: Int,
        credentials: ProxyCredentials,
        forwarder: any PortForwarding,
        profileID: UUID,
        connectionLeaseID: UUID,
        targetMappings: [ProxyTarget: ProxyTarget]
    ) -> any SOCKS5ProxyLifecycle {
        _ = credentials
        _ = forwarder
        _ = profileID
        _ = connectionLeaseID
        let proxy = RemoteBrowserSessionProxy(port: port)
        if failingPorts.contains(port) {
            proxy.startError = POSIXError(.EADDRINUSE)
        }
        proxy.onStart = { [weak self] in self?.onStart?(port) }
        proxies.append(proxy)
        self.targetMappings.append(targetMappings)
        return proxy
    }
}

@Suite("Remote browser proxy session", .serialized)
struct RemoteBrowserProxySessionSwiftTestingTests {
    @Test("Capability is bound to window, profile, port, and an exact target mapping")
    @MainActor func capabilityIsFullyScoped() async throws {
        let owner = WindowID()
        let profileID = UUID()
        let forwarder = RemoteBrowserSessionForwarder()
        let recorder = RemoteBrowserSessionProxyRecorder()
        recorder.failingPorts = [51_000]
        let session = RemoteBrowserProxySession(
            ownerWindowID: owner,
            profileID: profileID,
            remotePort: 3_000,
            forwarder: forwarder,
            portCandidates: { [51_000, 51_001, 51_001, 0] },
            proxyFactory: recorder.make
        )

        let capability = try await session.start()

        #expect(capability.ownerWindowID == owner)
        #expect(capability.profileID == profileID)
        #expect(capability.remotePort == 3_000)
        #expect(capability.localProxyPort == 51_001)
        #expect(capability.credentials.password.count >= 40)
        #expect(capability.expiresAt > Date())
        #expect(capability.browserHost == RemoteBrowserProxyCapability.browserHost(for: owner))
        #expect(recorder.proxies.count == 2)
        #expect(recorder.proxies[0].stopCallCount == 1)
        #expect(recorder.proxies[1].activateCallCount == 1)
        #expect(recorder.targetMappings.last == [
            try ProxyTarget(host: capability.browserHost, port: 3_000):
                try ProxyTarget(host: "localhost", port: 3_000),
        ])
    }

    @Test("A lease change during listener startup fails closed")
    @MainActor func leaseChangeRejectsActivation() async {
        let profileID = UUID()
        let forwarder = RemoteBrowserSessionForwarder()
        let recorder = RemoteBrowserSessionProxyRecorder()
        recorder.onStart = { _ in forwarder.leaseID = UUID() }
        let session = RemoteBrowserProxySession(
            ownerWindowID: WindowID(),
            profileID: profileID,
            remotePort: 5_173,
            forwarder: forwarder,
            portCandidates: { [52_000] },
            proxyFactory: recorder.make
        )

        await #expect(throws: RemoteBrowserProxySessionError.connectionChanged) {
            _ = try await session.start()
        }
        #expect(session.capability == nil)
        #expect(recorder.proxies.first?.stopCallCount == 1)
        #expect(recorder.proxies.first?.activateCallCount == 0)
    }

    @Test("Invalid capability lifetimes fail before listener allocation")
    @MainActor func invalidLifetimeFailsBeforeListenerAllocation() async {
        let recorder = RemoteBrowserSessionProxyRecorder()
        let session = RemoteBrowserProxySession(
            ownerWindowID: WindowID(),
            profileID: UUID(),
            remotePort: 5_173,
            forwarder: RemoteBrowserSessionForwarder(),
            lifetime: .infinity,
            portCandidates: { [52_000] },
            proxyFactory: recorder.make
        )

        await #expect(throws: RemoteBrowserProxySessionError.invalidLifetime) {
            _ = try await session.start()
        }
        #expect(recorder.proxies.isEmpty)
    }

    @Test("Stopping a route immediately revokes its in-memory capability")
    @MainActor func stopRevokesCapability() async throws {
        let recorder = RemoteBrowserSessionProxyRecorder()
        let forwarder = RemoteBrowserSessionForwarder()
        let session = RemoteBrowserProxySession(
            ownerWindowID: WindowID(),
            profileID: UUID(),
            remotePort: 8_080,
            forwarder: forwarder,
            portCandidates: { [53_000] },
            proxyFactory: recorder.make
        )
        _ = try await session.start()

        session.stop()

        #expect(session.capability == nil)
        #expect(recorder.proxies.first?.stopCallCount == 1)
    }

    @Test("Listener failure revokes the route and reports a bounded reason")
    @MainActor func listenerFailureInvalidatesSession() async throws {
        let recorder = RemoteBrowserSessionProxyRecorder()
        let forwarder = RemoteBrowserSessionForwarder()
        let session = RemoteBrowserProxySession(
            ownerWindowID: WindowID(),
            profileID: UUID(),
            remotePort: 8_888,
            forwarder: forwarder,
            portCandidates: { [54_000] },
            proxyFactory: recorder.make
        )
        var invalidation: RemoteBrowserProxyInvalidation?
        session.invalidationHandler = { invalidation = $0 }
        _ = try await session.start()

        recorder.proxies.first?.failureHandler?("listener stopped")

        #expect(session.capability == nil)
        #expect(invalidation == .listenerFailed("listener stopped"))
        #expect(recorder.proxies.first?.stopCallCount == 1)
    }

    @Test("Capability expiry revokes the listener")
    @MainActor func expiryRevokesListener() async throws {
        let recorder = RemoteBrowserSessionProxyRecorder()
        let forwarder = RemoteBrowserSessionForwarder()
        let session = RemoteBrowserProxySession(
            ownerWindowID: WindowID(),
            profileID: UUID(),
            remotePort: 9_000,
            forwarder: forwarder,
            lifetime: 0.02,
            portCandidates: { [55_000] },
            proxyFactory: recorder.make
        )
        var invalidation: RemoteBrowserProxyInvalidation?
        session.invalidationHandler = { invalidation = $0 }
        _ = try await session.start()

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(session.capability == nil)
        #expect(invalidation == .expired)
        #expect(recorder.proxies.first?.stopCallCount == 1)
    }
}
