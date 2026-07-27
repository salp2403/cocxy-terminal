// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManager.swift - Multi-channel relay orchestrator.

import Foundation
import Combine

// MARK: - Relay Managing Protocol

/// Defines the public API for relay channel management.
@MainActor
protocol RelayManaging: AnyObject {
    func openChannel(config: RelayChannelConfig, profileID: UUID) async throws -> RelayChannel
    func closeChannel(channelID: UUID) async
    func closeAllChannels(profileID: UUID) async
    func listChannels(profileID: UUID) -> [RelayChannel]
    func rotateToken(channelID: UUID) throws
    func updateACL(channelID: UUID, acl: RelayACL)
}

enum RelayManagerError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Relay channel name is required"
        case .invalidPort:
            return "Relay ports must be between 1 and 65535"
        }
    }
}

typealias RelayAuthBrokerFactory = @MainActor (
    _ channelID: UUID,
    _ token: RelayToken,
    _ acl: RelayACL,
    _ targetHost: String,
    _ targetPort: UInt16,
    _ auditLog: RelayAuditLog?
) -> any RelayAuthBrokering

typealias RelayProfileSessionRevoker = @MainActor (
    _ profileID: UUID,
    _ connectionLeaseID: UUID
) async -> Bool

// MARK: - Relay Manager Implementation

/// Orchestrates relay channels: creates reverse tunnels, manages tokens,
/// and handles auto-cleanup on disconnect.
///
/// Each channel gets:
/// - A loopback authentication broker as the mandatory reverse-tunnel target
/// - A unique `RelayToken` for HMAC authentication
/// - An optional expiration time for auto-close
@MainActor
final class RelayManagerImpl: RelayManaging, ObservableObject {

    private struct ProfileRevocationTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct ProfileLeaseKey: Hashable {
        let profileID: UUID
        let connectionLeaseID: UUID
    }

    // MARK: - Published State

    @Published private(set) var channels: [UUID: RelayChannel] = [:]
    @Published private(set) var tokens: [UUID: RelayToken] = [:]

    // MARK: - Dependencies

    private let tunnelManager: SSHTunnelManager
    private weak var forwarder: (any PortForwarding)?
    private let tokenStore: any RelayTokenStoring
    private let auditLog: RelayAuditLog?
    private let brokerFactory: RelayAuthBrokerFactory
    private let profileSessionRevoker: RelayProfileSessionRevoker

    /// Security topology retained for the full lifetime of every SSH listener.
    private var brokers: [UUID: any RelayAuthBrokering] = [:]
    private var forwards: [UUID: RemoteConnectionProfile.PortForward] = [:]
    private var tunnelIDs: [UUID: UUID] = [:]
    private var channelLeaseIDs: [UUID: UUID] = [:]
    private var openingGenerations: [UUID: UInt64] = [:]
    private var openingChannelIDs: Set<UUID> = []
    private var openingFailures: [UUID: String] = [:]
    private var closingChannelIDs: Set<UUID> = []
    private var profileRevocationTasks: [ProfileLeaseKey: ProfileRevocationTask] = [:]

    // MARK: - Auto-Cleanup

