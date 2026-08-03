// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionManagerTests.swift - Tests for remote connection orchestrator.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Multiplexer

final class MockSSHMultiplexerDelegate: SSHMultiplexing, @unchecked Sendable {
    var connectCalled = false
    var connectCallCount = 0
    var disconnectCalled = false
    var isAliveResult = false
    var controlMasterProcessAliveResult: Bool?
    var shouldThrowOnConnect = false
    var shouldThrowOnDisconnect = false
    var shouldThrowOnCancelForward = false
    var forwardedPorts: [RemoteConnectionProfile.PortForward] = []
    var disconnectedProfileIDs: [UUID] = []
    var exactlyDisconnectedIdentities: [SSHControlMasterIdentity] = []
    var exactForwardIdentities: [SSHControlMasterIdentity] = []
    var exactCancelIdentities: [SSHControlMasterIdentity] = []
    var exactRemoteCommandIdentities: [SSHControlMasterIdentity] = []
    var terminatedControlPaths: [String] = []
    var lifecycleEvents: [String] = []
    var proxyTransport: (any ProxyUpstreamTransport)?
    var shouldThrowOnAttestation = false
    var shouldThrowOnVerification = false
    var attestation = SSHControlSocketAttestation(
        device: 7,
        inode: 11,
        peerProcessID: 12_345
    )
    private(set) var openedProxyTargets: [ProxyTarget] = []
    private(set) var openedProxyIdentities: [SSHControlMasterIdentity] = []
    private(set) var attestedIdentities: [SSHControlMasterIdentity] = []
    private(set) var verifiedIdentities: [SSHControlMasterIdentity] = []
    var executeRemoteCommandsWithProcessExecutor = false
    var forwardAsyncError: (any Error)?
    var connectAsyncHandler: ((RemoteConnectionProfile) async throws -> SSHControlMasterIdentity)?

    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity {
        connectCalled = true
        connectCallCount += 1
        lifecycleEvents.append("connect")
        if shouldThrowOnConnect {
            throw SSHMultiplexerError.connectionFailed("mock failure")
        }
        return SSHControlMasterIdentity(
            processID: 12_345,
            controlPath: profile.controlPath,
            supervisorID: UUID()
        )
    }

    func connectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> SSHControlMasterIdentity {
        _ = executor
        if let connectAsyncHandler {
            return try await connectAsyncHandler(profile)
        }
        return try connect(profile: profile, executor: executor)
    }

    func disconnect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        disconnectCalled = true
        disconnectedProfileIDs.append(profile.id)
        lifecycleEvents.append("disconnect")
        if shouldThrowOnDisconnect {
            throw SSHMultiplexerError.disconnectFailed("mock failure")
        }
    }

    func disconnectAsync(
        profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        exactlyDisconnectedIdentities.append(expectedControlMaster)
        try disconnect(profile: profile, executor: executor)
    }

    func isAlive(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> Bool {
        lifecycleEvents.append("check")
        return isAliveResult
    }

    func isControlMasterProcessAlive(_ identity: SSHControlMasterIdentity) -> Bool {
        _ = identity
        lifecycleEvents.append("check")
        return controlMasterProcessAliveResult ?? isAliveResult
    }

    func terminateControlMaster(_ identity: SSHControlMasterIdentity) {
        terminatedControlPaths.append(identity.controlPath)
        lifecycleEvents.append("terminate")
    }

    func controlPath(for profile: RemoteConnectionProfile) -> String {
        profile.controlPath
    }

    func newSession(profile: RemoteConnectionProfile) -> String {
        "ssh -o ControlPath=mock \(profile.user ?? "")@\(profile.host)"
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        forwardedPorts.append(forward)
        lifecycleEvents.append("forward")
    }

    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        _ = profile
        _ = executor
        forwardedPorts.append(forward)
        exactForwardIdentities.append(expectedControlMaster)
        lifecycleEvents.append("forward")
        if let forwardAsyncError { throw forwardAsyncError }
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        lifecycleEvents.append("cancel")
        if shouldThrowOnCancelForward {
            throw SSHMultiplexerError.forwardFailed("mock cancellation failure")
        }
    }

    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        _ = forward
        _ = profile
        _ = executor
        exactCancelIdentities.append(expectedControlMaster)
        lifecycleEvents.append("cancel")
        if shouldThrowOnCancelForward {
            throw SSHMultiplexerError.forwardFailed("mock cancellation failure")
        }
    }

    func openDirectTCPTransport(
        to target: ProxyTarget,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity
    ) throws -> any ProxyUpstreamTransport {
        _ = profile
        guard let proxyTransport else {
            throw ProxyUpstreamTransportError.unavailable
        }
        openedProxyTargets.append(target)
        openedProxyIdentities.append(expectedControlMaster)
        return proxyTransport
    }

    func attestControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity
    ) throws -> SSHControlSocketAttestation {
        attestedIdentities.append(expectedControlMaster)
        if shouldThrowOnAttestation { throw SSHMultiplexerError.notConnected }
        return attestation
    }

    func verifyControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity,
        attestation: SSHControlSocketAttestation
    ) throws {
        verifiedIdentities.append(expectedControlMaster)
        guard !shouldThrowOnVerification,
              attestation == self.attestation,
              attestation.peerProcessID == expectedControlMaster.processID else {
            throw SSHMultiplexerError.notConnected
        }
    }

    var remoteCommandResults: [String: ProcessResult] = [:]
    var afterRemoteCommand: (() -> Void)?

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        if executeRemoteCommandsWithProcessExecutor {
            let result = try await executor.executeAsync(
                command: "/bin/sh",
                arguments: ["-c", command]
            )
            afterRemoteCommand?()
            return result
        }
        let result = remoteCommandResults[command]
            ?? ProcessResult(exitCode: 0, stdout: "", stderr: "")
        afterRemoteCommand?()
        return result
    }

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        exactRemoteCommandIdentities.append(expectedControlMaster)
        return try await executeRemoteCommand(command, on: profile, executor: executor)
    }
}

