// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionManager.swift - Orchestrates SSH connections, tunnels and profiles.

import Foundation

// MARK: - Remote Connection Manager

/// Orchestrates the full lifecycle of remote SSH connections.
///
/// Combines `SSHMultiplexer` for connection management, `SSHTunnelManager`
/// for port forward tracking, and `RemoteProfileStore` for persistence.
///
/// ## Connection Flow
///
/// 1. `connect(profile:)` transitions to `.connecting`, starts ControlMaster.
/// 2. On success, transitions to `.connected`. On failure, transitions to `.failed`.
/// 3. If `autoReconnect` is enabled, failed connections trigger automatic
///    retry with exponential backoff (1s, 2s, 4s, 8s, max 30s, up to 5 attempts).
/// 4. `healthCheck(profileID:)` verifies the master process is still alive.
/// 5. `disconnect(profileID:)` terminates the master and cleans up tunnels.
@MainActor
final class RemoteConnectionManager: ObservableObject {

    // MARK: - Connection State

    /// Represents the current state of a remote connection.
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(latencyMs: Int?)
        case reconnecting(attempt: Int)
        case failed(String)
    }

    // MARK: - Constants

    /// Maximum number of automatic reconnection attempts.
    static let maxReconnectAttempts = 5

    /// Maximum delay between reconnection attempts (in seconds).
    static let maxBackoffDelay: TimeInterval = 30.0

    // MARK: - Published State

    /// Current connection state for each profile, keyed by profile ID.
    @Published private(set) var connections: [UUID: ConnectionState] = [:]

    // MARK: - Dependencies

    private let multiplexer: any SSHMultiplexing
    private let profileStore: any RemoteProfileStoring
    private let tunnelManager: SSHTunnelManager
    private let executor: any ProcessExecutor

    /// Async delay function for backoff waits. Injected for testability.
    private let delaySleep: @Sendable (UInt64) async throws -> Void

    /// Profiles that have been connected (kept in memory for reconnect/health check).
    private var knownProfiles: [UUID: RemoteConnectionProfile] = [:]

    // MARK: - Initialization

    /// Creates a connection manager with injected dependencies.
    ///
    /// - Parameters:
    ///   - multiplexer: SSH ControlMaster manager.
    ///   - profileStore: Persistent profile storage.
    ///   - tunnelManager: Active tunnel tracker.
    ///   - executor: Process executor for SSH commands.
    ///   - delaySleep: Async delay function. Defaults to `Task.sleep(nanoseconds:)`.
    ///     Inject a no-op closure in tests to avoid real waiting.
    init(
        multiplexer: any SSHMultiplexing,
        profileStore: any RemoteProfileStoring,
        tunnelManager: SSHTunnelManager,
        executor: any ProcessExecutor,
        delaySleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.multiplexer = multiplexer
        self.profileStore = profileStore
        self.tunnelManager = tunnelManager
        self.executor = executor
        self.delaySleep = delaySleep
    }

    // MARK: - Connect

    /// Establishes an SSH connection for the given profile.
    ///
    /// Transitions through `.connecting` -> `.connected` or `.failed`.
    /// When `profile.autoReconnect` is enabled, a failed initial connection
    /// triggers automatic retry with exponential backoff (1s, 2s, 4s, 8s,
    /// capped at 30s) for up to 5 attempts. Each retry emits a
    /// `.reconnecting(attempt:)` state so the UI can show progress.
    func connect(profile: RemoteConnectionProfile) async {
        knownProfiles[profile.id] = profile
        connections[profile.id] = .connecting

        do {
            try multiplexer.connect(profile: profile, executor: executor)
            connections[profile.id] = .connected(latencyMs: nil)
            return
        } catch {
            let message = errorMessage(from: error)

            guard profile.autoReconnect else {
                connections[profile.id] = .failed(message)
                return
            }

            // Auto-reconnect with exponential backoff.
            var lastErrorMessage = message
            for attempt in 1...Self.maxReconnectAttempts {
                connections[profile.id] = .reconnecting(attempt: attempt)

                let delayNanoseconds = UInt64(
                    Self.backoffDelay(attempt: attempt - 1) * 1_000_000_000
                )
                try? await delaySleep(delayNanoseconds)

                do {
                    try multiplexer.connect(profile: profile, executor: executor)
                    connections[profile.id] = .connected(latencyMs: nil)
                    return
                } catch {
                    lastErrorMessage = errorMessage(from: error)
                }
            }

            connections[profile.id] = .failed(lastErrorMessage)
        }
    }

    // MARK: - Error Formatting

    /// Extracts a readable message from a connection error.
    private func errorMessage(from error: any Error) -> String {
        (error as? SSHMultiplexerError)
            .map { "\($0)" } ?? error.localizedDescription
    }

    // MARK: - Disconnect

    /// Terminates the SSH connection for the given profile.
    ///
    /// Removes all associated tunnels and resets the connection state.
    func disconnect(profileID: UUID) async {
        guard let profile = knownProfiles[profileID] else { return }

        do {
            try multiplexer.disconnect(profile: profile, executor: executor)
        } catch {
            // Best-effort: even if disconnect fails, clean up local state.
        }

        tunnelManager.removeAllTunnels(for: profileID)
        connections[profileID] = .disconnected
    }

    // MARK: - Reconnect

    /// Attempts to re-establish the connection for a known profile.
    ///
    /// Useful after a transient network failure when the user manually
    /// triggers a reconnection.
    func reconnect(profileID: UUID) async {
        guard let profile = knownProfiles[profileID] else { return }
        await connect(profile: profile)
    }

    // MARK: - Health Check

    /// Verifies that the SSH connection is still alive.
    ///
    /// - Returns: `true` if the ControlMaster process is running.
    func healthCheck(profileID: UUID) async -> Bool {
        guard let profile = knownProfiles[profileID] else { return false }

        do {
            return try await multiplexer.isAlive(profile: profile, executor: executor)
        } catch {
            return false
        }
    }

    // MARK: - Backoff Calculation

    /// Calculates the delay for exponential backoff with a maximum cap.
    ///
    /// - Parameter attempt: The zero-indexed attempt number.
    /// - Returns: The delay in seconds before the next retry.
    nonisolated static func backoffDelay(attempt: Int) -> TimeInterval {
        let baseDelay = pow(2.0, Double(attempt))
        return min(baseDelay, maxBackoffDelay)
    }
}
