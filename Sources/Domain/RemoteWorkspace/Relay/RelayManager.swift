// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManager.swift - Multi-channel relay orchestrator.

import Foundation
import Combine

// MARK: - Relay Managing Protocol

/// Defines the public API for relay channel management.
@MainActor
protocol RelayManaging: AnyObject {
    func openChannel(config: RelayChannelConfig, profileID: UUID) throws -> RelayChannel
    func closeChannel(channelID: UUID)
    func closeAllChannels(profileID: UUID)
    func listChannels(profileID: UUID) -> [RelayChannel]
    func rotateToken(channelID: UUID)
    func updateACL(channelID: UUID, acl: RelayACL)
}

// MARK: - Relay Manager Implementation

/// Orchestrates relay channels: creates reverse tunnels, manages tokens,
/// and handles auto-cleanup on disconnect.
///
/// Each channel gets:
/// - A reverse SSH tunnel (`-R remotePort:localHost:localPort`)
/// - A unique `RelayToken` for HMAC authentication
/// - An optional expiration time for auto-close
@MainActor
final class RelayManagerImpl: RelayManaging, ObservableObject {

    // MARK: - Published State

    @Published private(set) var channels: [UUID: RelayChannel] = [:]
    @Published private(set) var tokens: [UUID: RelayToken] = [:]

    // MARK: - Dependencies

    private let tunnelManager: SSHTunnelManager
    private weak var forwarder: (any PortForwarding)?
    private let tokenStore: any RelayTokenStoring

    // MARK: - Auto-Cleanup

    /// Timer that checks for expired channels every 60 seconds.
    private var expirationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        tunnelManager: SSHTunnelManager,
        forwarder: any PortForwarding,
        tokenStore: any RelayTokenStoring = InMemoryTokenStore()
    ) {
        self.tunnelManager = tunnelManager
        self.forwarder = forwarder
        self.tokenStore = tokenStore
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
    func openChannel(config: RelayChannelConfig, profileID: UUID) throws -> RelayChannel {
        guard let forwarder else {
            throw SSHMultiplexerError.connectionFailed("Port forwarder unavailable")
        }

        // Create reverse tunnel.
        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: config.remotePort,
            localPort: config.localPort,
            localHost: config.localHost
        )
        try forwarder.forwardPort(forward, for: profileID)
        tunnelManager.addTunnel(forward: forward, for: profileID)

        // Create channel with fresh token.
        let channel = RelayChannel(
            profileID: profileID,
            name: config.name,
            localHost: config.localHost,
            localPort: config.localPort,
            remotePort: config.remotePort
        )
        let token = RelayToken.generate()

        channels[channel.id] = channel
        tokens[channel.id] = token

        // Persist token to Keychain.
        try? tokenStore.save(token: token, channelID: channel.id)

        return channel
    }

    // MARK: - Close Channel

    /// Closes a single relay channel and cancels its reverse tunnel.
    func closeChannel(channelID: UUID) {
        guard let channel = channels[channelID] else { return }

        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: channel.remotePort,
            localPort: channel.localPort,
            localHost: channel.localHost
        )
        try? forwarder?.cancelForward(forward, for: channel.profileID)

        channels.removeValue(forKey: channelID)
        tokens.removeValue(forKey: channelID)

        // Remove token from Keychain.
        try? tokenStore.delete(channelID: channelID)
    }

    /// Closes all channels for a given profile.
    ///
    /// Called when a profile disconnects to clean up all associated tunnels.
    func closeAllChannels(profileID: UUID) {
        let profileChannels = channels.values.filter { $0.profileID == profileID }
        for channel in profileChannels {
            closeChannel(channelID: channel.id)
        }
    }

    // MARK: - List Channels

    /// Returns all active channels for a given profile.
    func listChannels(profileID: UUID) -> [RelayChannel] {
        channels.values
            .filter { $0.profileID == profileID }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Token Management

    /// Rotates the token for a channel, invalidating the old one.
    func rotateToken(channelID: UUID) {
        guard tokens[channelID] != nil else { return }
        let newToken = RelayToken.generate()
        tokens[channelID] = newToken
        try? tokenStore.save(token: newToken, channelID: channelID)
    }

    /// Returns the current token for a channel.
    func token(for channelID: UUID) -> RelayToken? {
        tokens[channelID]
    }

    // MARK: - ACL Management

    /// Updates the access control list for an active channel.
    ///
    /// The new ACL applies to subsequent connections only;
    /// already-established connections are not affected.
    func updateACL(channelID: UUID, acl: RelayACL) {
        guard var channel = channels[channelID] else { return }
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
            connectionCount: channel.connectionCount
        )
        channels[channelID] = channel
    }

    // MARK: - Expiration Timer

    /// Starts a periodic timer that closes expired channels.
    private func startExpirationTimer() {
        expirationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                guard let self else { return }
                self.closeExpiredChannels()
            }
        }
    }

    /// Stops the expiration timer.
    func stopExpirationTimer() {
        expirationTask?.cancel()
        expirationTask = nil
    }

    /// Closes all channels that have passed their `expiresAt` time.
    private func closeExpiredChannels() {
        let expired = channels.values.filter { $0.isExpired }
        for channel in expired {
            closeChannel(channelID: channel.id)
        }
    }
}