    /// Timer that checks for expired channels every 60 seconds.
    private var expirationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        tunnelManager: SSHTunnelManager,
        forwarder: any PortForwarding,
        tokenStore: any RelayTokenStoring = InMemoryTokenStore(),
        auditLog: RelayAuditLog? = nil,
        profileSessionRevoker: @escaping RelayProfileSessionRevoker = { _, _ in false },
        brokerFactory: @escaping RelayAuthBrokerFactory = {
            channelID, token, acl, targetHost, targetPort, auditLog in
            RelayAuthBroker(
                channelID: channelID,
                token: token,
                acl: acl,
                targetHost: targetHost,
                targetPort: targetPort,
                auditLog: auditLog
            )
        }
    ) {
        self.tunnelManager = tunnelManager
        self.forwarder = forwarder
        self.tokenStore = tokenStore
        self.auditLog = auditLog
        self.profileSessionRevoker = profileSessionRevoker
        self.brokerFactory = brokerFactory
        startExpirationTimer()
    }

    // MARK: - Open Channel

    /// Creates a new relay channel with a reverse SSH tunnel.
    ///
    /// - Parameters:
    ///   - config: The channel configuration (name, ports).
    ///   - profileID: The remote profile whose SSH session carries the tunnel.
    /// - Returns: The created `RelayChannel` with a fresh token.
    @discardableResult
    func openChannel(config: RelayChannelConfig, profileID: UUID) async throws -> RelayChannel {
        guard let forwarder else {
            throw SSHMultiplexerError.connectionFailed("Port forwarder unavailable")
        }
        guard let connectionLeaseID = forwarder.connectionLeaseID(for: profileID) else {
            throw SSHMultiplexerError.connectionFailed("No active connection lease for profile")
        }
        guard (1...65535).contains(config.localPort),
              (1...65535).contains(config.remotePort)
        else {
            throw RelayManagerError.invalidPort
        }
        let channelName = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelName.isEmpty else { throw RelayManagerError.invalidName }
        let openingGeneration = openingGenerations[profileID, default: 0]

        let channel = RelayChannel(
            profileID: profileID,
            name: channelName,
            localHost: config.localHost,
            localPort: config.localPort,
            remotePort: config.remotePort
        )
        let token = RelayToken.generate()
        let broker = brokerFactory(
            channel.id,
            token,
            channel.acl,
            channel.localHost,
            UInt16(channel.localPort),
            auditLog
        )
        openingChannelIDs.insert(channel.id)
        brokers[channel.id] = broker
        defer {
            openingChannelIDs.remove(channel.id)
            openingFailures.removeValue(forKey: channel.id)
        }
        broker.setConnectionCountHandler { [weak self] count in
            self?.updateConnectionCount(channelID: channel.id, count: count)
        }
        broker.setFailureHandler { [weak self] error in
            self?.handleBrokerFailureSignal(channelID: channel.id, error: error)
        }

        do {
            try tokenStore.save(token: token, channelID: channel.id)
        } catch {
            brokers.removeValue(forKey: channel.id)
            broker.stop()
            throw error
        }

        let brokerPort: UInt16
        do {
            brokerPort = try await broker.startOnEphemeralLoopbackPort()
            try Task.checkCancellation()
            guard openingGenerations[profileID, default: 0] == openingGeneration else {
                throw CancellationError()
            }
            guard forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
                throw CancellationError()
            }
            if let failure = openingFailures[channel.id] {
                throw SSHMultiplexerError.connectionFailed(
                    "Relay authentication broker failed during setup: \(failure)"
                )
            }
        } catch {
            try? tokenStore.delete(channelID: channel.id)
            brokers.removeValue(forKey: channel.id)
            broker.stop()
            throw error
        }

        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: config.remotePort,
            localPort: Int(brokerPort),
            localHost: "127.0.0.1"
        )

        forwards[channel.id] = forward

        var forwardWasConfirmed = false
        do {
            try await forwarder.forwardPort(
                forward,
                for: profileID,
                expectedConnectionLeaseID: connectionLeaseID
            )
            forwardWasConfirmed = true
            guard !Task.isCancelled,
                  openingGenerations[profileID, default: 0] == openingGeneration,
                  forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
                throw CancellationError()
            }
        } catch {
            var cleanupConfirmed = !forwardWasConfirmed && !forwardOutcomeMayBeUncertain(error)
            if forwardWasConfirmed || forwardOutcomeMayBeUncertain(error) {
                cleanupConfirmed = await compensateForwardOpening(
                    forward,
                    profileID: profileID,
                    connectionLeaseID: connectionLeaseID,
                    forwarder: forwarder
                )
            }
            guard cleanupConfirmed else {
                retainUncertainForwardOpening(
                    channel: channel,
                    token: token,
                    forward: forward,
                    connectionLeaseID: connectionLeaseID,
                    broker: broker,
                    reason: error.localizedDescription
                )
                scheduleProfileRevocation(
                    profileID: profileID,
                    connectionLeaseID: connectionLeaseID
                )
                throw error
            }
            brokers.removeValue(forKey: channel.id)
            forwards.removeValue(forKey: channel.id)
            broker.stop()
            try? tokenStore.delete(channelID: channel.id)
            throw error
        }

        let tunnel = tunnelManager.addTunnel(forward: forward, for: profileID)
        tunnelIDs[channel.id] = tunnel.id
        channelLeaseIDs[channel.id] = connectionLeaseID
        channels[channel.id] = channel
        tokens[channel.id] = token
        auditLog?.log(.channelOpened(channelID: channel.id, name: channel.name))

        return channel
    }

    // MARK: - Close Channel

    /// Closes a single relay channel and cancels its reverse tunnel.
    func closeChannel(channelID: UUID) async {
        guard var channel = channels[channelID] else { return }
        guard closingChannelIDs.insert(channelID).inserted else { return }
        defer { closingChannelIDs.remove(channelID) }

        if let forward = forwards[channelID] {
            guard let forwarder else {
                brokers[channelID]?.deactivate()
                channel.status = .closeFailed(reason: "SSH forwarder unavailable")
                channel.connectionCount = 0
                channels[channelID] = channel
                return
            }
            guard let connectionLeaseID = channelLeaseIDs[channelID],
                  forwarder.connectionLeaseID(for: channel.profileID) == connectionLeaseID
            else {
                brokers[channelID]?.deactivate()
                channel.status = .closeFailed(
                    reason: "SSH session changed before listener closure was confirmed"
                )
                channel.connectionCount = 0
                channels[channelID] = channel
                return
            }
            brokers[channelID]?.deactivate()
            channel.connectionCount = 0
            channels[channelID] = channel
            do {
                try await forwarder.cancelForward(
                    forward,
                    for: channel.profileID,
                    expectedConnectionLeaseID: connectionLeaseID
                )
            } catch {
                guard channels[channelID] != nil else { return }
                brokers[channelID]?.deactivate()
                channel.status = .closeFailed(reason: error.localizedDescription)
                channel.connectionCount = 0
                channels[channelID] = channel
                if let tunnelID = tunnelIDs[channelID] {
                    tunnelManager.updateTunnelStatus(
                        id: tunnelID,
                        status: .failed(error.localizedDescription)
                    )
                }
                return
            }
            guard channels[channelID] != nil,
                  channelLeaseIDs[channelID] == connectionLeaseID else { return }
        }

        finalizeClosedChannel(channelID: channelID)
    }

    /// Closes all channels for a given profile.
    ///
    /// Called when a profile disconnects to clean up all associated tunnels.
    func closeAllChannels(profileID: UUID) async {
        await closeAllChannels(profileID: profileID, connectionLeaseID: nil)
    }

    func closeAllChannels(profileID: UUID, connectionLeaseID: UUID?) async {
        invalidatePendingOpenings(profileID: profileID)
        deactivateChannelsForSessionTermination(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        let profileChannels = channels.values.filter { channel in
            guard channel.profileID == profileID else { return false }
            return connectionLeaseID.map { channelLeaseIDs[channel.id] == $0 } ?? true
        }
        for channel in profileChannels {
            await closeChannel(channelID: channel.id)
        }
    }

    /// Denies relay traffic synchronously without invoking OpenSSH. This is a
    /// first shutdown phase so one blocked control command cannot leave another
    /// profile's authenticated broker accepting traffic.
    func deactivateChannelsForSessionTermination(
        profileID: UUID,
        connectionLeaseID: UUID?
    ) {
        invalidatePendingOpenings(profileID: profileID)
        let profileChannels = channels.values.filter { channel in
            guard channel.profileID == profileID else { return false }
            return connectionLeaseID.map { channelLeaseIDs[channel.id] == $0 } ?? true
        }
        for var channel in profileChannels {
            brokers[channel.id]?.deactivate()
            channel.connectionCount = 0
            channel.status = .closeFailed(
                reason: "SSH session termination is not yet confirmed"
            )
            channels[channel.id] = channel
        }
    }

    /// Releases quarantined local state only after the owning ControlMaster has exited.
    func releaseChannelsAfterSessionTermination(
        profileID: UUID,
        connectionLeaseID: UUID? = nil,
        channelIDs: Set<UUID>? = nil
    ) {
        if let connectionLeaseID {
            let key = ProfileLeaseKey(
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
            profileRevocationTasks.removeValue(forKey: key)?.task.cancel()
        } else {
            let keys = profileRevocationTasks.keys.filter { $0.profileID == profileID }
            for key in keys {
                profileRevocationTasks.removeValue(forKey: key)?.task.cancel()
            }
        }
        let profileChannels = channels.values.filter { channel in
            guard channel.profileID == profileID else { return false }
            guard connectionLeaseID.map({ channelLeaseIDs[channel.id] == $0 }) ?? true else {
                return false
            }
            return channelIDs?.contains(channel.id) ?? true
        }
        for channel in profileChannels {
            finalizeClosedChannel(channelID: channel.id)
        }
    }

    // MARK: - List Channels

    /// Returns all active channels for a given profile.
    func listChannels(profileID: UUID) -> [RelayChannel] {
        channels.values
            .filter { $0.profileID == profileID }
            .sorted { $0.name < $1.name }
    }

    func channelIDs(profileID: UUID, connectionLeaseID: UUID) -> Set<UUID> {
        Set(channels.values.lazy.filter { channel in
            channel.profileID == profileID
                && self.channelLeaseIDs[channel.id] == connectionLeaseID
        }.map(\.id))
    }

    // MARK: - Token Management

    /// Rotates the token for a channel, invalidating the old one.
    func rotateToken(channelID: UUID) throws {
        guard let channel = channels[channelID],
              channel.status.isActive,
              brokers[channelID] != nil
        else { return }
        let newToken = RelayToken.generate()
        try tokenStore.save(token: newToken, channelID: channelID)
        tokens[channelID] = newToken
        brokers[channelID]?.updateAuthorization(token: newToken, acl: channel.acl)
        auditLog?.log(.tokenRotated(channelID: channelID))
    }

    /// Returns the current token for a channel.
    func token(for channelID: UUID) -> RelayToken? {
        tokens[channelID]
    }

    func clientCommand(for channelID: UUID) -> String? {
        guard let channel = channels[channelID],
              channel.status.isActive,
              tokens[channelID] != nil
        else { return nil }
        return RelayClientBootstrap(
            channelID: channelID,
            remotePort: channel.remotePort
        ).shellCommand()
    }

    func clientToken(for channelID: UUID) -> String? {
        guard let channel = channels[channelID],
              channel.status.isActive,
              let token = tokens[channelID]
        else { return nil }
        return token.secret.base64EncodedString()
    }

    // MARK: - ACL Management

    /// Updates the access control list for an active channel.
    ///
    /// The new ACL applies to subsequent connections only;
    /// already-established connections are not affected.
    func updateACL(channelID: UUID, acl: RelayACL) {
        guard var channel = channels[channelID], channel.status.isActive else { return }
        channel = RelayChannel(
            id: channel.id,
            profileID: channel.profileID,
            name: channel.name,
            localHost: channel.localHost,
            localPort: channel.localPort,
            remotePort: channel.remotePort,
            acl: acl,
            createdAt: channel.createdAt,
            expiresAt: channel.expiresAt,
            connectionCount: channel.connectionCount,
            status: channel.status
        )
        channels[channelID] = channel
        if let token = tokens[channelID] {
            brokers[channelID]?.updateAuthorization(token: token, acl: acl)
        }
    }

    // MARK: - Expiration Timer

    /// Starts a periodic timer that closes expired channels.
    private func startExpirationTimer() {
        expirationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                guard let self else { return }
                await self.closeExpiredChannels()
            }
        }
    }

    /// Stops the expiration timer.
    func stopExpirationTimer() {
        expirationTask?.cancel()
        expirationTask = nil
        for revocation in profileRevocationTasks.values {
            revocation.task.cancel()
        }
        profileRevocationTasks.removeAll()
    }

    /// Closes all channels that have passed their `expiresAt` time.
    private func closeExpiredChannels() async {
        let expired = channels.values.filter { $0.isExpired }
        for channel in expired {
            await closeChannel(channelID: channel.id)
        }
    }

    private func updateConnectionCount(channelID: UUID, count: Int) {
        guard var channel = channels[channelID] else { return }
        channel.connectionCount = count
        channels[channelID] = channel
    }

    func invalidatePendingOpenings(profileID: UUID) {
        openingGenerations[profileID, default: 0] &+= 1
    }

    private func handleBrokerFailureSignal(channelID: UUID, error: any Error) {
        if openingChannelIDs.contains(channelID) {
            brokers[channelID]?.deactivate()
            openingFailures[channelID] = error.localizedDescription
            return
        }

        guard let channel = channels[channelID],
              let connectionLeaseID = channelLeaseIDs[channelID]
        else { return }
        guard !closingChannelIDs.contains(channelID) else { return }
        retainBrokerFailure(channelID: channelID, error: error)

        Task { @MainActor [weak self] in
            await self?.resolveBrokerFailure(
                channelID: channelID,
                profileID: channel.profileID,
                connectionLeaseID: connectionLeaseID
            )
        }
    }

    private func resolveBrokerFailure(
        channelID: UUID,
        profileID: UUID,
        connectionLeaseID: UUID
    ) async {
        guard channels[channelID] != nil,
              channelLeaseIDs[channelID] == connectionLeaseID else { return }
        guard let forward = forwards[channelID], let forwarder else {
            scheduleProfileRevocation(
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
            return
        }
        guard forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
            scheduleProfileRevocation(
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
            return
        }

        do {
            try await forwarder.cancelForward(
                forward,
                for: profileID,
                expectedConnectionLeaseID: connectionLeaseID
            )
            if channels[channelID] != nil,
               channelLeaseIDs[channelID] == connectionLeaseID {
                finalizeClosedChannel(channelID: channelID)
            }
        } catch {
            scheduleProfileRevocation(
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
        }
    }

    private func retainBrokerFailure(channelID: UUID, error: any Error) {
        guard var channel = channels[channelID] else { return }
        brokers[channelID]?.deactivate()
        channel.status = .brokerFailed(reason: error.localizedDescription)
        channel.connectionCount = 0
        channels[channelID] = channel
        if let tunnelID = tunnelIDs[channelID] {
            tunnelManager.updateTunnelStatus(
                id: tunnelID,
                status: .failed(error.localizedDescription)
            )
        }
    }

    private func compensateForwardOpening(
        _ forward: RemoteConnectionProfile.PortForward,
        profileID: UUID,
        connectionLeaseID: UUID,
        forwarder: any PortForwarding
    ) async -> Bool {
        let cleanup = Task { @MainActor in
            try await forwarder.cancelForward(
                forward,
                for: profileID,
                expectedConnectionLeaseID: connectionLeaseID
            )
        }
        do {
            try await cleanup.value
            return true
        } catch {
            return false
        }
    }

    private func retainUncertainForwardOpening(
        channel: RelayChannel,
        token: RelayToken,
        forward: RemoteConnectionProfile.PortForward,
        connectionLeaseID: UUID,
        broker: any RelayAuthBrokering,
        reason: String
    ) {
        broker.deactivate()
        var retainedChannel = channel
        retainedChannel.connectionCount = 0
        retainedChannel.status = .closeFailed(
            reason: "Reverse forward cleanup is unconfirmed: \(reason)"
        )
        let tunnel = tunnelManager.addTunnel(
            forward: forward,
            for: channel.profileID,
            status: .failed(reason)
        )
        channels[channel.id] = retainedChannel
        tokens[channel.id] = token
        forwards[channel.id] = forward
        brokers[channel.id] = broker
        tunnelIDs[channel.id] = tunnel.id
        channelLeaseIDs[channel.id] = connectionLeaseID
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

    private func scheduleProfileRevocation(profileID: UUID, connectionLeaseID: UUID) {
        let key = ProfileLeaseKey(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        guard profileRevocationTasks[key] == nil else { return }
        let revocationID = UUID()
        let affectedChannelIDs = Set(
            channels.values.lazy
                .filter { channel in
                    channel.profileID == profileID
                        && self.channelLeaseIDs[channel.id] == connectionLeaseID
                }
                .map(\.id)
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let terminated = await self.profileSessionRevoker(
                profileID,
                connectionLeaseID
            )
            guard self.profileRevocationTasks[key]?.id == revocationID else {
                return
            }
            self.profileRevocationTasks.removeValue(forKey: key)
            if terminated {
                self.releaseChannelsAfterSessionTermination(
                    profileID: profileID,
                    connectionLeaseID: connectionLeaseID,
                    channelIDs: affectedChannelIDs
                )
            }
        }
        profileRevocationTasks[key] = ProfileRevocationTask(
            id: revocationID,
            task: task
        )
    }

    private func finalizeClosedChannel(channelID: UUID) {
        brokers[channelID]?.stop()
        if let tunnelID = tunnelIDs[channelID] {
            tunnelManager.removeTunnel(id: tunnelID)
        }

        channels.removeValue(forKey: channelID)
        tokens.removeValue(forKey: channelID)
        brokers.removeValue(forKey: channelID)
        forwards.removeValue(forKey: channelID)
        tunnelIDs.removeValue(forKey: channelID)
        channelLeaseIDs.removeValue(forKey: channelID)
        try? tokenStore.delete(channelID: channelID)
        auditLog?.log(.channelClosed(channelID: channelID))
    }
}
