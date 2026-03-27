// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHTunnelManager.swift - Manages active SSH port forwards.

import Foundation

// MARK: - Tunnel Status

/// Represents the current state of an SSH tunnel.
enum TunnelStatus: Equatable, Sendable {
    case active
    case failed(String)
    case pending
}

// MARK: - Active Tunnel

/// Represents a single active port forward associated with a remote profile.
struct ActiveTunnel: Identifiable, Sendable {

    /// Unique identifier for this tunnel instance.
    let id: UUID

    /// The remote profile that owns this tunnel.
    let profileID: UUID

    /// The port forwarding rule being applied.
    let forward: RemoteConnectionProfile.PortForward

    /// Current operational status.
    let status: TunnelStatus

    init(
        id: UUID = UUID(),
        profileID: UUID,
        forward: RemoteConnectionProfile.PortForward,
        status: TunnelStatus = .active
    ) {
        self.id = id
        self.profileID = profileID
        self.forward = forward
        self.status = status
    }
}

// MARK: - SSH Tunnel Manager

/// Manages the lifecycle of active SSH port forwards across all connected profiles.
///
/// Tracks which tunnels are running, detects port conflicts, and supports
/// per-profile bulk operations (e.g., removing all tunnels when disconnecting).
///
/// Must be accessed from the main actor since it publishes UI-bound state.
@MainActor
final class SSHTunnelManager: ObservableObject {

    // MARK: - Published State

    /// Active tunnels grouped by profile ID.
    @Published private(set) var activeTunnels: [UUID: [ActiveTunnel]] = [:]

    // MARK: - Tunnel Lifecycle

    /// Creates and registers a new active tunnel for the given profile.
    ///
    /// - Parameters:
    ///   - forward: The port forwarding rule to apply.
    ///   - profileID: The profile that owns this tunnel.
    /// - Returns: The newly created tunnel.
    @discardableResult
    func addTunnel(
        forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) -> ActiveTunnel {
        let tunnel = ActiveTunnel(
            profileID: profileID,
            forward: forward,
            status: .active
        )

        var tunnels = activeTunnels[profileID] ?? []
        tunnels.append(tunnel)
        activeTunnels[profileID] = tunnels

        return tunnel
    }

    /// Removes a tunnel by its unique identifier.
    ///
    /// - Parameter id: The tunnel ID to remove.
    /// - Returns: `true` if the tunnel was found and removed.
    @discardableResult
    func removeTunnel(id: UUID) -> Bool {
        for (profileID, tunnels) in activeTunnels {
            if let index = tunnels.firstIndex(where: { $0.id == id }) {
                var updated = tunnels
                updated.remove(at: index)
                if updated.isEmpty {
                    activeTunnels.removeValue(forKey: profileID)
                } else {
                    activeTunnels[profileID] = updated
                }
                return true
            }
        }
        return false
    }

    /// Removes all tunnels for a given profile.
    ///
    /// Called when disconnecting a profile to clean up all associated forwards.
    func removeAllTunnels(for profileID: UUID) {
        activeTunnels.removeValue(forKey: profileID)
    }

    /// Returns all tunnels for a given profile.
    func listTunnels(for profileID: UUID) -> [ActiveTunnel] {
        activeTunnels[profileID] ?? []
    }

    // MARK: - Conflict Detection

    /// Checks whether the given local port is already in use by an active tunnel.
    ///
    /// Prevents accidental double-binding of the same local port across
    /// different profiles or forwarding rules.
    func hasConflict(port: Int) -> Bool {
        for tunnels in activeTunnels.values {
            for tunnel in tunnels {
                if tunnel.forward.boundLocalPort == port {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Status Updates

    /// Updates the status of an existing tunnel.
    ///
    /// Used to mark a tunnel as failed when the underlying SSH forward
    /// encounters an error, or to transition from pending to active.
    func updateTunnelStatus(id: UUID, status: TunnelStatus) {
        for (profileID, tunnels) in activeTunnels {
            if let index = tunnels.firstIndex(where: { $0.id == id }) {
                let existing = tunnels[index]
                let updated = ActiveTunnel(
                    id: existing.id,
                    profileID: existing.profileID,
                    forward: existing.forward,
                    status: status
                )
                var mutableTunnels = tunnels
                mutableTunnels[index] = updated
                activeTunnels[profileID] = mutableTunnels
                return
            }
        }
    }
}