private actor OrderedConnectCompletionGate {
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<SSHControlMasterIdentity, any Error>] = [:]

    var pendingCalls: Set<Int> {
        Set(continuations.keys)
    }

    func connect(profile: RemoteConnectionProfile) async throws -> SSHControlMasterIdentity {
        _ = profile
        nextCall += 1
        let call = nextCall
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func resume(call: Int, identity: SSHControlMasterIdentity) {
        continuations.removeValue(forKey: call)?.resume(returning: identity)
    }
}

private final class RemoteManagerTestProxyTransport: ProxyUpstreamTransport, @unchecked Sendable {
    let processIdentifier: Int32 = 73_001
    var isRunning = true
    let diagnosticOutput = ""
    private(set) var wasCancelled = false

    func waitUntilReady() async throws {}

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

private final class DaemonCancellationSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var startedStorage = false
    private var cancellationObservedStorage = false

    var started: Bool { lock.withLock { startedStorage } }
    var cancellationObserved: Bool { lock.withLock { cancellationObservedStorage } }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = sftpCommand
        _ = authorization
        lock.withLock { startedStorage = true }
        for _ in 0..<6_000 {
            if Task.isCancelled {
                lock.withLock { cancellationObservedStorage = true }
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return ""
    }

    func executeRecovery(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = sftpCommand
        _ = authorization
        return ""
    }
}

private final class DaemonRecordingSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var commandsStorage: [String] = []

    var commands: [String] { lock.withLock { commandsStorage } }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = authorization
        lock.withLock { commandsStorage.append(sftpCommand) }
        return ""
    }
}

// MARK: - Tracking Multiplexer (for reconnect tests)

/// Multiplexer mock that fails the first N connect attempts, then succeeds.
final class TrackingSSHMultiplexer: SSHMultiplexing, @unchecked Sendable {
    var connectAttempts = 0
    private let failUntilAttempt: Int

