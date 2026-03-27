// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionManagerTests.swift - Tests for remote connection orchestrator.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Multiplexer

final class MockSSHMultiplexerDelegate: SSHMultiplexing, @unchecked Sendable {
    var connectCalled = false
    var disconnectCalled = false
    var isAliveResult = true
    var shouldThrowOnConnect = false
    var shouldThrowOnDisconnect = false

    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        connectCalled = true
        if shouldThrowOnConnect {
            throw SSHMultiplexerError.connectionFailed("mock failure")
        }
    }

    func disconnect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        disconnectCalled = true
        if shouldThrowOnDisconnect {
            throw SSHMultiplexerError.disconnectFailed("mock failure")
        }
    }

    func isAlive(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> Bool {
        isAliveResult
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
    ) throws {}

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {}
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
    ) throws {
        connectAttempts += 1
        if connectAttempts < failUntilAttempt {
            throw SSHMultiplexerError.connectionFailed("temporary failure #\(connectAttempts)")
        }
    }

    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool { true }
    func controlPath(for profile: RemoteConnectionProfile) -> String { profile.controlPath }
    func newSession(profile: RemoteConnectionProfile) -> String { "ssh mock" }
    func forwardPort(_ forward: RemoteConnectionProfile.PortForward, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func cancelForward(_ forward: RemoteConnectionProfile.PortForward, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
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
