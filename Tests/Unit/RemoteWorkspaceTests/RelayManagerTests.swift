// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManagerTests.swift - Tests for relay manager channel orchestration.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
private func waitForRelayCondition(_ condition: () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

private final class RelayTestTokenStore: RelayTokenStoring, @unchecked Sendable {
    enum TestError: Error {
        case saveFailed
    }

    var stored: [UUID: RelayToken] = [:]
    var shouldFailSave = false

    func save(token: RelayToken, channelID: UUID) throws {
        if shouldFailSave { throw TestError.saveFailed }
        stored[channelID] = token
    }

    func load(channelID: UUID) throws -> RelayToken? {
        stored[channelID]
    }

    func delete(channelID: UUID) throws {
        stored.removeValue(forKey: channelID)
    }
}

@MainActor
private final class MockRelayAuthBroker: RelayAuthBrokering {
    enum TestError: Error {
        case startFailed
    }

    let channelID: UUID
    let targetHost: String
    let targetPort: UInt16
    private(set) var listeningPort: UInt16?
    private(set) var isStarted = false
    private(set) var isStopped = false
    private(set) var isDeactivated = false
    private(set) var authorizationUpdates: [(RelayToken, RelayACL)] = []
    var shouldFailStart = false
    var emitFailureAfterStart = false
    var startDelayNanoseconds: UInt64 = 0
    private var connectionCountHandler: ((Int) -> Void)?
    private var failureHandler: ((any Error) -> Void)?

    init(channelID: UUID, targetHost: String, targetPort: UInt16, port: UInt16) {
        self.channelID = channelID
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.listeningPort = port
    }

    func startOnEphemeralLoopbackPort() async throws -> UInt16 {
        if startDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
        if shouldFailStart { throw TestError.startFailed }
        isStarted = true
        if emitFailureAfterStart {
            failureHandler?(TestError.startFailed)
        }
        return listeningPort ?? 0
    }

    func updateAuthorization(token: RelayToken, acl: RelayACL) {
        authorizationUpdates.append((token, acl))
    }

    func setConnectionCountHandler(_ handler: ((Int) -> Void)?) {
        connectionCountHandler = handler
    }

    func setFailureHandler(_ handler: ((any Error) -> Void)?) {
        failureHandler = handler
    }

    func deactivate() {
        isDeactivated = true
        connectionCountHandler?(0)
    }

    func stop() {
        isStopped = true
        isStarted = false
        listeningPort = nil
        connectionCountHandler = nil
        failureHandler = nil
    }

    func emitConnectionCount(_ count: Int) {
        connectionCountHandler?(count)
    }

    func emitFailure(_ error: any Error) {
        failureHandler?(error)
    }
}

@MainActor
private final class RelayBrokerFactoryRecorder {
    private var nextPort: UInt16 = 45_000
    private(set) var brokers: [MockRelayAuthBroker] = []
    var shouldFailStart = false
    var emitFailureAfterStart = false
    var startDelayNanoseconds: UInt64 = 0

    func make(
        channelID: UUID,
        token: RelayToken,
        acl: RelayACL,
        targetHost: String,
        targetPort: UInt16,
        auditLog: RelayAuditLog?
    ) -> any RelayAuthBrokering {
        _ = token
        _ = acl
        _ = auditLog
        let broker = MockRelayAuthBroker(
            channelID: channelID,
            targetHost: targetHost,
            targetPort: targetPort,
            port: nextPort
        )
        nextPort += 1
        broker.shouldFailStart = shouldFailStart
        broker.emitFailureAfterStart = emitFailureAfterStart
        broker.startDelayNanoseconds = startDelayNanoseconds
        brokers.append(broker)
        return broker
    }
}

@MainActor
private final class RelayProfileRevokerRecorder {
    private(set) var profileIDs: [UUID] = []
    private(set) var connectionLeaseIDs: [UUID] = []
    var succeeds = false
    var shouldSuspend = false
    private(set) var hasPendingRevocation = false
    private var pendingRevocation: CheckedContinuation<Bool, Never>?

    func revoke(_ profileID: UUID, connectionLeaseID: UUID) async -> Bool {
        profileIDs.append(profileID)
        connectionLeaseIDs.append(connectionLeaseID)
        guard shouldSuspend else { return succeeds }
        return await withCheckedContinuation { continuation in
            hasPendingRevocation = true
            pendingRevocation = continuation
        }
    }

    func completePendingRevocation(succeeds: Bool) {
        hasPendingRevocation = false
        pendingRevocation?.resume(returning: succeeds)
        pendingRevocation = nil
    }
}

@Suite("RelayManager")
struct RelayManagerTests {

    @MainActor
    private func makeManager(
        tokenStore: RelayTestTokenStore = RelayTestTokenStore()
    ) -> (
        manager: RelayManagerImpl,
        forwarder: MockPortForwarder,
        tunnelManager: SSHTunnelManager,
        tokenStore: RelayTestTokenStore,
        brokerFactory: RelayBrokerFactoryRecorder,
        profileRevoker: RelayProfileRevokerRecorder
    ) {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let brokerFactory = RelayBrokerFactoryRecorder()
        let profileRevoker = RelayProfileRevokerRecorder()
        let manager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder,
            tokenStore: tokenStore,
            profileSessionRevoker: { profileID, connectionLeaseID in
                await profileRevoker.revoke(
                    profileID,
                    connectionLeaseID: connectionLeaseID
                )
            },
            brokerFactory: { channelID, token, acl, targetHost, targetPort, auditLog in
                brokerFactory.make(
                    channelID: channelID,
                    token: token,
                    acl: acl,
                    targetHost: targetHost,
                    targetPort: targetPort,
                    auditLog: auditLog
                )
            }
        )
        return (
            manager,
            forwarder,
            tunnelManager,
            tokenStore,
            brokerFactory,
            profileRevoker
        )
    }

    @Test("Open channel routes the reverse tunnel only through its auth broker")
    @MainActor func openChannel() async throws {
        let context = makeManager()
        let profileID = UUID()

        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )

        #expect(channel.name == "api")
        #expect(context.brokerFactory.brokers.count == 1)
        #expect(context.brokerFactory.brokers[0].targetHost == "localhost")
        #expect(context.brokerFactory.brokers[0].targetPort == 3000)
        #expect(context.brokerFactory.brokers[0].isStarted)
        #expect(context.forwarder.forwardedPorts.count == 1)
        #expect(context.tokenStore.stored[channel.id] != nil)

        guard case let .remote(remotePort, localPort, localHost) =
            context.forwarder.forwardedPorts[0]
        else {
            Issue.record("Expected a reverse forward")
            return
        }
        #expect(remotePort == 9000)
        #expect(localPort == 45_000)
        #expect(localPort != channel.localPort)
        #expect(localHost == "127.0.0.1")
    }

    @Test("Production broker factory is a live mandatory hop")
    @MainActor func productionBrokerFactory() async throws {
        let forwarder = MockPortForwarder()
        let manager = RelayManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        let profileID = UUID()
        let channel = try await manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )

        let forward = try #require(forwarder.forwardedPorts.first)
        guard case let .remote(remotePort, localPort, localHost) = forward else {
            Issue.record("Expected a reverse forward")
            return
        }
        #expect(remotePort == 9000)
        #expect(localPort != 3000)
        #expect(localPort > 0)
        #expect(localHost == "127.0.0.1")
        await manager.closeChannel(channelID: channel.id)
    }

    @Test("Close channel cancels the exact broker forward and tears down security state")
    @MainActor func closeChannel() async throws {
        let context = makeManager()
        let profileID = UUID()
        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        let broker = context.brokerFactory.brokers[0]

        await context.manager.closeChannel(channelID: channel.id)

        #expect(context.forwarder.cancelledPorts == context.forwarder.forwardedPorts)
        #expect(broker.isStopped)
        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.tunnelManager.listTunnels(for: profileID).isEmpty)
        #expect(context.tokenStore.stored[channel.id] == nil)
    }

    @Test("Failed SSH cancellation quarantines the broker and remains retryable")
    @MainActor func cancellationFailureIsQuarantined() async throws {
        let context = makeManager()
        let profileID = UUID()
        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        context.forwarder.shouldThrowOnCancel = true

        await context.manager.closeChannel(channelID: channel.id)

        let retained = try #require(context.manager.listChannels(profileID: profileID).first)
        guard case .closeFailed = retained.status else {
            Issue.record("Expected closeFailed status")
            return
        }
        #expect(context.brokerFactory.brokers[0].isDeactivated)
        #expect(!context.brokerFactory.brokers[0].isStopped)
        #expect(context.tokenStore.stored[channel.id] != nil)
        #expect(context.manager.clientCommand(for: channel.id) == nil)
        #expect(context.manager.clientToken(for: channel.id) == nil)
        #expect(context.tunnelManager.listTunnels(for: profileID).count == 1)

        context.forwarder.shouldThrowOnCancel = false
        await context.manager.closeChannel(channelID: channel.id)

        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.brokerFactory.brokers[0].isStopped)
        #expect(context.tokenStore.stored[channel.id] == nil)
    }

    @Test("Old-session channel close never cancels a forward on the new lease")
    @MainActor func staleLeaseCloseIsQuarantined() async throws {
        let context = makeManager()
        let profileID = UUID()
        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        context.forwarder.currentConnectionLeaseID = UUID()

        await context.manager.closeChannel(channelID: channel.id)

        #expect(context.forwarder.cancelledPorts.isEmpty)
        let retained = try #require(context.manager.listChannels(profileID: profileID).first)
        guard case .closeFailed = retained.status else {
            Issue.record("Expected closeFailed status")
            return
        }
        #expect(context.brokerFactory.brokers[0].isDeactivated)
        #expect(!context.brokerFactory.brokers[0].isStopped)
    }

    @Test("Runtime broker failure cancels the exact reverse forward")
    @MainActor func brokerFailureCancelsForward() async throws {
        let context = makeManager()
        let profileID = UUID()
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )

        context.brokerFactory.brokers[0].emitFailure(MockRelayAuthBroker.TestError.startFailed)
        await waitForRelayCondition {
            context.manager.listChannels(profileID: profileID).isEmpty
        }

        #expect(context.forwarder.cancelledPorts == context.forwarder.forwardedPorts)
        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.profileRevoker.profileIDs.isEmpty)
    }

    @Test("Old-session broker failure never cancels a forward on the new lease")
    @MainActor func staleLeaseBrokerFailureDoesNotCancelNewForward() async throws {
        let context = makeManager()
        let profileID = UUID()
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        let oldLeaseID = try #require(context.forwarder.currentConnectionLeaseID)
        context.forwarder.currentConnectionLeaseID = UUID()

        context.brokerFactory.brokers[0].emitFailure(MockRelayAuthBroker.TestError.startFailed)
        await waitForRelayCondition {
            !context.profileRevoker.connectionLeaseIDs.isEmpty
        }

        #expect(context.forwarder.cancelledPorts.isEmpty)
        #expect(context.profileRevoker.connectionLeaseIDs == [oldLeaseID])
        let retained = try #require(context.manager.listChannels(profileID: profileID).first)
        guard case .brokerFailed = retained.status else {
            Issue.record("Expected brokerFailed status")
            return
        }
    }

    @Test("Confirmed ControlMaster termination releases quarantined channels")
    @MainActor func sessionTerminationReleasesQuarantine() async throws {
        let context = makeManager()
        let profileID = UUID()
        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        context.forwarder.shouldThrowOnCancel = true
        await context.manager.closeChannel(channelID: channel.id)
        #expect(context.manager.listChannels(profileID: profileID).count == 1)

        context.manager.releaseChannelsAfterSessionTermination(profileID: profileID)

        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.brokerFactory.brokers[0].isStopped)
        #expect(context.tokenStore.stored[channel.id] == nil)
    }

    @Test("Uncancellable broker failure revokes the owning SSH session")
    @MainActor func brokerFailureRevokesProfile() async throws {
        let context = makeManager()
        let profileID = UUID()
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        context.forwarder.shouldThrowOnCancel = true

        context.brokerFactory.brokers[0].emitFailure(MockRelayAuthBroker.TestError.startFailed)
        await waitForRelayCondition {
            !context.profileRevoker.profileIDs.isEmpty
        }

        #expect(context.profileRevoker.profileIDs == [profileID])
        let retained = try #require(context.manager.listChannels(profileID: profileID).first)
        guard case .brokerFailed = retained.status else {
            Issue.record("Expected brokerFailed status")
            return
        }
    }

    @Test("Successful profile revocation releases failed broker state")
    @MainActor func successfulProfileRevocationFinalizesChannel() async throws {
        let context = makeManager()
        let profileID = UUID()
        context.profileRevoker.succeeds = true
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "db", localPort: 5432, remotePort: 9001),
            profileID: profileID
        )
        context.forwarder.shouldThrowOnCancel = true

        context.brokerFactory.brokers[0].emitFailure(MockRelayAuthBroker.TestError.startFailed)
        await waitForRelayCondition {
            context.manager.listChannels(profileID: profileID).isEmpty
        }

        #expect(context.profileRevoker.profileIDs == [profileID])
        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.brokerFactory.brokers[0].isStopped)
        #expect(context.brokerFactory.brokers[1].isStopped)
    }

    @Test("Completed old-session revocation does not close a newly opened channel")
    @MainActor func oldRevocationDoesNotCloseNewChannel() async throws {
        let context = makeManager()
        let profileID = UUID()
        context.profileRevoker.shouldSuspend = true
        let oldConnectionLeaseID = try #require(context.forwarder.currentConnectionLeaseID)
        let oldChannel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "old", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        context.forwarder.shouldThrowOnCancel = true
        context.brokerFactory.brokers[0].emitFailure(MockRelayAuthBroker.TestError.startFailed)

        for _ in 0..<20 where !context.profileRevoker.hasPendingRevocation {
            await Task.yield()
        }
        #expect(context.profileRevoker.hasPendingRevocation)
        #expect(context.profileRevoker.connectionLeaseIDs == [oldConnectionLeaseID])

        context.forwarder.currentConnectionLeaseID = UUID()
        context.brokerFactory.startDelayNanoseconds = 30_000_000
        let newChannelTask = Task { @MainActor in
            try await context.manager.openChannel(
                config: RelayChannelConfig(name: "new", localPort: 3001, remotePort: 9001),
                profileID: profileID
            )
        }
        for _ in 0..<20 where context.brokerFactory.brokers.count < 2 {
            await Task.yield()
        }
        #expect(context.brokerFactory.brokers.count == 2)
        context.profileRevoker.completePendingRevocation(succeeds: true)
        let newChannel = try await newChannelTask.value

        let remainingIDs = Set(context.manager.listChannels(profileID: profileID).map(\.id))
        #expect(!remainingIDs.contains(oldChannel.id))
        #expect(remainingIDs == Set([newChannel.id]))
        #expect(context.brokerFactory.brokers[0].isStopped)
        #expect(!context.brokerFactory.brokers[1].isStopped)
    }

    @Test("Close all channels affects only the selected profile")
    @MainActor func closeAllChannels() async throws {
        let context = makeManager()
        let profileA = UUID()
        let profileB = UUID()

        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileA
        )
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "db", localPort: 5432, remotePort: 9001),
            profileID: profileA
        )
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "other", localPort: 4000, remotePort: 9002),
            profileID: profileB
        )

        await context.manager.closeAllChannels(profileID: profileA)

        #expect(context.forwarder.cancelledPorts.count == 2)
        #expect(context.manager.listChannels(profileID: profileA).isEmpty)
        #expect(context.manager.listChannels(profileID: profileB).count == 1)
    }

    @Test("List channels returns only the requested profile")
    @MainActor func listChannels() async throws {
        let context = makeManager()
        let profileA = UUID()
        let profileB = UUID()

        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "a", localPort: 3000, remotePort: 9000),
            profileID: profileA
        )
        _ = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "b", localPort: 4000, remotePort: 9001),
            profileID: profileB
        )

        #expect(context.manager.listChannels(profileID: profileA).map(\.name) == ["a"])
        #expect(context.manager.listChannels(profileID: profileB).map(\.name) == ["b"])
    }

    @Test("Token rotation updates persistence and the live broker")
    @MainActor func tokenRotation() async throws {
        let context = makeManager()
        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: UUID()
        )
        let oldToken = context.manager.token(for: channel.id)

        try context.manager.rotateToken(channelID: channel.id)

        let newToken = context.manager.token(for: channel.id)
        let update = try #require(context.brokerFactory.brokers[0].authorizationUpdates.last)
        #expect(oldToken?.secret != newToken?.secret)
        #expect(update.0.secret == newToken?.secret)
        #expect(context.tokenStore.stored[channel.id]?.secret == newToken?.secret)
    }

    @Test("ACL and connection count updates reach the live topology")
    @MainActor func liveUpdates() async throws {
        let context = makeManager()
        let profileID = UUID()
        let channel = try await context.manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        let acl = RelayACL(maxConnections: 2, allowedRemoteHosts: ["127.0.0.1"])

        context.manager.updateACL(channelID: channel.id, acl: acl)
        context.brokerFactory.brokers[0].emitConnectionCount(2)

        let update = try #require(context.brokerFactory.brokers[0].authorizationUpdates.last)
        #expect(update.1 == acl)
        #expect(context.manager.listChannels(profileID: profileID)[0].acl == acl)
        #expect(context.manager.listChannels(profileID: profileID)[0].connectionCount == 2)
    }

    @Test("SSH setup failure rolls back broker, token, tunnel, and channel")
    @MainActor func forwardFailureRollsBack() async {
        let context = makeManager()
        let profileID = UUID()
        context.forwarder.shouldThrow = true

        do {
            _ = try await context.manager.openChannel(
                config: RelayChannelConfig(name: "fail", localPort: 3000, remotePort: 9000),
                profileID: profileID
            )
            Issue.record("Expected error")
        } catch {
            #expect(context.forwarder.cancelledPorts.isEmpty)
            #expect(context.brokerFactory.brokers[0].isStopped)
            #expect(context.tokenStore.stored.isEmpty)
            #expect(context.tunnelManager.listTunnels(for: profileID).isEmpty)
            #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        }
    }

    @Test("Broker startup failure never creates an SSH listener")
    @MainActor func brokerFailureRollsBack() async {
        let context = makeManager()
        let profileID = UUID()
        context.brokerFactory.shouldFailStart = true

        do {
            _ = try await context.manager.openChannel(
                config: RelayChannelConfig(name: "fail", localPort: 3000, remotePort: 9000),
                profileID: profileID
            )
            Issue.record("Expected error")
        } catch {
            #expect(context.forwarder.forwardedPorts.isEmpty)
            #expect(context.brokerFactory.brokers[0].isStopped)
            #expect(context.tokenStore.stored.isEmpty)
            #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        }
    }

    @Test("Runtime broker failure during setup rolls back before SSH exposure")
    @MainActor func runtimeBrokerFailureDuringSetupRollsBack() async {
        let context = makeManager()
        let profileID = UUID()
        context.brokerFactory.emitFailureAfterStart = true

        do {
            _ = try await context.manager.openChannel(
                config: RelayChannelConfig(name: "fail", localPort: 3000, remotePort: 9000),
                profileID: profileID
            )
            Issue.record("Expected setup failure")
        } catch {
            #expect(context.forwarder.forwardedPorts.isEmpty)
            #expect(context.brokerFactory.brokers[0].isDeactivated)
            #expect(context.brokerFactory.brokers[0].isStopped)
            #expect(context.tokenStore.stored.isEmpty)
            #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        }
    }

    @Test("Token persistence failure never starts a broker or SSH listener")
    @MainActor func tokenPersistenceFailureRollsBack() async {
        let tokenStore = RelayTestTokenStore()
        tokenStore.shouldFailSave = true
        let context = makeManager(tokenStore: tokenStore)

        do {
            _ = try await context.manager.openChannel(
                config: RelayChannelConfig(name: "fail", localPort: 3000, remotePort: 9000),
                profileID: UUID()
            )
            Issue.record("Expected error")
        } catch {
            #expect(context.forwarder.forwardedPorts.isEmpty)
            #expect(!context.brokerFactory.brokers[0].isStarted)
            #expect(context.brokerFactory.brokers[0].isStopped)
            #expect(context.tokenStore.stored.isEmpty)
        }
    }

    @Test("Cancelled channel setup rolls back before SSH exposure")
    @MainActor func cancelledSetupRollsBack() async {
        let context = makeManager()
        let profileID = UUID()
        context.brokerFactory.startDelayNanoseconds = 1_000_000_000
        let task = Task { @MainActor in
            try await context.manager.openChannel(
                config: RelayChannelConfig(name: "cancel", localPort: 3000, remotePort: 9000),
                profileID: profileID
            )
        }

        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(context.forwarder.forwardedPorts.isEmpty)
            #expect(context.brokerFactory.brokers[0].isStopped)
            #expect(context.tokenStore.stored.isEmpty)
            #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Profile generation invalidation cancels an opening before SSH exposure")
    @MainActor func generationInvalidationRollsBack() async {
        let context = makeManager()
        let profileID = UUID()
        context.brokerFactory.startDelayNanoseconds = 30_000_000
        let task = Task { @MainActor in
            try await context.manager.openChannel(
                config: RelayChannelConfig(name: "stale", localPort: 3000, remotePort: 9000),
                profileID: profileID
            )
        }

        await Task.yield()
        context.manager.invalidatePendingOpenings(profileID: profileID)

        do {
            _ = try await task.value
            Issue.record("Expected stale opening cancellation")
        } catch is CancellationError {
            #expect(context.forwarder.forwardedPorts.isEmpty)
            #expect(context.brokerFactory.brokers[0].isStopped)
            #expect(context.tokenStore.stored.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Invalidation after SSH exposure compensates the uncertain forward")
    @MainActor func postForwardInvalidationCompensates() async {
        let context = makeManager()
        let profileID = UUID()
        let gate = MockPortForwardCompletionGate()
        context.forwarder.forwardCompletionGate = gate
        let task = Task { @MainActor in
            try await context.manager.openChannel(
                config: RelayChannelConfig(
                    name: "stale",
                    localPort: 3000,
                    remotePort: 9000
                ),
                profileID: profileID
            )
        }

        for _ in 0..<200 where !gate.isWaiting {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(gate.isWaiting)
        #expect(context.forwarder.forwardedPorts.count == 1)
        context.manager.invalidatePendingOpenings(profileID: profileID)
        gate.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(context.forwarder.cancelledPorts == context.forwarder.forwardedPorts)
        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.brokerFactory.brokers[0].isStopped)
        #expect(context.tokenStore.stored.isEmpty)
    }

    @Test("A late opening quarantines the old forward without touching its replacement")
    @MainActor func lateOpeningQuarantinesOldLease() async throws {
        let context = makeManager()
        let profileID = UUID()
        let oldConnectionLeaseID = try #require(
            context.forwarder.currentConnectionLeaseID
        )
        let gate = MockPortForwardCompletionGate()
        context.forwarder.forwardCompletionGate = gate
        let task = Task { @MainActor in
            try await context.manager.openChannel(
                config: RelayChannelConfig(
                    name: "stale",
                    localPort: 3000,
                    remotePort: 9000
                ),
                profileID: profileID
            )
        }

        for _ in 0..<200 where !gate.isWaiting {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(gate.isWaiting)
        context.forwarder.currentConnectionLeaseID = UUID()
        context.manager.invalidatePendingOpenings(profileID: profileID)
        gate.resume()

        await #expect(throws: SSHMultiplexerError.notConnected) {
            _ = try await task.value
        }
        await waitForRelayCondition {
            !context.profileRevoker.connectionLeaseIDs.isEmpty
        }
        #expect(context.forwarder.cancelledPorts.isEmpty)
        #expect(context.profileRevoker.connectionLeaseIDs == [oldConnectionLeaseID])
        let retained = try #require(
            context.manager.listChannels(profileID: profileID).first
        )
        guard case .closeFailed = retained.status else {
            Issue.record("Expected closeFailed quarantine status")
            return
        }
        #expect(context.brokerFactory.brokers[0].isDeactivated)
        #expect(!context.brokerFactory.brokers[0].isStopped)
        #expect(context.tokenStore.stored[retained.id] != nil)

        context.manager.releaseChannelsAfterSessionTermination(
            profileID: profileID,
            connectionLeaseID: oldConnectionLeaseID
        )
        #expect(context.manager.listChannels(profileID: profileID).isEmpty)
        #expect(context.brokerFactory.brokers[0].isStopped)
        #expect(context.tokenStore.stored.isEmpty)
    }

    @Test("Invalid ports fail before broker or forward creation")
    @MainActor func invalidPorts() async {
        let context = makeManager()

        do {
            _ = try await context.manager.openChannel(
                config: RelayChannelConfig(name: "invalid", localPort: 0, remotePort: 9000),
                profileID: UUID()
            )
            Issue.record("Expected invalid port error")
        } catch {
            #expect(error as? RelayManagerError == .invalidPort)
            #expect(context.brokerFactory.brokers.isEmpty)
            #expect(context.forwarder.forwardedPorts.isEmpty)
        }
    }

    @Test("Blank channel names fail before broker or forward creation")
    @MainActor func invalidName() async {
        let context = makeManager()

        do {
            _ = try await context.manager.openChannel(
                config: RelayChannelConfig(name: "   ", localPort: 3000, remotePort: 9000),
                profileID: UUID()
            )
            Issue.record("Expected invalid name error")
        } catch {
            #expect(error as? RelayManagerError == .invalidName)
            #expect(context.brokerFactory.brokers.isEmpty)
            #expect(context.forwarder.forwardedPorts.isEmpty)
        }
    }

    @Test("Close and rotate for unknown channels are safe no-ops")
    @MainActor func unknownChannelNoOps() async throws {
        let context = makeManager()

        await context.manager.closeChannel(channelID: UUID())
        try context.manager.rotateToken(channelID: UUID())

        #expect(context.forwarder.cancelledPorts.isEmpty)
    }
}