    init(failUntilAttempt: Int) {
        self.failUntilAttempt = failUntilAttempt
    }

    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity {
        connectAttempts += 1
        if connectAttempts < failUntilAttempt {
            throw SSHMultiplexerError.connectionFailed("temporary failure #\(connectAttempts)")
        }
        return SSHControlMasterIdentity(
            processID: 23_456,
            controlPath: profile.controlPath
        )
    }

    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool { true }
    func isControlMasterProcessAlive(_ identity: SSHControlMasterIdentity) -> Bool { false }
    func terminateControlMaster(_ identity: SSHControlMasterIdentity) {}
    func controlPath(for profile: RemoteConnectionProfile) -> String { profile.controlPath }
    func newSession(profile: RemoteConnectionProfile) -> String { "ssh mock" }
    func forwardPort(_ forward: RemoteConnectionProfile.PortForward, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func cancelForward(_ forward: RemoteConnectionProfile.PortForward, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func executeRemoteCommand(_ command: String, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

// MARK: - Mock Profile Store

final class MockRemoteProfileStore: RemoteProfileStoring, @unchecked Sendable {
    var profiles: [RemoteConnectionProfile] = []

    func loadAll() throws -> [RemoteConnectionProfile] {
        profiles
    }

    func save(_ profile: RemoteConnectionProfile) throws {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }

    func delete(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw RemoteProfileStoreError.profileNotFound
        }
        profiles.removeAll { $0.id == id }
    }

    func findByName(_ name: String) throws -> RemoteConnectionProfile? {
        profiles.first { $0.name == name }
    }

    func findByGroup(_ group: String) throws -> [RemoteConnectionProfile] {
        profiles.filter { $0.group == group }
    }
}

private actor RemoteReconnectDelayGate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func isWaiting() -> Bool {
        continuation != nil
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum RemoteCommandFixtureError: Error {
    case processDidNotStart
}

private func waitForRemoteCommandMarker(at url: URL) async throws {
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw RemoteCommandFixtureError.processDidNotStart
}

// MARK: - Remote Connection Manager Tests

@Suite("RemoteConnectionManager")
struct RemoteConnectionManagerTests {

    @Test @MainActor func initialStateIsEmpty() {
        let manager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )

        #expect(manager.connections.isEmpty)
    }

    @Test @MainActor func connectTransitionsToConnected() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")

        await manager.connect(profile: profile)

        #expect(multiplexer.connectCalled)
        #expect(manager.connections[profile.id] == .connected(latencyMs: nil))
    }

    @Test @MainActor func duplicateConnectPreservesControlMasterLease() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let originalLeaseID = try #require(manager.connectionLeaseID(for: profile.id))

        await manager.connect(profile: profile)

        #expect(multiplexer.connectCallCount == 1)
        #expect(manager.connectionLeaseID(for: profile.id) == originalLeaseID)
        #expect(manager.connections[profile.id] == .connected(latencyMs: nil))
    }

    @Test @MainActor func connectTransitionsToFailedOnError() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.shouldThrowOnConnect = true
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(
            name: "dev", host: "unreachable.com", autoReconnect: false
        )

        await manager.connect(profile: profile)

        if case .failed = manager.connections[profile.id] {
            // Expected state.
        } else {
            Issue.record("Expected .failed state but got \(String(describing: manager.connections[profile.id]))")
        }
    }

    @Test @MainActor func disconnectClearsConnectionState() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        await manager.disconnect(profileID: profile.id)

