// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyManagerTests.swift - Tests for authenticated proxy lifecycle ownership.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Shared Test Double

@MainActor
final class MockPortForwardCompletionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

/// Mock port forwarder shared with the relay manager tests.
@MainActor
final class MockPortForwarder: PortForwarding {
    var forwardedPorts: [RemoteConnectionProfile.PortForward] = []
    var forwardedProfileIDs: [UUID] = []
    var cancelledPorts: [RemoteConnectionProfile.PortForward] = []
    var cancelledProfileIDs: [UUID] = []
    var shouldThrow = false
    var shouldThrowOnCancel = false
    var currentConnectionLeaseID: UUID? = UUID()
    var forwardCompletionGate: MockPortForwardCompletionGate?

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        _ = profileID
        return currentConnectionLeaseID
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) async throws {
        if shouldThrow {
            throw SSHMultiplexerError.connectionFailed("Mock forward error")
        }
        forwardedPorts.append(forward)
        forwardedProfileIDs.append(profileID)
        await forwardCompletionGate?.wait()
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) async throws {
        if shouldThrowOnCancel {
            throw SSHMultiplexerError.forwardFailed("Mock cancellation error")
        }
        cancelledPorts.append(forward)
        cancelledProfileIDs.append(profileID)
    }
}

// MARK: - Authenticated Proxy Test Doubles

@MainActor
private final class ProxyStartGate {
    enum Failure: Error {
        case rejected
    }

    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]

    func wait(port: Int) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[port] = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel(port: port)
            }
        }
    }

    func isWaiting(port: Int) -> Bool {
        continuations[port] != nil
    }

    func resume(port: Int) {
        continuations.removeValue(forKey: port)?.resume()
    }

    func fail(port: Int) {
        continuations.removeValue(forKey: port)?.resume(throwing: Failure.rejected)
    }

    private func cancel(port: Int) {
        continuations.removeValue(forKey: port)?.resume(throwing: CancellationError())
    }
}

@MainActor
private final class MockSOCKS5Proxy: SOCKS5ProxyLifecycle {
    let port: Int
    let gate: ProxyStartGate
    var activeConnectionCount = 0
    var isReady = true
    var failureHandler: (@MainActor @Sendable (String) -> Void)?
    private(set) var startCallCount = 0
    private(set) var activateCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var releaseCallCount = 0

    init(port: Int, gate: ProxyStartGate) {
        self.port = port
        self.gate = gate
    }

    func start() async throws {
        startCallCount += 1
        try await gate.wait(port: port)
    }

    func activate() {
        activateCallCount += 1
    }

    func stop() {
        stopCallCount += 1
        isReady = false
    }

    func releaseAfterSessionTermination() {
        releaseCallCount += 1
        isReady = false
    }

    func fail(reason: String) {
        failureHandler?(reason)
    }
}

@MainActor
private final class MockHTTPConnectProxy: HTTPConnectProxyLifecycle {
    let port: Int
    let gate: ProxyStartGate
    var activeConnectionCount = 0
    var isReady = true
    var failureHandler: (@MainActor @Sendable (String) -> Void)?
    private(set) var startCallCount = 0
    private(set) var activateCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var releaseCallCount = 0

    init(port: Int, gate: ProxyStartGate) {
        self.port = port
        self.gate = gate
    }

    func start() async throws {
        startCallCount += 1
        try await gate.wait(port: port)
    }

    func activate() {
        activateCallCount += 1
    }

    func stop() {
        stopCallCount += 1
        isReady = false
    }

    func releaseAfterSessionTermination() {
        releaseCallCount += 1
        isReady = false
    }

    func fail(reason: String) {
        failureHandler?(reason)
    }
}

@MainActor
private final class ProxyFactoryRecorder {
    let socksGate = ProxyStartGate()
    let httpGate = ProxyStartGate()

    private(set) var socksProxies: [MockSOCKS5Proxy] = []
    private(set) var socksCredentials: [ProxyCredentials] = []
    private(set) var socksProfileIDs: [UUID] = []
    private(set) var socksLeaseIDs: [UUID] = []

    private(set) var httpProxies: [MockHTTPConnectProxy] = []
    private(set) var httpCredentials: [ProxyCredentials] = []
    private(set) var httpProfileIDs: [UUID] = []
    private(set) var httpLeaseIDs: [UUID] = []

