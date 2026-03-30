// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayChannel.swift - Runtime relay channel model and serializable config.

import Foundation

// MARK: - Relay Channel (Runtime)

/// Runtime model for an active relay channel.
///
/// Represents a reverse SSH tunnel with ACL-gated access, token auth,
/// and optional auto-expiration. This is the in-memory, live representation.
/// For serializable config, see `RelayChannelConfig`.
struct RelayChannel: Identifiable, Sendable {

    /// Unique identifier for this channel instance.
    let id: UUID

    /// The remote profile that owns this channel.
    let profileID: UUID

    /// Human-readable name (e.g., "api-service", "db-tunnel").
    let name: String

    /// Local host to forward traffic to.
    let localHost: String

    /// Local port of the service being exposed.
    let localPort: Int

    /// Remote port on the server (assigned by SSH `-R`).
    let remotePort: Int

    /// Access control list for this channel.
    let acl: RelayACL

    /// When this channel should auto-expire (nil = never).
    let expiresAt: Date?

    /// Number of currently active connections through this channel.
    var connectionCount: Int

    init(
        id: UUID = UUID(),
        profileID: UUID,
        name: String,
        localHost: String = "localhost",
        localPort: Int,
        remotePort: Int,
        acl: RelayACL = RelayACL(),
        expiresAt: Date? = nil,
        connectionCount: Int = 0
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.localHost = localHost
        self.localPort = localPort
        self.remotePort = remotePort
        self.acl = acl
        self.expiresAt = expiresAt
        self.connectionCount = connectionCount
    }

    /// Whether this channel has passed its expiration time.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - Relay Channel Config (Serializable)

/// Lightweight, serializable configuration for a relay channel.
///
/// Stored in `RemoteConnectionProfile.relayChannels` as a persistent
/// blueprint for channels that should be opened on connection.
/// Unlike `RelayChannel`, this has no runtime state (connection count,
/// token, etc.).
struct RelayChannelConfig: Codable, Sendable, Equatable {

    /// Human-readable name for the channel.
    let name: String

    /// Local host to forward to (default "localhost").
    let localHost: String

    /// Local port of the service to expose.
    let localPort: Int

    /// Remote port on the server.
    let remotePort: Int

    init(
        name: String,
        localHost: String = "localhost",
        localPort: Int,
        remotePort: Int
    ) {
        self.name = name
        self.localHost = localHost
        self.localPort = localPort
        self.remotePort = remotePort
    }
}
