// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionManager.swift - Orchestrates SSH connections, tunnels and profiles.

import Darwin
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

    /// Bounded checks used before releasing a relay port quarantine.
    nonisolated static let terminationConfirmationAttempts = 5
    nonisolated static let terminationConfirmationDelayNanoseconds: UInt64 = 100_000_000

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

    /// Unforgeable identity of the currently connected ControlMaster lease.
    private var connectionLeaseIDs: [UUID: UUID] = [:]

    /// OS process identity bound to each logical connection lease.
    private var controlMasterIdentities: [UUID: SSHControlMasterIdentity] = [:]

    /// Revocable SFTP authority bound to the exact active ControlMaster socket.
    private var sftpAuthorizations: [UUID: SFTPConnectionAuthorization] = [:]

    /// In-flight SSH commands keyed by profile and invalidated with the connection lease.
    private var remoteCommandTasks: [UUID: [UUID: Task<ProcessResult, Error>]] = [:]

    /// Invalidates delayed connect/reconnect work when a profile is disconnected.
    private var connectionGenerations: [UUID: UInt64] = [:]

    /// Prevents overlapping teardown paths from crossing an async suspension.
    private var terminatingProfileIDs: Set<UUID> = []

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
        guard !terminatingProfileIDs.contains(profile.id) else { return }
        if case .connecting = connections[profile.id] { return }
        if case .reconnecting = connections[profile.id] { return }

        if connectionLeaseIDs[profile.id] != nil {
            if case .connected = connections[profile.id], knownProfiles[profile.id] == profile {
                return
            }

            // Retire the existing socket owner before assigning a new identity
            // to a replacement ControlMaster.
            await disconnect(profileID: profile.id)
            guard connectionLeaseIDs[profile.id] == nil else {
                connections[profile.id] = .failed(
                    "Previous SSH ControlMaster termination is not confirmed"
                )
                return
            }
        }

        let connectionGeneration = nextConnectionGeneration(profileID: profile.id)
        knownProfiles[profile.id] = profile
        connections[profile.id] = .connecting

        do {
            let identity = try await multiplexer.connectAsync(
                profile: profile,
                executor: executor
            )
            guard connectionGenerations[profile.id] == connectionGeneration else {
                await retireStaleControlMaster(profile: profile, identity: identity)
                return
            }
            revokeSFTPAuthorization(profileID: profile.id)
            connectionLeaseIDs[profile.id] = UUID()
            controlMasterIdentities[profile.id] = identity
            connections[profile.id] = .connected(latencyMs: nil)
            return
        } catch {
            let message = errorMessage(from: error)
            guard connectionGenerations[profile.id] == connectionGeneration else { return }

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
                do {
                    try await delaySleep(delayNanoseconds)
                } catch {
                    guard connectionGenerations[profile.id] == connectionGeneration,
                          !Task.isCancelled else { return }
                }
                guard connectionGenerations[profile.id] == connectionGeneration,
                      !Task.isCancelled else { return }

                do {
                    let identity = try await multiplexer.connectAsync(
                        profile: profile,
                        executor: executor
                    )
                    guard connectionGenerations[profile.id] == connectionGeneration else {
                        await retireStaleControlMaster(profile: profile, identity: identity)
                        return
                    }
                    revokeSFTPAuthorization(profileID: profile.id)
                    connectionLeaseIDs[profile.id] = UUID()
                    controlMasterIdentities[profile.id] = identity
                    connections[profile.id] = .connected(latencyMs: nil)
                    return
                } catch {
                    guard connectionGenerations[profile.id] == connectionGeneration else { return }
                    lastErrorMessage = errorMessage(from: error)
                }
            }

            guard connectionGenerations[profile.id] == connectionGeneration else { return }
            connections[profile.id] = .failed(lastErrorMessage)
        }
    }

    private func retireStaleControlMaster(
        profile: RemoteConnectionProfile,
        identity: SSHControlMasterIdentity
    ) async {
        do {
            try await multiplexer.disconnectAsync(
                profile: profile,
                expectedControlMaster: identity,
                executor: executor
            )
        } catch {
            multiplexer.terminateControlMaster(identity)
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
        _ = nextConnectionGeneration(profileID: profileID)
        revokeSFTPAuthorization(profileID: profileID)
        let connectionLeaseID = connectionLeaseIDs[profileID]
        let controlMasterIdentity = controlMasterIdentities[profileID]
        guard beginProfileTermination(profileID: profileID) else { return }
        defer {
            finishProfileTermination(profileID: profileID)
        }

        // Publish the trust-boundary change before the SSH listener is torn
        // down so browser grants cannot outlive the connection lease.
        connections[profileID] = .disconnected
        relayManager?.invalidatePendingOpenings(profileID: profileID)
        proxyManager?.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        await relayManager?.closeAllChannels(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        let retainedRelayChannelIDs = connectionLeaseID.map { leaseID in
            relayManager?.channelIDs(
                profileID: profileID,
                connectionLeaseID: leaseID
            ) ?? []
        } ?? []
        var terminationConfirmed = connectionLeaseID == nil

        if let controlMasterIdentity {
            do {
                try await multiplexer.disconnectAsync(
                    profile: profile,
                    expectedControlMaster: controlMasterIdentity,
                    executor: executor
                )
            } catch {
                multiplexer.terminateControlMaster(controlMasterIdentity)
            }
        }

        if let connectionLeaseID,
           await confirmControlMasterTermination(
               profile: profile,
               expectedLeaseID: connectionLeaseID,
               identity: controlMasterIdentity
           ) {
            terminationConfirmed = true
            if !retainedRelayChannelIDs.isEmpty {
                relayManager?.releaseChannelsAfterSessionTermination(
                    profileID: profileID,
                    connectionLeaseID: connectionLeaseID,
                    channelIDs: retainedRelayChannelIDs
                )
            }
        }

        if connectionLeaseID == nil || connectionLeaseIDs[profileID] == connectionLeaseID {
            await cleanupSubsystems(
                profileID: profileID,
                relayConnectionLeaseID: connectionLeaseID,
                forwardingSessionTerminated: terminationConfirmed
            )
        }
        if terminationConfirmed,
           connectionLeaseID == nil || connectionLeaseIDs[profileID] == connectionLeaseID {
            tunnelManager.removeAllTunnels(for: profileID)
            connectionLeaseIDs.removeValue(forKey: profileID)
            controlMasterIdentities.removeValue(forKey: profileID)
        }
    }

    /// Cleans up relay channels, proxy, and daemon state for a profile.
    ///
    /// Called on disconnect AND when connection fails permanently.
    /// Ensures no orphaned heartbeats, NWConnections, or pending requests.
    private func cleanupSubsystems(
        profileID: UUID,
        relayConnectionLeaseID: UUID? = nil,
        forwardingSessionTerminated: Bool = false
    ) async {
        revokeSFTPAuthorization(profileID: profileID)
        await relayManager?.closeAllChannels(
            profileID: profileID,
            connectionLeaseID: relayConnectionLeaseID
        )
        if forwardingSessionTerminated, let relayConnectionLeaseID {
            proxyManager?.releaseAfterSessionTermination(
                profileID: profileID,
                connectionLeaseID: relayConnectionLeaseID
            )
        } else {
            await proxyManager?.disable(profileID: profileID)
        }
        daemonManager?.invalidate(
            profileID: profileID,
            expectedConnectionLeaseID: relayConnectionLeaseID
        )
    }

    // MARK: - Reconnect

    /// Attempts to re-establish the connection for a known profile.
    ///
    /// Useful after a transient network failure when the user manually
    /// triggers a reconnection.
    func reconnect(profileID: UUID) async {
        guard let profile = knownProfiles[profileID] else { return }
        await disconnect(profileID: profileID)
        guard connectionLeaseIDs[profileID] == nil else { return }
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
    ) async throws {
        guard let profile = knownProfiles[profileID],
              case .connected = connections[profileID],
              let connectionLeaseID = connectionLeaseIDs[profileID],
              let controlMasterIdentity = controlMasterIdentities[profileID] else {
            throw SSHMultiplexerError.connectionFailed("No active connection for profile")
        }
        do {
            try await applyForward(
                forward,
                profile: profile,
                expectedConnectionLeaseID: connectionLeaseID,
                expectedControlMaster: controlMasterIdentity
            )
        } catch {
            guard forwardOutcomeMayBeUncertain(error) else { throw error }
            let cleanupConfirmed = await compensateUncertainForward(
                forward,
                profile: profile,
                expectedConnectionLeaseID: connectionLeaseID,
                expectedControlMaster: controlMasterIdentity
            )
            guard cleanupConfirmed else {
                throw SSHMultiplexerError.forwardCleanupUnconfirmed(
                    "SSH port forward cleanup and exact session revocation were not confirmed"
                )
            }
            throw error
        }
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) async throws {
        guard let profile = knownProfiles[profileID],
              case .connected = connections[profileID],
              connectionLeaseIDs[profileID] == expectedConnectionLeaseID,
              let controlMasterIdentity = controlMasterIdentities[profileID]
        else {
            throw SSHMultiplexerError.notConnected
        }
        try await applyForward(
            forward,
            profile: profile,
            expectedConnectionLeaseID: expectedConnectionLeaseID,
            expectedControlMaster: controlMasterIdentity
        )
    }

    private func applyForward(
        _ forward: RemoteConnectionProfile.PortForward,
        profile: RemoteConnectionProfile,
        expectedConnectionLeaseID: UUID,
        expectedControlMaster: SSHControlMasterIdentity
    ) async throws {
        try await multiplexer.forwardPortAsync(
            forward,
            on: profile,
            expectedControlMaster: expectedControlMaster,
            executor: executor
        )
        guard case .connected = connections[profile.id],
              connectionLeaseIDs[profile.id] == expectedConnectionLeaseID,
              controlMasterIdentities[profile.id] == expectedControlMaster else {
            throw SSHMultiplexerError.notConnected
        }
    }

    private func compensateUncertainForward(
        _ forward: RemoteConnectionProfile.PortForward,
        profile: RemoteConnectionProfile,
        expectedConnectionLeaseID: UUID,
        expectedControlMaster: SSHControlMasterIdentity
    ) async -> Bool {
        do {
            try await multiplexer.cancelForwardAsync(
                forward,
                on: profile,
                expectedControlMaster: expectedControlMaster,
                executor: executor
            )
            return true
        } catch {
            if !multiplexer.isControlMasterProcessAlive(expectedControlMaster) {
                return true
            }
            return await revokeForwardingSession(
                profileID: profile.id,
                expectedLeaseID: expectedConnectionLeaseID
            )
        }
    }

    private func forwardOutcomeMayBeUncertain(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if error as? ProcessExecutorError == .outputLimitExceeded { return true }
        guard let error = error as? SSHMultiplexerError else { return false }
        switch error {
        case .forwardTimedOut, .forwardCleanupUnconfirmed, .notConnected:
            return true
        default:
            return false
        }
    }

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        connectionLeaseIDs[profileID]
    }

    func sftpAuthorization(for profileID: UUID) throws -> SFTPConnectionAuthorization {
        guard let profile = knownProfiles[profileID],
              case .connected = connections[profileID],
              let connectionLeaseID = connectionLeaseIDs[profileID],
              let controlMasterIdentity = controlMasterIdentities[profileID] else {
            throw SFTPClientError.notConnected
        }
        if let existing = sftpAuthorizations[profileID],
           existing.connectionLeaseID == connectionLeaseID,
           existing.controlMasterIdentity == controlMasterIdentity {
            do {
                try existing.verify()
                return existing
            } catch {
                existing.revoke()
                sftpAuthorizations.removeValue(forKey: profileID)
                throw SFTPClientError.notConnected
            }
        }

        let attestation = try multiplexer.attestControlMaster(controlMasterIdentity)
        let multiplexer = self.multiplexer
        let authorization = try SFTPConnectionAuthorization(
            profile: profile,
            connectionLeaseID: connectionLeaseID,
            controlMasterIdentity: controlMasterIdentity,
            controlSocketAttestation: attestation,
            verifier: {
                try multiplexer.verifyControlMaster(
                    controlMasterIdentity,
                    attestation: attestation
                )
            }
        )
        guard case .connected = connections[profileID],
              connectionLeaseIDs[profileID] == connectionLeaseID,
              controlMasterIdentities[profileID] == controlMasterIdentity else {
            authorization.revoke()
            throw SFTPClientError.notConnected
        }
        sftpAuthorizations[profileID] = authorization
        return authorization
    }

    func makeSFTPClient(
        profileID: UUID,
        executor: any SFTPExecutor = SystemSFTPExecutor()
    ) throws -> SFTPClient {
        try SFTPClient(
            executor: executor,
            authorization: sftpAuthorization(for: profileID)
        )
    }

    func openProxyTransport(
        to target: ProxyTarget,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> any ProxyUpstreamTransport {
        guard let profile = knownProfiles[profileID],
              case .connected = connections[profileID],
              connectionLeaseIDs[profileID] == expectedConnectionLeaseID,
              let controlMasterIdentity = controlMasterIdentities[profileID]
        else {
            throw SSHMultiplexerError.notConnected
        }

        let transport = try multiplexer.openDirectTCPTransport(
            to: target,
            on: profile,
            expectedControlMaster: controlMasterIdentity
        )
        guard case .connected = connections[profileID],
              connectionLeaseIDs[profileID] == expectedConnectionLeaseID,
              controlMasterIdentities[profileID] == controlMasterIdentity else {
            transport.cancel()
            throw SSHMultiplexerError.notConnected
        }
        return transport
    }

    func openDaemonTransport(
        remotePort: Int,
        profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> DaemonTransportBinding {
        let target = try ProxyTarget(host: "127.0.0.1", port: remotePort)
        let transport = try openProxyTransport(
            to: target,
            for: profileID,
            expectedConnectionLeaseID: expectedConnectionLeaseID
        )
        return DaemonTransportBinding(
            profileID: profileID,
            connectionLeaseID: expectedConnectionLeaseID,
            transport: transport
        )
    }

    /// Revokes a profile's entire forwarding authority after a local broker fails closed.
    @discardableResult
    func revokeForwardingSession(
        profileID: UUID,
        expectedLeaseID: UUID
    ) async -> Bool {
        guard connectionLeaseIDs[profileID] == expectedLeaseID else { return false }
        guard beginProfileTermination(profileID: profileID) else { return false }
        defer {
            finishProfileTermination(profileID: profileID)
        }
        _ = nextConnectionGeneration(profileID: profileID)
        revokeSFTPAuthorization(profileID: profileID)
        relayManager?.invalidatePendingOpenings(profileID: profileID)
        relayManager?.deactivateChannelsForSessionTermination(
            profileID: profileID,
            connectionLeaseID: expectedLeaseID
        )
        connections[profileID] = .disconnected
        proxyManager?.prepareForSessionTermination(
            profileID: profileID,
            connectionLeaseID: expectedLeaseID
        )

        guard let profile = knownProfiles[profileID],
              let controlMasterIdentity = controlMasterIdentities[profileID] else {
            tunnelManager.removeAllTunnels(for: profileID)
            return false
        }

        do {
            try await multiplexer.disconnectAsync(
                profile: profile,
                expectedControlMaster: controlMasterIdentity,
                executor: executor
            )
        } catch {
            multiplexer.terminateControlMaster(controlMasterIdentity)
            NSLog("[RemoteConnectionManager] Failed to request SSH forwarding session revocation")
        }
        let sessionTerminated = await confirmControlMasterTermination(
            profile: profile,
            expectedLeaseID: expectedLeaseID,
            identity: controlMasterIdentity
        )

        guard connectionLeaseIDs[profileID] == expectedLeaseID else { return false }

        if sessionTerminated {
            proxyManager?.releaseAfterSessionTermination(
                profileID: profileID,
                connectionLeaseID: expectedLeaseID
            )
        } else {
            await proxyManager?.disable(profileID: profileID)
        }
        guard connectionLeaseIDs[profileID] == expectedLeaseID else { return false }
        daemonManager?.invalidate(
            profileID: profileID,
            expectedConnectionLeaseID: expectedLeaseID
        )
        if sessionTerminated {
            tunnelManager.removeAllTunnels(for: profileID)
            connectionLeaseIDs.removeValue(forKey: profileID)
            controlMasterIdentities.removeValue(forKey: profileID)
        }
        return sessionTerminated
    }

    /// Bounded synchronous shutdown used while AppKit still owns local brokers.
    /// Local listeners are denied first for every profile, then all supervisor
    /// pipes are closed before one shared process-death wait.
    func shutdownForApplicationTermination() {
        var activeSessions: [(
            profileID: UUID,
            connectionLeaseID: UUID?,
            identity: SSHControlMasterIdentity?
        )] = []

        for profileID in knownProfiles.keys {
            _ = nextConnectionGeneration(profileID: profileID)
            revokeSFTPAuthorization(profileID: profileID)
            connections[profileID] = .disconnected
            let connectionLeaseID = connectionLeaseIDs[profileID]
            let identity = controlMasterIdentities[profileID]
            daemonManager?.invalidate(
                profileID: profileID,
                expectedConnectionLeaseID: connectionLeaseID
            )
            relayManager?.invalidatePendingOpenings(profileID: profileID)
            relayManager?.deactivateChannelsForSessionTermination(
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
            proxyManager?.prepareForSessionTermination(
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
            if connectionLeaseID != nil || identity != nil {
                activeSessions.append((profileID, connectionLeaseID, identity))
            }
        }

        for session in activeSessions {
            if let identity = session.identity {
                multiplexer.terminateControlMaster(identity)
            }
        }

        for _ in 0..<20 {
            let anyProcessAlive = activeSessions.contains { session in
                guard let identity = session.identity else { return false }
                return multiplexer.isControlMasterProcessAlive(identity)
            }
            if !anyProcessAlive { break }
            usleep(50_000)
        }

        for session in activeSessions {
            guard let identity = session.identity,
                  !multiplexer.isControlMasterProcessAlive(identity) else { continue }

            if let connectionLeaseID = session.connectionLeaseID {
                relayManager?.releaseChannelsAfterSessionTermination(
                    profileID: session.profileID,
                    connectionLeaseID: connectionLeaseID
                )
                proxyManager?.releaseAfterSessionTermination(
                    profileID: session.profileID,
                    connectionLeaseID: connectionLeaseID
                )
            } else {
                relayManager?.releaseChannelsAfterSessionTermination(
                    profileID: session.profileID
                )
            }
            tunnelManager.removeAllTunnels(for: session.profileID)
            connectionLeaseIDs.removeValue(forKey: session.profileID)
            controlMasterIdentities.removeValue(forKey: session.profileID)
        }
    }

    private func beginProfileTermination(profileID: UUID) -> Bool {
        terminatingProfileIDs.insert(profileID).inserted
    }

    private func finishProfileTermination(profileID: UUID) {
        terminatingProfileIDs.remove(profileID)
    }

    /// Treats `ssh -O exit` as a request, then proves the master is no longer alive.
    private func confirmControlMasterTermination(
        profile: RemoteConnectionProfile,
        expectedLeaseID: UUID,
        identity: SSHControlMasterIdentity?
    ) async -> Bool {
        guard let identity else { return false }
        for attempt in 0..<Self.terminationConfirmationAttempts {
            if Task.isCancelled { return false }
            guard connectionLeaseIDs[profile.id] == expectedLeaseID,
                  controlMasterIdentities[profile.id] == identity else { return false }
            if !multiplexer.isControlMasterProcessAlive(identity) { return true }

            if attempt + 1 < Self.terminationConfirmationAttempts {
                do {
                    try await delaySleep(Self.terminationConfirmationDelayNanoseconds)
                } catch {
                    return false
                }
            }
        }
        return false
    }

    private func nextConnectionGeneration(profileID: UUID) -> UInt64 {
        cancelRemoteCommands(profileID: profileID)
        connectionGenerations[profileID, default: 0] &+= 1
        return connectionGenerations[profileID, default: 0]
    }

    private func revokeSFTPAuthorization(profileID: UUID) {
        sftpAuthorizations.removeValue(forKey: profileID)?.revoke()
    }

    private func cancelRemoteCommands(profileID: UUID) {
        guard let tasks = remoteCommandTasks.removeValue(forKey: profileID) else { return }
        for task in tasks.values {
            task.cancel()
        }
    }

    private func removeRemoteCommandTask(profileID: UUID, operationID: UUID) {
        remoteCommandTasks[profileID]?.removeValue(forKey: operationID)
        if remoteCommandTasks[profileID]?.isEmpty == true {
            remoteCommandTasks.removeValue(forKey: profileID)
        }
    }

    /// Cancels an active port forward on the SSH ControlMaster.
    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) async throws {
        guard let connectionLeaseID = connectionLeaseIDs[profileID] else {
            throw SSHMultiplexerError.connectionFailed("No active connection for profile")
        }
        try await cancelForward(
            forward,
            for: profileID,
            expectedConnectionLeaseID: connectionLeaseID
        )
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) async throws {
        let canUseForwardingSession: Bool
        if case .connected = connections[profileID] {
            canUseForwardingSession = true
        } else {
            canUseForwardingSession = terminatingProfileIDs.contains(profileID)
        }

        guard let profile = knownProfiles[profileID],
              connectionLeaseIDs[profileID] == expectedConnectionLeaseID,
              let controlMasterIdentity = controlMasterIdentities[profileID],
              canUseForwardingSession else {
            throw SSHMultiplexerError.notConnected
        }
        try await multiplexer.cancelForwardAsync(
            forward,
            on: profile,
            expectedControlMaster: controlMasterIdentity,
            executor: executor
        )
        guard connectionLeaseIDs[profileID] == expectedConnectionLeaseID,
              controlMasterIdentities[profileID] == controlMasterIdentity else {
            throw SSHMultiplexerError.notConnected
        }
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
        guard let profile = knownProfiles[profileID],
              case .connected = connections[profileID],
              let connectionLeaseID = connectionLeaseIDs[profileID],
              let controlMasterIdentity = controlMasterIdentities[profileID] else {
            throw SSHMultiplexerError.notConnected
        }
        let attestation = try multiplexer.attestControlMaster(controlMasterIdentity)
        try Task.checkCancellation()
        let operationID = UUID()
        let multiplexer = self.multiplexer
        let executor = self.executor
        let executionTask = Task<ProcessResult, Error> {
            try await multiplexer.executeRemoteCommand(
                command,
                on: profile,
                expectedControlMaster: controlMasterIdentity,
                executor: executor
            )
        }
        remoteCommandTasks[profileID, default: [:]][operationID] = executionTask
        defer {
            removeRemoteCommandTask(profileID: profileID, operationID: operationID)
        }

        let result: ProcessResult
        do {
            result = try await withTaskCancellationHandler {
                try await executionTask.value
            } onCancel: {
                executionTask.cancel()
            }
        } catch is CancellationError {
            if Task.isCancelled { throw CancellationError() }
            throw SSHMultiplexerError.notConnected
        } catch {
            let leaseIsCurrent = connectionLeaseIDs[profileID] == connectionLeaseID
                && controlMasterIdentities[profileID] == controlMasterIdentity
            guard case .connected = connections[profileID], leaseIsCurrent else {
                throw SSHMultiplexerError.notConnected
            }
            throw error
        }
        var connectionRemainsVerified = result.postExecutionConnectionState == .verified
        if connectionRemainsVerified {
            do {
                try multiplexer.verifyControlMaster(
                    controlMasterIdentity,
                    attestation: attestation
                )
            } catch {
                connectionRemainsVerified = false
            }
        }
        if connectionRemainsVerified {
            let isStillConnected: Bool
            if case .connected = connections[profileID] {
                isStillConnected = true
            } else {
                isStillConnected = false
            }
            connectionRemainsVerified = isStillConnected
                && connectionLeaseIDs[profileID] == connectionLeaseID
                && controlMasterIdentities[profileID] == controlMasterIdentity
        }
        if !connectionRemainsVerified {
            _ = await revokeForwardingSession(
                profileID: profileID,
                expectedLeaseID: connectionLeaseID
            )
        }
        if result.timedOut {
            let diagnostic = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHMultiplexerError.remoteCommandTimedOut(
                diagnostic.isEmpty ? "Remote command timed out" : diagnostic
            )
        }
        guard result.exitCode == 0 else {
            let diagnostic = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHMultiplexerError.connectionFailed(
                diagnostic.isEmpty
                    ? "Remote command exited with code \(result.exitCode)"
                    : diagnostic
            )
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
extension RemoteConnectionManager: DaemonTransportProviding {}