    func makeSOCKS(
        port: Int,
        credentials: ProxyCredentials,
        profileID: UUID,
        connectionLeaseID: UUID
    ) -> any SOCKS5ProxyLifecycle {
        let proxy = MockSOCKS5Proxy(port: port, gate: socksGate)
        socksProxies.append(proxy)
        socksCredentials.append(credentials)
        socksProfileIDs.append(profileID)
        socksLeaseIDs.append(connectionLeaseID)
        return proxy
    }

    func makeHTTP(
        port: Int,
        credentials: ProxyCredentials,
        profileID: UUID,
        connectionLeaseID: UUID
    ) -> any HTTPConnectProxyLifecycle {
        let proxy = MockHTTPConnectProxy(port: port, gate: httpGate)
        httpProxies.append(proxy)
        httpCredentials.append(credentials)
        httpProfileIDs.append(profileID)
        httpLeaseIDs.append(connectionLeaseID)
        return proxy
    }
}

// MARK: - ProxyManager Tests

@Suite("ProxyManager")
struct ProxyManagerTests {
    @MainActor
    private struct Context {
        let manager: ProxyManagerImpl
        let forwarder: MockPortForwarder
        let tunnelManager: SSHTunnelManager
        let recorder: ProxyFactoryRecorder
    }

    @MainActor
    private func makeContext(
        forwarder suppliedForwarder: MockPortForwarder? = nil
    ) -> Context {
        let forwarder = suppliedForwarder ?? MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let recorder = ProxyFactoryRecorder()
        let manager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder,
            socks5ProxyFactory: { port, credentials, _, profileID, leaseID in
                recorder.makeSOCKS(
                    port: port,
                    credentials: credentials,
                    profileID: profileID,
                    connectionLeaseID: leaseID
                )
            },
            httpConnectProxyFactory: { port, credentials, _, profileID, leaseID in
                recorder.makeHTTP(
                    port: port,
                    credentials: credentials,
                    profileID: profileID,
                    connectionLeaseID: leaseID
                )
            }
        )
        return Context(
            manager: manager,
            forwarder: forwarder,
            tunnelManager: tunnelManager,
            recorder: recorder
        )
    }

    @MainActor
    private func waitForStart(_ gate: ProxyStartGate, port: Int) async throws {
        for _ in 0..<200 {
            if gate.isWaiting(port: port) { return }
            await Task.yield()
        }
        _ = try #require(gate.isWaiting(port: port))
    }

    @MainActor
    private func enableSOCKS(
        _ context: Context,
        port: Int = 1_080,
        profileID: UUID
    ) async throws {
        let start = Task { @MainActor in
            try await context.manager.enableSOCKS(port: port, profileID: profileID)
        }
        try await waitForStart(context.recorder.socksGate, port: port)
        context.recorder.socksGate.resume(port: port)
        try await start.value
    }

    @MainActor
    private func enableHTTP(
        _ context: Context,
        port: Int = 8_888,
        profileID: UUID
    ) async throws {
        let start = Task { @MainActor in
            try await context.manager.enableHTTPConnect(port: port, profileID: profileID)
        }
        try await waitForStart(context.recorder.httpGate, port: port)
        context.recorder.httpGate.resume(port: port)
        try await start.value
    }

    @Test("Initial state is off and contains no credential")
    @MainActor func initialState() {
        let context = makeContext()

        #expect(context.manager.state == .off)
        #expect(context.manager.activeProfileID == nil)
        #expect(context.manager.credentials(for: UUID()) == nil)
        #expect(context.manager.httpConnectCredentials(for: UUID()) == nil)
    }

    @Test("SOCKS activation is app-owned, authenticated, and atomic")
    @MainActor func enableSOCKSActivatesAuthenticatedBroker() async throws {
        let context = makeContext()
        let profileID = UUID()
        let leaseID = try #require(context.forwarder.currentConnectionLeaseID)

        try await enableSOCKS(context, profileID: profileID)

        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: nil
        ))
        #expect(context.manager.activeProfileID == profileID)
        #expect(context.manager.credentials(for: profileID) == context.recorder.socksCredentials[0])
        #expect(context.manager.httpConnectCredentials(for: profileID) == nil)
        #expect(context.manager.credentials(for: UUID()) == nil)
        #expect(context.recorder.socksProfileIDs == [profileID])
        #expect(context.recorder.socksLeaseIDs == [leaseID])
        #expect(context.recorder.socksProxies[0].activateCallCount == 1)
        #expect(context.recorder.socksProxies[0].stopCallCount == 0)
        #expect(context.forwarder.forwardedPorts.isEmpty)
        #expect(context.tunnelManager.listTunnels(for: profileID).isEmpty)
    }

    @Test("Active state is published only after each broker accepts connections")
    @MainActor func activePublicationFollowsBrokerActivation() async throws {
        let context = makeContext()
        let profileID = UUID()
        let socksPort = 10_804
        let httpPort = 18_885
        var observedActivatedSOCKS = false
        var observedActivatedHTTP = false
        let subscription = context.manager.statePublisher.sink { state in
            guard case .active(_, let publishedSOCKSPort, let publishedHTTPPort) = state else {
                return
            }
            if publishedSOCKSPort == socksPort, publishedHTTPPort == nil {
                observedActivatedSOCKS = context.recorder.socksProxies.first?.activateCallCount == 1
            }
            if publishedHTTPPort == httpPort {
                observedActivatedHTTP = context.recorder.httpProxies.first?.activateCallCount == 1
            }
        }

        try await enableSOCKS(context, port: socksPort, profileID: profileID)
        try await enableHTTP(context, port: httpPort, profileID: profileID)

        #expect(observedActivatedSOCKS)
        #expect(observedActivatedHTTP)
        withExtendedLifetime(subscription) {}
    }

    @Test("Reentrant termination during SOCKS publication cannot restore active state")
    @MainActor func socksPublicationIsReentrancySafe() async throws {
        let context = makeContext()
        let profileID = UUID()
        let leaseID = try #require(context.forwarder.currentConnectionLeaseID)
        var didTerminate = false
        let terminatingSubscription = context.manager.statePublisher.sink { state in
            guard case .active(_, _, nil) = state, !didTerminate else { return }
            didTerminate = true
            context.manager.prepareForSessionTermination(
                profileID: profileID,
                connectionLeaseID: leaseID
            )
        }
        var observerStates: [ProxyState] = []
        let observingSubscription = context.manager.statePublisher.sink { state in
            observerStates.append(state)
        }

        try await enableSOCKS(context, profileID: profileID)

        #expect(didTerminate)
        #expect(context.manager.state == .off)
        #expect(context.manager.activeProfileID == nil)
        #expect(context.manager.credentials(for: profileID) == nil)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(observerStates == [
            .off,
            .off,
            .starting(profileID: profileID),
            .active(profileID: profileID, socksPort: 1_080, httpPort: nil),
            .off,
        ])
        withExtendedLifetime((terminatingSubscription, observingSubscription)) {}
    }

    @Test("Reentrant termination during HTTP publication cannot restore active state")
    @MainActor func httpPublicationIsReentrancySafe() async throws {
        let context = makeContext()
        let profileID = UUID()
        let leaseID = try #require(context.forwarder.currentConnectionLeaseID)
        try await enableSOCKS(context, profileID: profileID)
        var didTerminate = false
        let terminatingSubscription = context.manager.statePublisher.sink { state in
            guard case .active(_, _, let httpPort) = state,
                  httpPort != nil,
                  !didTerminate else { return }
            didTerminate = true
            context.manager.prepareForSessionTermination(
                profileID: profileID,
                connectionLeaseID: leaseID
            )
        }
        var observerStates: [ProxyState] = []
        let observingSubscription = context.manager.statePublisher.sink { state in
            observerStates.append(state)
        }

        try await enableHTTP(context, profileID: profileID)

        #expect(didTerminate)
        #expect(context.manager.state == .off)
        #expect(context.manager.activeProfileID == nil)
        #expect(context.manager.credentials(for: profileID) == nil)
        #expect(context.manager.httpConnectCredentials(for: profileID) == nil)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.recorder.httpProxies[0].stopCallCount == 1)
        #expect(observerStates == [
            .active(profileID: profileID, socksPort: 1_080, httpPort: nil),
            .active(profileID: profileID, socksPort: 1_080, httpPort: nil),
            .active(profileID: profileID, socksPort: 1_080, httpPort: 8_888),
            .off,
        ])
        withExtendedLifetime((terminatingSubscription, observingSubscription)) {}
    }

    @Test("Invalid SOCKS port is rejected before creating a listener")
    @MainActor func invalidSOCKSPort() async {
        let context = makeContext()

        do {
            try await context.manager.enableSOCKS(port: 0, profileID: UUID())
            Issue.record("Expected invalidPort")
        } catch let error as ProxyError {
            #expect(error == .invalidPort)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.socksProxies.isEmpty)
        #expect(context.manager.state == .off)
    }

    @Test("SOCKS requires a live SSH connection lease")
    @MainActor func socksRequiresLease() async {
        let forwarder = MockPortForwarder()
        forwarder.currentConnectionLeaseID = nil
        let context = makeContext(forwarder: forwarder)
        let profileID = UUID()

        do {
            try await context.manager.enableSOCKS(port: 1_080, profileID: profileID)
            Issue.record("Expected notConnected")
        } catch let error as SSHMultiplexerError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        guard case .failing(let failedProfileID, _) = context.manager.state else {
            Issue.record("Expected a failing state")
            return
        }
        #expect(failedProfileID == profileID)
        #expect(context.recorder.socksProxies.isEmpty)
    }

    @Test("SOCKS start failure clears the pending listener and credential")
    @MainActor func socksStartFailure() async throws {
        let context = makeContext()
        let profileID = UUID()
        let start = Task { @MainActor in
            try await context.manager.enableSOCKS(port: 1_080, profileID: profileID)
        }
        try await waitForStart(context.recorder.socksGate, port: 1_080)

        context.recorder.socksGate.fail(port: 1_080)
        do {
            try await start.value
            Issue.record("Expected the listener start to fail")
        } catch is ProxyStartGate.Failure {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.manager.credentials(for: profileID) == nil)
        guard case .failing(let failedProfileID, _) = context.manager.state else {
            Issue.record("Expected a failing state")
            return
        }
        #expect(failedProfileID == profileID)
    }

    @Test("Cancelling SOCKS startup cannot publish or activate the pending broker")
    @MainActor func cancellingSOCKSStart() async throws {
        let context = makeContext()
        let profileID = UUID()
        let start = Task { @MainActor in
            try await context.manager.enableSOCKS(port: 10_803, profileID: profileID)
        }
        try await waitForStart(context.recorder.socksGate, port: 10_803)

        start.cancel()
        await #expect(throws: CancellationError.self) {
            try await start.value
        }

        #expect(context.manager.state == .off)
        #expect(context.manager.credentials(for: profileID) == nil)
        #expect(context.recorder.socksProxies[0].activateCallCount == 0)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
    }

    @Test("A newer SOCKS start supersedes and stops the older start")
    @MainActor func concurrentSOCKSStarts() async throws {
        let context = makeContext()
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstPort = 10_801
        let secondPort = 10_802

        let firstStart = Task { @MainActor in
            try await context.manager.enableSOCKS(port: firstPort, profileID: firstProfileID)
        }
        try await waitForStart(context.recorder.socksGate, port: firstPort)

        let secondStart = Task { @MainActor in
            try await context.manager.enableSOCKS(port: secondPort, profileID: secondProfileID)
        }
        try await waitForStart(context.recorder.socksGate, port: secondPort)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.recorder.socksProxies[0].activateCallCount == 0)

        context.recorder.socksGate.resume(port: secondPort)
        try await secondStart.value
        context.recorder.socksGate.resume(port: firstPort)
        do {
            try await firstStart.value
            Issue.record("Expected the superseded start to fail")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.socksProxies[0].stopCallCount == 2)
        #expect(context.recorder.socksProxies[1].activateCallCount == 1)
        #expect(context.manager.state == .active(
            profileID: secondProfileID,
            socksPort: secondPort,
            httpPort: nil
        ))
        #expect(context.manager.credentials(for: firstProfileID) == nil)
        #expect(context.manager.credentials(for: secondProfileID) == context.recorder.socksCredentials[1])
    }

    @Test("Replacing the active owner stops old listeners and rotates credentials")
    @MainActor func replaceSOCKSOwner() async throws {
        let context = makeContext()
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        try await enableSOCKS(context, port: 10_811, profileID: firstProfileID)
        let firstCredential = try #require(context.manager.credentials(for: firstProfileID))

        try await enableSOCKS(context, port: 10_812, profileID: secondProfileID)
        let secondCredential = try #require(context.manager.credentials(for: secondProfileID))

        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.recorder.socksProxies[1].activateCallCount == 1)
        #expect(firstCredential != secondCredential)
        #expect(context.manager.credentials(for: firstProfileID) == nil)
        #expect(context.forwarder.cancelledPorts.isEmpty)
    }

    @Test("Disable is owner-scoped and invalidates credentials before teardown completes")
    @MainActor func disableIsOwnerScoped() async throws {
        let context = makeContext()
        let ownerProfileID = UUID()
        try await enableSOCKS(context, profileID: ownerProfileID)

        await context.manager.disable(profileID: UUID())
        #expect(context.recorder.socksProxies[0].stopCallCount == 0)
        #expect(context.manager.credentials(for: ownerProfileID) != nil)

        await context.manager.disable(profileID: ownerProfileID)
        #expect(context.manager.state == .off)
        #expect(context.manager.credentials(for: ownerProfileID) == nil)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
    }

    @Test("Disable cancels a pending SOCKS activation for the same owner")
    @MainActor func disablePendingSOCKS() async throws {
        let context = makeContext()
        let profileID = UUID()
        let start = Task { @MainActor in
            try await context.manager.enableSOCKS(port: 10_821, profileID: profileID)
        }
        try await waitForStart(context.recorder.socksGate, port: 10_821)

        await context.manager.disable(profileID: profileID)
        #expect(context.manager.state == .off)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)

        context.recorder.socksGate.resume(port: 10_821)
        do {
            try await start.value
            Issue.record("Expected the cancelled start to fail")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(context.recorder.socksProxies[0].stopCallCount == 2)
    }

    @Test("SOCKS cannot commit after its SSH lease changes")
    @MainActor func socksLeaseChangesDuringStart() async throws {
        let context = makeContext()
        let profileID = UUID()
        let start = Task { @MainActor in
            try await context.manager.enableSOCKS(port: 10_831, profileID: profileID)
        }
        try await waitForStart(context.recorder.socksGate, port: 10_831)

        context.forwarder.currentConnectionLeaseID = UUID()
        context.recorder.socksGate.resume(port: 10_831)
        do {
            try await start.value
            Issue.record("Expected the stale lease to reject activation")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.socksProxies[0].activateCallCount == 0)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.manager.credentials(for: profileID) == nil)
        guard case .failing(let failedProfileID, _) = context.manager.state else {
            Issue.record("Expected a failing state")
            return
        }
        #expect(failedProfileID == profileID)
    }

    @Test("Session termination cancels an exact pending SOCKS lease")
    @MainActor func terminatePendingSOCKS() async throws {
        let context = makeContext()
        let profileID = UUID()
        let leaseID = try #require(context.forwarder.currentConnectionLeaseID)
        let start = Task { @MainActor in
            try await context.manager.enableSOCKS(port: 10_832, profileID: profileID)
        }
        try await waitForStart(context.recorder.socksGate, port: 10_832)

        context.manager.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: UUID()
        )
        #expect(context.recorder.socksProxies[0].stopCallCount == 0)

        context.manager.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: leaseID
        )
        #expect(context.manager.state == .off)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)

        context.recorder.socksGate.resume(port: 10_832)
        do {
            try await start.value
            Issue.record("Expected the terminated start to fail")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(context.recorder.socksProxies[0].stopCallCount == 2)
    }

    @Test("HTTP CONNECT requires the active SOCKS owner and lease")
    @MainActor func httpRequiresSOCKSOwnerAndLease() async throws {
        let context = makeContext()
        let profileID = UUID()

        do {
            try await context.manager.enableHTTPConnect(port: 8_888, profileID: profileID)
            Issue.record("Expected socksNotActive")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        try await enableSOCKS(context, profileID: profileID)
        do {
            try await context.manager.enableHTTPConnect(port: 8_888, profileID: UUID())
            Issue.record("Expected a profile mismatch to fail")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        context.forwarder.currentConnectionLeaseID = UUID()
        do {
            try await context.manager.enableHTTPConnect(port: 8_888, profileID: profileID)
            Issue.record("Expected a lease mismatch to fail")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.httpProxies.isEmpty)
    }

    @Test("HTTP CONNECT rotates an independent capability and commits atomically")
    @MainActor func enableHTTPConnect() async throws {
        let context = makeContext()
        let profileID = UUID()
        let leaseID = try #require(context.forwarder.currentConnectionLeaseID)
        try await enableSOCKS(context, profileID: profileID)

        try await enableHTTP(context, profileID: profileID)

        #expect(context.recorder.httpCredentials.count == 1)
        #expect(context.recorder.httpCredentials[0] != context.recorder.socksCredentials[0])
        #expect(
            context.manager.httpConnectCredentials(for: profileID)
                == context.recorder.httpCredentials[0]
        )
        #expect(context.recorder.httpProfileIDs == [profileID])
        #expect(context.recorder.httpLeaseIDs == [leaseID])
        #expect(context.recorder.httpProxies[0].activateCallCount == 1)
        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: 8_888
        ))
    }

    @Test("HTTP start failure preserves the authenticated SOCKS listener")
    @MainActor func httpStartFailure() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)
        let start = Task { @MainActor in
            try await context.manager.enableHTTPConnect(port: 18_883, profileID: profileID)
        }
        try await waitForStart(context.recorder.httpGate, port: 18_883)

        context.recorder.httpGate.fail(port: 18_883)
        do {
            try await start.value
            Issue.record("Expected the HTTP listener start to fail")
        } catch let error as ProxyError {
            guard case .httpConnectFailed = error else {
                Issue.record("Expected httpConnectFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.httpProxies[0].stopCallCount == 1)
        #expect(context.recorder.socksProxies[0].stopCallCount == 0)
        #expect(context.manager.credentials(for: profileID) != nil)
        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: nil
        ))
    }

    @Test("Cancelling HTTP startup preserves SOCKS without publishing HTTP credentials")
    @MainActor func cancellingHTTPStart() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)
        let start = Task { @MainActor in
            try await context.manager.enableHTTPConnect(port: 18_884, profileID: profileID)
        }
        try await waitForStart(context.recorder.httpGate, port: 18_884)

        start.cancel()
        await #expect(throws: CancellationError.self) {
            try await start.value
        }

        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: nil
        ))
        #expect(context.manager.credentials(for: profileID) != nil)
        #expect(context.manager.httpConnectCredentials(for: profileID) == nil)
        #expect(context.recorder.httpProxies[0].activateCallCount == 0)
        #expect(context.recorder.httpProxies[0].stopCallCount == 1)
    }

    @Test("HTTP CONNECT can be disabled without stopping SOCKS")
    @MainActor func disableHTTPConnectOnly() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)
        try await enableHTTP(context, profileID: profileID)

        await context.manager.disableHTTPConnect(profileID: UUID())
        #expect(context.recorder.httpProxies[0].stopCallCount == 0)

        await context.manager.disableHTTPConnect(profileID: profileID)
        #expect(context.recorder.httpProxies[0].stopCallCount == 1)
        #expect(context.recorder.socksProxies[0].stopCallCount == 0)
        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: nil
        ))
        #expect(context.manager.credentials(for: profileID) != nil)
        #expect(context.manager.httpConnectCredentials(for: profileID) == nil)
    }

    @Test("Re-enabling HTTP CONNECT invalidates its previous capability")
    @MainActor func reenableHTTPConnectRotatesCredentials() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)
        try await enableHTTP(context, port: 18_881, profileID: profileID)
        let first = try #require(context.manager.httpConnectCredentials(for: profileID))

        await context.manager.disableHTTPConnect(profileID: profileID)
        #expect(context.manager.httpConnectCredentials(for: profileID) == nil)
        try await enableHTTP(context, port: 18_882, profileID: profileID)
        let second = try #require(context.manager.httpConnectCredentials(for: profileID))

        #expect(first != second)
        #expect(context.recorder.httpCredentials == [first, second])
        #expect(context.manager.credentials(for: profileID) == context.recorder.socksCredentials[0])
    }

    @Test("A newer HTTP CONNECT start supersedes the older listener")
    @MainActor func concurrentHTTPConnectStarts() async throws {
        let context = makeContext()
        let profileID = UUID()
        let firstPort = 18_881
        let secondPort = 18_882
        try await enableSOCKS(context, profileID: profileID)

        let firstStart = Task { @MainActor in
            try await context.manager.enableHTTPConnect(port: firstPort, profileID: profileID)
        }
        try await waitForStart(context.recorder.httpGate, port: firstPort)

        let secondStart = Task { @MainActor in
            try await context.manager.enableHTTPConnect(port: secondPort, profileID: profileID)
        }
        try await waitForStart(context.recorder.httpGate, port: secondPort)
        #expect(context.recorder.httpProxies[0].stopCallCount == 1)

        context.recorder.httpGate.resume(port: secondPort)
        try await secondStart.value
        context.recorder.httpGate.resume(port: firstPort)
        do {
            try await firstStart.value
            Issue.record("Expected the superseded HTTP start to fail")
        } catch let error as ProxyError {
            #expect(error == .socksNotActive)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.recorder.httpProxies[0].stopCallCount == 2)
        #expect(context.recorder.httpProxies[1].activateCallCount == 1)
        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: secondPort
        ))
        context.recorder.httpProxies[0].fail(reason: "stale failure")
        #expect(context.manager.state == .active(
            profileID: profileID,
            socksPort: 1_080,
            httpPort: secondPort
        ))
    }

    @Test("Unexpected SOCKS listener failure revokes the capability session")
    @MainActor func socksRuntimeFailure() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)

        context.recorder.socksProxies[0].fail(reason: "listener failed")

        #expect(context.manager.credentials(for: profileID) == nil)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        guard case .failing(let failedProfileID, let reason) = context.manager.state else {
            Issue.record("Expected a failing state")
            return
        }
        #expect(failedProfileID == profileID)
        #expect(reason == "listener failed")
    }

    @Test("Unexpected HTTP listener failure revokes both authenticated listeners")
    @MainActor func httpRuntimeFailure() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)
        try await enableHTTP(context, profileID: profileID)

        context.recorder.httpProxies[0].fail(reason: "listener failed")

        #expect(context.manager.credentials(for: profileID) == nil)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.recorder.httpProxies[0].stopCallCount == 1)
        #expect(context.manager.state == .failing(
            profileID: profileID,
            reason: "listener failed"
        ))
    }

    @Test("Session termination tears down exact owner listeners and credentials")
    @MainActor func prepareForSessionTermination() async throws {
        let context = makeContext()
        let profileID = UUID()
        let leaseID = try #require(context.forwarder.currentConnectionLeaseID)
        try await enableSOCKS(context, profileID: profileID)
        try await enableHTTP(context, profileID: profileID)

        context.manager.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: UUID()
        )
        #expect(context.recorder.socksProxies[0].stopCallCount == 0)

        context.manager.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: leaseID
        )
        #expect(context.manager.state == .off)
        #expect(context.manager.credentials(for: profileID) == nil)
        #expect(context.recorder.socksProxies[0].stopCallCount == 1)
        #expect(context.recorder.httpProxies[0].stopCallCount == 1)

        context.manager.releaseAfterSessionTermination(
            profileID: profileID,
            connectionLeaseID: leaseID
        )
        #expect(context.recorder.socksProxies[0].releaseCallCount == 0)
        #expect(context.recorder.httpProxies[0].releaseCallCount == 0)
    }

    @Test("Health check requires ready listeners on the exact SSH lease")
    @MainActor func healthCheck() async throws {
        let context = makeContext()
        let profileID = UUID()
        try await enableSOCKS(context, profileID: profileID)

        #expect(await context.manager.healthCheck())
        context.recorder.socksProxies[0].isReady = false
        #expect(!(await context.manager.healthCheck()))
        context.recorder.socksProxies[0].isReady = true
        context.forwarder.currentConnectionLeaseID = UUID()
        #expect(!(await context.manager.healthCheck()))
    }

    @Test("ProxyState equality includes its owning profile")
    func stateEquality() {
        let firstProfileID = UUID()
        let secondProfileID = UUID()

        #expect(ProxyState.off == ProxyState.off)
        #expect(ProxyState.starting(profileID: firstProfileID) == .starting(profileID: firstProfileID))
        #expect(ProxyState.starting(profileID: firstProfileID) != .starting(profileID: secondProfileID))
        #expect(ProxyState.active(
            profileID: firstProfileID,
            socksPort: 1_080,
            httpPort: 8_888
        ) != .active(
            profileID: secondProfileID,
            socksPort: 1_080,
            httpPort: 8_888
        ))
        #expect(ProxyState.failing(
            profileID: firstProfileID,
            reason: "test"
        ) == .failing(
            profileID: firstProfileID,
            reason: "test"
        ))
        #expect(ProxyState.failover(profileID: firstProfileID) == .failover(profileID: firstProfileID))
    }

    @Test("ProxyError equality works correctly")
    func errorEquality() {
        #expect(ProxyError.socksNotActive == ProxyError.socksNotActive)
        #expect(ProxyError.httpConnectFailed("a") == ProxyError.httpConnectFailed("a"))
        #expect(ProxyError.systemProxyFailed("x") != ProxyError.systemProxyFailed("y"))
    }
}
