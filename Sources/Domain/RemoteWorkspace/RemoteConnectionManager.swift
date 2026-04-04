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
    nonisolated static let maxReconnectAttempts = 5

    /// Maximum delay between reconnection attempts (in seconds).
    nonisolated static let maxBackoffDelay: TimeInterval = 30.0

    // MARK: - Published State

    /// Current connection state for each profile, keyed by profile ID.
    @Published private(set) var connections: [UUID: ConnectionState] = [:]

    // MARK: - Dependencies

    private let multiplexer: any SSHMultiplexing
    private let profileStore: any RemoteProfileStoring
    private let tunnelManager: SSHTunnelManager
    private let executor: any ProcessExecutor
    private let tmuxManager: any TmuxSessionManaging
    private let sessionStore: any RemoteSessionStoring

    /// Async delay function for backoff waits. Injected for testability.
    private let delaySleep: @Sendable (UInt64) async throws -> Void

    /// Profiles that have been connected (kept in memory for reconnect/health check).
    private var knownProfiles: [UUID: RemoteConnectionProfile] = [:]

    /// Cached remote shell support per profile.
    private(set) var remoteSupport: [UUID: RemoteShellSupport] = [:]

    /// Optional proxy manager for coordinated recovery on reconnect.
    var proxyManager: ProxyManagerImpl?

    /// Optional relay manager for multi-channel reverse tunnels.
    var relayManager: RelayManagerImpl?

    /// Optional daemon manager for remote cocxyd lifecycle.
    var daemonManager: DaemonManagerImpl?

    // MARK: - Initialization

    /// Creates a connection manager with injected dependencies.
    ///
    /// - Parameters:
    ///   - multiplexer: SSH ControlMaster manager.
    ///   - profileStore: Persistent profile storage.
    ///   - tunnelManager: Active tunnel tracker.
    ///   - executor: Process executor for SSH commands.
    ///   - tmuxManager: Tmux session manager for remote persistence.
    ///   - sessionStore: Local persistence for remote session metadata.
    ///   - delaySleep: Async delay function. Defaults to `Task.sleep(nanoseconds:)`.
    ///     Inject a no-op closure in tests to avoid real waiting.
    init(
        multiplexer: any SSHMultiplexing,
        profileStore: any RemoteProfileStoring,
        tunnelManager: SSHTunnelManager,
        executor: any ProcessExecutor,
        tmuxManager: any TmuxSessionManaging = TmuxSessionManager(),
        sessionStore: any RemoteSessionStoring = RemoteSessionStore(),
        delaySleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.multiplexer = multiplexer
        self.profileStore = profileStore
        self.tunnelManager = tunnelManager
        self.executor = executor
        self.tmuxManager = tmuxManager
        self.sessionStore = sessionStore
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
                await cleanupSubsystems(profileID: profile.id)
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

            await cleanupSubsystems(profileID: profile.id)
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

        await cleanupSubsystems(profileID: profileID)
        tunnelManager.removeAllTunnels(for: profileID)
        connections[profileID] = .disconnected
    }

    /// Cleans up relay channels, proxy, and daemon state for a profile.
    ///
    /// Called on disconnect AND when connection fails permanently.
    /// Ensures no orphaned heartbeats, NWConnections, or pending requests.
    private func cleanupSubsystems(profileID: UUID) async {
        relayManager?.closeAllChannels(profileID: profileID)
        await proxyManager?.disable(profileID: profileID)
        daemonManager?.connection.disconnect()
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

    // MARK: - Port Forwarding

    /// Dynamically adds a port forward through the active SSH ControlMaster.
    ///
    /// Delegates to `SSHMultiplexer.forwardPort()` which runs `ssh -O forward`.
    /// The tunnel manager is updated by the caller.
    ///
    /// - Parameters:
    ///   - forward: The port forwarding rule to apply.
    ///   - profileID: The profile whose SSH session carries the forward.
    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        guard let profile = knownProfiles[profileID] else {
            throw SSHMultiplexerError.connectionFailed("No active connection for profile")
        }
        try multiplexer.forwardPort(forward, on: profile, executor: executor)
    }

    /// Cancels an active port forward on the SSH ControlMaster.
    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        guard let profile = knownProfiles[profileID] else { return }
        try multiplexer.cancelForward(forward, on: profile, executor: executor)
    }

    // MARK: - Remote Command Execution

    /// Executes a command on the remote server via the SSH ControlMaster.
    ///
    /// Used by `DaemonDeployer` for deploy, start, stop, and version check.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute on the remote host.
    ///   - profileID: The profile whose SSH session carries the command.
    /// - Returns: The command's stdout output.
    func executeRemoteCommand(_ command: String, profileID: UUID) async throws -> String {
        guard let profile = knownProfiles[profileID] else {
            throw SSHMultiplexerError.connectionFailed("No active connection for profile")
        }
        let result = try await multiplexer.executeRemoteCommand(command, on: profile, executor: executor)
        if result.exitCode != 0 && !result.stderr.isEmpty {
            throw SSHMultiplexerError.connectionFailed(result.stderr)
        }
        return result.stdout
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

    // MARK: - Remote Session Support

    /// Detects which session multiplexer is available on the remote host.
    ///
    /// Caches the result per profile to avoid repeated SSH round-trips.
    /// Requires an active ControlMaster connection.
    func detectRemoteSupport(profileID: UUID) async -> RemoteShellSupport {
        if let cached = remoteSupport[profileID] {
            return cached
        }
        guard let profile = knownProfiles[profileID] else { return .none }

        let support = await tmuxManager.detectSupport(
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )
        remoteSupport[profileID] = support
        return support
    }

    // MARK: - Tmux Session Operations

    /// Lists all tmux sessions on the remote host for a given profile.
    ///
    /// Requires an active SSH connection. Returns an empty array if
    /// tmux is not available or no sessions exist.
    func listRemoteSessions(profileID: UUID) async -> [TmuxSessionInfo] {
        guard let profile = knownProfiles[profileID],
              connections[profileID] == .connected(latencyMs: nil)
                || isConnected(profileID: profileID)
        else { return [] }

        do {
            return try await tmuxManager.listSessions(
                on: profile,
                multiplexer: multiplexer,
                executor: executor
            )
        } catch {
            return []
        }
    }

    /// Creates a new persistent tmux session on the remote host.
    ///
    /// The session is created in detached mode so it persists
    /// even if the SSH connection drops. A local record is saved
    /// for offline reconnection tracking.
    ///
    /// - Parameters:
    ///   - name: The session name (will be prefixed with "cocxy-" if not already).
    ///   - profileID: The profile to create the session on.
    /// - Throws: `TmuxError` if session creation fails.
    func createRemoteSession(named name: String, profileID: UUID) async throws {
        guard let profile = knownProfiles[profileID] else { return }

        let sessionName = name.hasPrefix(TmuxSessionManager.sessionPrefix)
            ? name
            : "\(TmuxSessionManager.sessionPrefix)\(name)"

        try await tmuxManager.createSession(
            named: sessionName,
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )

        // Persist record locally for reconnection tracking.
        let record = RemoteSessionRecord(
            profileID: profileID,
            sessionName: sessionName,
            profileDisplayTitle: profile.displayTitle
        )
        try? sessionStore.save(record)
    }

    /// Returns the SSH command string to attach to a remote tmux session.
    ///
    /// The returned command reuses the existing ControlMaster and allocates
    /// a TTY for interactive use.
    func attachCommand(sessionName: String, profileID: UUID) -> String? {
        guard let profile = knownProfiles[profileID] else { return nil }

        return tmuxManager.attachCommand(
            sessionName: sessionName,
            on: profile,
            multiplexer: multiplexer
        )
    }

    /// Kills a remote tmux session and removes its local record.
    func killRemoteSession(named name: String, profileID: UUID) async throws {
        guard let profile = knownProfiles[profileID] else { return }

        try await tmuxManager.killSession(
            named: name,
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )

        // Remove local records for this session.
        if let records = try? sessionStore.findByProfile(profileID) {
            for record in records where record.sessionName == name {
                try? sessionStore.delete(id: record.id)
            }
        }
    }

    /// Returns locally-stored session records for offline reconnection display.
    func savedSessionRecords(profileID: UUID) -> [RemoteSessionRecord] {
        (try? sessionStore.findByProfile(profileID)) ?? []
    }

    // MARK: - Connection State Helpers

    /// Returns whether a profile is in any connected state.
    private func isConnected(profileID: UUID) -> Bool {
        guard let state = connections[profileID] else { return false }
        if case .connected = state { return true }
        return false
    }
}

// MARK: - PortForwarding Conformance

/// RemoteConnectionManager already implements the required methods.
/// This conformance enables ProxyManager to use it without tight coupling.
extension RemoteConnectionManager: PortForwarding {}