        #expect(multiplexer.disconnectCalled)
        #expect(multiplexer.lifecycleEvents.contains("check"))
        #expect(manager.connections[profile.id] == .disconnected)
    }

    @Test @MainActor func disconnectHandlesUnknownProfile() async {
        let manager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )

        await manager.disconnect(profileID: UUID())

        #expect(manager.connections.isEmpty)
    }

    @Test @MainActor func healthCheckReportsConnectedWhenAlive() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.isAliveResult = true
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        let alive = await manager.healthCheck(profileID: profile.id)

        #expect(alive == true)
    }

    @Test @MainActor func healthCheckReportsDeadWhenNotAlive() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        multiplexer.isAliveResult = false
        let alive = await manager.healthCheck(profileID: profile.id)

        #expect(alive == false)
    }

    @Test @MainActor func healthCheckReturnsFalseForUnknownProfile() async {
        let manager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )

        let alive = await manager.healthCheck(profileID: UUID())

        #expect(alive == false)
    }

    @Test @MainActor func reconnectAttemptsConnectionAgain() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        multiplexer.connectCalled = false
        await manager.reconnect(profileID: profile.id)

        #expect(multiplexer.connectCalled)
        #expect(manager.connections[profile.id] == .connected(latencyMs: nil))
    }

    @Test @MainActor func forwardingRequiresCurrentConnectedState() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080,
            remotePort: 80,
            remoteHost: "127.0.0.1"
        )
        await manager.connect(profile: profile)

        try await manager.forwardPort(forward, for: profile.id)
        #expect(multiplexer.forwardedPorts == [forward])
        try await manager.cancelForward(forward, for: profile.id)
        #expect(multiplexer.lifecycleEvents.contains("cancel"))

        await manager.disconnect(profileID: profile.id)
        do {
            try await manager.forwardPort(forward, for: profile.id)
            Issue.record("Expected disconnected forwarding to fail")
        } catch {
            #expect(error as? SSHMultiplexerError == .connectionFailed(
                "No active connection for profile"
            ))
        }
        do {
            try await manager.cancelForward(forward, for: profile.id)
            Issue.record("Expected disconnected cancellation to fail")
        } catch {
            #expect(error as? SSHMultiplexerError == .connectionFailed(
                "No active connection for profile"
            ))
        }
    }

    @Test @MainActor func staleLeaseCannotControlReplacementForwards() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8_080,
            remotePort: 80,
            remoteHost: "127.0.0.1"
        )
        await manager.connect(profile: profile)
        let oldLeaseID = try #require(manager.connectionLeaseID(for: profile.id))
        await manager.disconnect(profileID: profile.id)
        await manager.connect(profile: profile)
        let replacementLeaseID = try #require(manager.connectionLeaseID(for: profile.id))
        #expect(replacementLeaseID != oldLeaseID)

        let forwardCount = multiplexer.forwardedPorts.count
        await #expect(throws: SSHMultiplexerError.notConnected) {
            try await manager.forwardPort(
                forward,
                for: profile.id,
                expectedConnectionLeaseID: oldLeaseID
            )
        }
        await #expect(throws: SSHMultiplexerError.notConnected) {
            try await manager.cancelForward(
                forward,
                for: profile.id,
                expectedConnectionLeaseID: oldLeaseID
            )
        }
        #expect(multiplexer.forwardedPorts.count == forwardCount)
    }

    @Test @MainActor func sftpClientRequiresAnAttestedConnectedLease() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "server.com",
            user: "deploy"
        )
        let executor = MockSFTPExecutor()

        #expect(throws: SFTPClientError.notConnected) {
            _ = try manager.makeSFTPClient(profileID: profile.id, executor: executor)
        }

        await manager.connect(profile: profile)
        let client = try manager.makeSFTPClient(profileID: profile.id, executor: executor)
        _ = try client.listDirectory(path: ".")

        #expect(multiplexer.attestedIdentities.count == 1)
        #expect(multiplexer.verifiedIdentities.count == 2)
        #expect(executor.executedCommands.count == 1)
    }

    @Test @MainActor func disconnectRevokesEveryIssuedSFTPClient() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let executor = MockSFTPExecutor()
        await manager.connect(profile: profile)
        let client = try manager.makeSFTPClient(profileID: profile.id, executor: executor)

        await manager.disconnect(profileID: profile.id)

        #expect(throws: SFTPClientError.notConnected) {
            _ = try client.listDirectory(path: ".")
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test @MainActor func reconnectRejectsClientFromPreviousLease() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let staleExecutor = MockSFTPExecutor()
        await manager.connect(profile: profile)
        let staleClient = try manager.makeSFTPClient(
            profileID: profile.id,
            executor: staleExecutor
        )

        await manager.reconnect(profileID: profile.id)
        let currentExecutor = MockSFTPExecutor()
        let currentClient = try manager.makeSFTPClient(
            profileID: profile.id,
            executor: currentExecutor
        )

        #expect(throws: SFTPClientError.notConnected) {
            _ = try staleClient.listDirectory(path: ".")
        }
        _ = try currentClient.listDirectory(path: ".")
        #expect(staleExecutor.executedCommands.isEmpty)
        #expect(currentExecutor.executedCommands.count == 1)
    }

    @Test @MainActor func failedControlSocketVerificationRefusesSFTPClient() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        multiplexer.shouldThrowOnVerification = true

        #expect(throws: SFTPClientError.notConnected) {
            _ = try manager.makeSFTPClient(
                profileID: profile.id,
                executor: MockSFTPExecutor()
            )
        }
    }

    @Test @MainActor func remoteCommandIsAttestedBeforeAndAfterExecution() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.remoteCommandResults["printf ok"] = ProcessResult(
            exitCode: 0,
            stdout: "ok",
            stderr: ""
        )
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        let output = try await manager.executeRemoteCommand("printf ok", profileID: profile.id)

        #expect(output == "ok")
        #expect(multiplexer.attestedIdentities.count == 1)
        #expect(multiplexer.verifiedIdentities.count == 1)
        #expect(multiplexer.attestedIdentities == multiplexer.verifiedIdentities)
    }

    @Test @MainActor func completedRemoteCommandSurvivesFailedPostVerification() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        multiplexer.shouldThrowOnVerification = true

        let output = try await manager.executeRemoteCommand(
            "printf ok",
            profileID: profile.id
        )

        #expect(output.isEmpty)
        #expect(manager.connections[profile.id] == .disconnected)
    }

    @Test @MainActor func completedRemoteMutationSurvivesPostExecutionConnectionLoss() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.remoteCommandResults["perform mutation"] = ProcessResult(
            exitCode: 0,
            stdout: "committed",
            stderr: ""
        )
        multiplexer.afterRemoteCommand = {
            multiplexer.shouldThrowOnVerification = true
        }
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        let output = try await manager.executeRemoteCommand(
            "perform mutation",
            profileID: profile.id
        )

        #expect(output == "committed")
        #expect(manager.connections[profile.id] == .disconnected)
    }

    @Test @MainActor func remoteCommandTreatsEveryNonzeroExitAsFailure() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.remoteCommandResults["false"] = ProcessResult(
            exitCode: 7,
            stdout: "",
            stderr: ""
        )
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)

        await #expect(
            throws: SSHMultiplexerError.connectionFailed("Remote command exited with code 7")
        ) {
            _ = try await manager.executeRemoteCommand("false", profileID: profile.id)
        }
    }

    @Test @MainActor func disconnectRevokesAnInFlightRemoteCommand() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.executeRemoteCommandsWithProcessExecutor = true
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: SystemProcessExecutor(asyncTimeoutSeconds: 2)
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-remote-command-revocation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("started")
        let command = Task {
            try await manager.executeRemoteCommand(
                "printf started > '\(marker.path)'; /bin/sleep 30",
                profileID: profile.id
            )
        }
        try await waitForRemoteCommandMarker(at: marker)

        await manager.disconnect(profileID: profile.id)

        await #expect(throws: SSHMultiplexerError.notConnected) {
            try await command.value
        }
    }

    @Test @MainActor func daemonUploadCancellationStopsItsSFTPWorker() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let sftpExecutor = DaemonCancellationSFTPExecutor()
        let adapter = DaemonDeployAdapter(
            connectionManager: manager,
            sftpExecutor: sftpExecutor
        )
        let localFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-daemon-upload-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: localFile) }
        try Data("payload".utf8).write(to: localFile)
        let upload = Task {
            try await adapter.uploadFile(
                localPath: localFile.path,
                remotePath: "/tmp/cocxyd",
                profileID: profile.id
            )
        }
        for _ in 0..<200 {
            if sftpExecutor.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(sftpExecutor.started)

        upload.cancel()

        await #expect(throws: CancellationError.self) {
            try await upload.value
        }
        #expect(sftpExecutor.cancellationObserved)
    }

    @Test @MainActor func daemonUploadExplicitlyReplacesItsManagedRemoteScript() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let sftpExecutor = DaemonRecordingSFTPExecutor()
        let adapter = DaemonDeployAdapter(
            connectionManager: manager,
            sftpExecutor: sftpExecutor
        )
        let localFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-daemon-upload-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: localFile) }
        try Data("payload".utf8).write(to: localFile)

        try await adapter.uploadFile(
            localPath: localFile.path,
            remotePath: DaemonDeployer.remotePath,
            profileID: profile.id
        )

        #expect(sftpExecutor.commands.count == 2)
        #expect(sftpExecutor.commands.first?.hasPrefix("put ") == true)
        #expect(sftpExecutor.commands.last?.hasPrefix("rename ") == true)
        #expect(sftpExecutor.commands.last?.contains("rename -l ") == false)
        #expect(sftpExecutor.commands.last?.hasSuffix(" '~/.cocxy/cocxyd.sh'") == true)
    }

    @Test @MainActor func proxyTransportUsesExactConnectedLeaseAndMasterIdentity() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let transport = RemoteManagerTestProxyTransport()
        multiplexer.proxyTransport = transport
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let leaseID = try #require(manager.connectionLeaseID(for: profile.id))
        let target = try ProxyTarget(host: "internal.example", port: 443)

        let opened = try manager.openProxyTransport(
            to: target,
            for: profile.id,
            expectedConnectionLeaseID: leaseID
        )

        #expect(opened === transport)
        #expect(multiplexer.openedProxyTargets == [target])
        #expect(multiplexer.openedProxyIdentities.count == 1)
        #expect(multiplexer.openedProxyIdentities[0].controlPath == profile.controlPath)

        #expect(throws: SSHMultiplexerError.self) {
            try manager.openProxyTransport(
                to: target,
                for: profile.id,
                expectedConnectionLeaseID: UUID()
            )
        }
        #expect(multiplexer.openedProxyTargets == [target])
        #expect(!transport.wasCancelled)
    }

    @Test @MainActor func brokerFailureRevocationDisconnectsTheProfile() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.isAliveResult = false
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let connectionLeaseID = try #require(manager.connectionLeaseID(for: profile.id))

        let terminated = await manager.revokeForwardingSession(
            profileID: profile.id,
            expectedLeaseID: connectionLeaseID
        )

        #expect(multiplexer.disconnectCalled)
        #expect(terminated)
        #expect(manager.connections[profile.id] == .disconnected)
    }

    @Test @MainActor func staleLeaseCannotRevokeReconnectedProfile() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let staleLeaseID = try #require(manager.connectionLeaseID(for: profile.id))
        await manager.disconnect(profileID: profile.id)
        await manager.connect(profile: profile)
        let currentLeaseID = try #require(manager.connectionLeaseID(for: profile.id))
        multiplexer.disconnectCalled = false

        let terminated = await manager.revokeForwardingSession(
            profileID: profile.id,
            expectedLeaseID: staleLeaseID
        )

        #expect(!terminated)
        #expect(!multiplexer.disconnectCalled)
        #expect(currentLeaseID != staleLeaseID)
        #expect(manager.connectionLeaseID(for: profile.id) == currentLeaseID)
        #expect(manager.connections[profile.id] == .connected(latencyMs: nil))
    }

    @Test @MainActor func disconnectCancelsRelayBeforeControlMasterExit() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let tunnelManager = SSHTunnelManager()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor()
        )
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: manager
        )
        manager.relayManager = relayManager
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        _ = try await relayManager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profile.id
        )

        await manager.disconnect(profileID: profile.id)

        let cancelIndex = try #require(multiplexer.lifecycleEvents.firstIndex(of: "cancel"))
        let disconnectIndex = try #require(
            multiplexer.lifecycleEvents.lastIndex(of: "disconnect")
        )
        #expect(cancelIndex < disconnectIndex)
        #expect(relayManager.listChannels(profileID: profile.id).isEmpty)
    }

    @Test @MainActor func successfulDisconnectReleasesQuarantinedRelay() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.isAliveResult = false
        let tunnelManager = SSHTunnelManager()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor()
        )
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: manager
        )
        manager.relayManager = relayManager
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        _ = try await relayManager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profile.id
        )
        multiplexer.shouldThrowOnCancelForward = true

        await manager.disconnect(profileID: profile.id)

        #expect(multiplexer.disconnectCalled)
        #expect(relayManager.listChannels(profileID: profile.id).isEmpty)
        #expect(tunnelManager.listTunnels(for: profile.id).isEmpty)
    }

    @Test @MainActor func exitAcknowledgementDoesNotReleaseLiveSessionQuarantine() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.isAliveResult = false
        multiplexer.controlMasterProcessAliveResult = true
        let tunnelManager = SSHTunnelManager()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor(),
            delaySleep: Self.instantDelay
        )
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: manager
        )
        manager.relayManager = relayManager
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        _ = try await relayManager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profile.id
        )
        multiplexer.shouldThrowOnCancelForward = true

        await manager.disconnect(profileID: profile.id)

        #expect(multiplexer.disconnectCalled)
        #expect(multiplexer.lifecycleEvents.filter { $0 == "check" }.count == 5)
        #expect(manager.connectionLeaseID(for: profile.id) != nil)
        let retained = try #require(relayManager.listChannels(profileID: profile.id).first)
        guard case .closeFailed = retained.status else {
            Issue.record("Expected quarantined close failure")
            return
        }
    }

    @Test @MainActor func daemonTransportUsesRemoteLoopbackOverExactSSHLease() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let transport = RemoteManagerTestProxyTransport()
        multiplexer.proxyTransport = transport
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        let leaseID = try #require(manager.connectionLeaseID(for: profile.id))
        let expectedTarget = try ProxyTarget(host: "127.0.0.1", port: 45_678)

        let binding = try manager.openDaemonTransport(
            remotePort: 45_678,
            profileID: profile.id,
            expectedConnectionLeaseID: leaseID
        )

        #expect(binding.profileID == profile.id)
        #expect(binding.connectionLeaseID == leaseID)
        #expect(binding.transport === transport)
        #expect(multiplexer.openedProxyTargets == [expectedTarget])
        #expect(multiplexer.openedProxyIdentities.count == 1)
        #expect(multiplexer.openedProxyIdentities[0].controlPath == profile.controlPath)

        #expect(throws: SSHMultiplexerError.self) {
            try manager.openDaemonTransport(
                remotePort: 45_678,
                profileID: profile.id,
                expectedConnectionLeaseID: UUID()
            )
        }
    }

    @Test @MainActor func applicationShutdownReleasesQuarantineAfterProcessExit() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.controlMasterProcessAliveResult = false
        let tunnelManager = SSHTunnelManager()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor()
        )
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: manager
        )
        manager.relayManager = relayManager
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        await manager.connect(profile: profile)
        _ = try await relayManager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profile.id
        )
        multiplexer.shouldThrowOnCancelForward = true

        manager.shutdownForApplicationTermination()

        #expect(multiplexer.disconnectedProfileIDs.isEmpty)
        #expect(multiplexer.terminatedControlPaths == [profile.controlPath])
        #expect(manager.connections[profile.id] == .disconnected)
        #expect(manager.connectionLeaseID(for: profile.id) == nil)
        #expect(relayManager.listChannels(profileID: profile.id).isEmpty)
        #expect(tunnelManager.listTunnels(for: profile.id).isEmpty)
    }

    @Test @MainActor func applicationShutdownSkipsProfilesWithoutActiveLease() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let activeProfile = RemoteConnectionProfile(
            name: "active",
            host: "active.example",
            autoReconnect: false
        )
        await manager.connect(profile: activeProfile)
        let failedProfile = RemoteConnectionProfile(
            name: "failed",
            host: "failed.example",
            autoReconnect: false
        )
        multiplexer.shouldThrowOnConnect = true
        await manager.connect(profile: failedProfile)
        multiplexer.shouldThrowOnConnect = false

        manager.shutdownForApplicationTermination()

        #expect(multiplexer.disconnectedProfileIDs.isEmpty)
        #expect(multiplexer.terminatedControlPaths == [activeProfile.controlPath])
        #expect(manager.connections[activeProfile.id] == .disconnected)
        #expect(manager.connections[failedProfile.id] == .disconnected)
    }

    @Test @MainActor func applicationShutdownTerminatesAllPipesWithoutControlCommands() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.controlMasterProcessAliveResult = false
        let tunnelManager = SSHTunnelManager()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor()
        )
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: manager
        )
        manager.relayManager = relayManager
        let profiles = [
            RemoteConnectionProfile(name: "first", host: "first.example"),
            RemoteConnectionProfile(name: "second", host: "second.example"),
        ]
        for (index, profile) in profiles.enumerated() {
            await manager.connect(profile: profile)
            _ = try await relayManager.openChannel(
                config: RelayChannelConfig(
                    name: "relay-\(index)",
                    localPort: 3_000 + index,
                    remotePort: 9_000 + index
                ),
                profileID: profile.id
            )
        }
        multiplexer.lifecycleEvents.removeAll()

        manager.shutdownForApplicationTermination()

        #expect(Set(multiplexer.terminatedControlPaths) == Set(profiles.map(\.controlPath)))
        #expect(!multiplexer.lifecycleEvents.contains("disconnect"))
        #expect(!multiplexer.lifecycleEvents.contains("cancel"))
        #expect(profiles.allSatisfy { relayManager.listChannels(profileID: $0.id).isEmpty })
        #expect(profiles.allSatisfy { manager.connectionLeaseID(for: $0.id) == nil })
    }

    // MARK: - Auto-Reconnect

    /// No-op delay for tests to avoid real waiting during reconnect backoff.
    private static let instantDelay: @Sendable (UInt64) async throws -> Void = { _ in }

    @Test @MainActor func autoReconnectRetriesOnFailure() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.shouldThrowOnConnect = true
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor(),
            delaySleep: Self.instantDelay
        )
        let profile = RemoteConnectionProfile(
            name: "dev", host: "flaky.com", autoReconnect: true
        )

        await manager.connect(profile: profile)

        // After all reconnect attempts exhausted, should end in .failed.
        if case .failed = manager.connections[profile.id] {
            // Expected.
        } else {
            Issue.record("Expected .failed state after max reconnect attempts, got \(String(describing: manager.connections[profile.id]))")
        }
    }

    @Test @MainActor func autoReconnectSucceedsOnRetry() async {
        // Fail the first 2 calls (initial + first retry), succeed on third.
        let trackingMultiplexer = TrackingSSHMultiplexer(failUntilAttempt: 3)

        let manager = RemoteConnectionManager(
            multiplexer: trackingMultiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor(),
            delaySleep: Self.instantDelay
        )
        let profile = RemoteConnectionProfile(
            name: "dev", host: "flaky.com", autoReconnect: true
        )

        await manager.connect(profile: profile)

        #expect(manager.connections[profile.id] == .connected(latencyMs: nil))
        #expect(trackingMultiplexer.connectAttempts >= 3)
    }

    @Test @MainActor func disconnectInvalidatesPendingAutoReconnect() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.shouldThrowOnConnect = true
        let gate = RemoteReconnectDelayGate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor(),
            delaySleep: { _ in try await gate.wait() }
        )
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "flaky.com",
            autoReconnect: true
        )
        let connectTask = Task { @MainActor in
            await manager.connect(profile: profile)
        }
        for _ in 0..<50 {
            if await gate.isWaiting() { break }
            await Task.yield()
        }
        #expect(await gate.isWaiting())

        await manager.disconnect(profileID: profile.id)
        await gate.resume()
        await connectTask.value

        #expect(multiplexer.connectCallCount == 1)
        #expect(manager.connections[profile.id] == .disconnected)
        #expect(manager.connectionLeaseID(for: profile.id) == nil)
    }

    @Test @MainActor func noAutoReconnectWhenDisabled() async {
        let multiplexer = MockSSHMultiplexerDelegate()
        multiplexer.shouldThrowOnConnect = true
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor(),
            delaySleep: Self.instantDelay
        )
        let profile = RemoteConnectionProfile(
            name: "dev", host: "down.com", autoReconnect: false
        )

        await manager.connect(profile: profile)

        // Should fail immediately without reconnect attempts.
        if case .failed = manager.connections[profile.id] {
            // Expected.
        } else {
            Issue.record("Expected .failed state without reconnect, got \(String(describing: manager.connections[profile.id]))")
        }
    }

    // MARK: - Exponential Backoff

    @Test func backoffDelayCalculation() {
        let delays = (0..<6).map { attempt in
            RemoteConnectionManager.backoffDelay(attempt: attempt)
        }

        #expect(delays[0] == 1.0)
        #expect(delays[1] == 2.0)
        #expect(delays[2] == 4.0)
        #expect(delays[3] == 8.0)
        #expect(delays[4] == 16.0)
        #expect(delays[5] == 30.0) // Capped at max.
    }

    @Test func backoffDelayNeverExceedsMax() {
        let delay = RemoteConnectionManager.backoffDelay(attempt: 100)
        #expect(delay == 30.0)
    }

    // MARK: - Connection State Equatable

    @Test func connectionStateEquatable() {
        let state1 = RemoteConnectionManager.ConnectionState.connected(latencyMs: 42)
        let state2 = RemoteConnectionManager.ConnectionState.connected(latencyMs: 42)
        let state3 = RemoteConnectionManager.ConnectionState.connected(latencyMs: 99)

        #expect(state1 == state2)
        #expect(state1 != state3)
    }

    @Test func connectionStateDisconnectedEquatable() {
        let state1 = RemoteConnectionManager.ConnectionState.disconnected
        let state2 = RemoteConnectionManager.ConnectionState.disconnected
        let state3 = RemoteConnectionManager.ConnectionState.connecting

        #expect(state1 == state2)
        #expect(state1 != state3)
    }

    @Test func connectionStateFailedEquatable() {
        let state1 = RemoteConnectionManager.ConnectionState.failed("timeout")
        let state2 = RemoteConnectionManager.ConnectionState.failed("timeout")
        let state3 = RemoteConnectionManager.ConnectionState.failed("refused")

        #expect(state1 == state2)
        #expect(state1 != state3)
    }
}
