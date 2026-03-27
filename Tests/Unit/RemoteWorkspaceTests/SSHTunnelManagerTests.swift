// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHTunnelManagerTests.swift - Tests for SSH tunnel lifecycle management.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - SSH Tunnel Manager Tests

@Suite("SSHTunnelManager")
struct SSHTunnelManagerTests {

    // MARK: - Add Tunnel

    @Test @MainActor func addTunnelCreatesActiveTunnel() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )

        let tunnel = manager.addTunnel(forward: forward, for: profileID)

        #expect(tunnel.profileID == profileID)
        #expect(tunnel.status == .active)
        #expect(manager.activeTunnels[profileID]?.count == 1)
    }

    @Test @MainActor func addMultipleTunnelsForSameProfile() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward1 = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )
        let forward2 = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )

        _ = manager.addTunnel(forward: forward1, for: profileID)
        _ = manager.addTunnel(forward: forward2, for: profileID)

        #expect(manager.activeTunnels[profileID]?.count == 2)
    }

    @Test @MainActor func addTunnelsForDifferentProfiles() {
        let manager = SSHTunnelManager()
        let profileID1 = UUID()
        let profileID2 = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )

        _ = manager.addTunnel(forward: forward, for: profileID1)
        _ = manager.addTunnel(forward: forward, for: profileID2)

        #expect(manager.activeTunnels.count == 2)
        #expect(manager.activeTunnels[profileID1]?.count == 1)
        #expect(manager.activeTunnels[profileID2]?.count == 1)
    }

    // MARK: - Remove Tunnel

    @Test @MainActor func removeTunnelDeletesFromList() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        let tunnel = manager.addTunnel(forward: forward, for: profileID)

        let removed = manager.removeTunnel(id: tunnel.id)

        #expect(removed == true)
        #expect(manager.activeTunnels[profileID]?.isEmpty ?? true)
    }

    @Test @MainActor func removeTunnelReturnsFalseWhenNotFound() {
        let manager = SSHTunnelManager()

        let removed = manager.removeTunnel(id: UUID())

        #expect(removed == false)
    }

    @Test @MainActor func removeTunnelOnlyRemovesTargetTunnel() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward1 = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )
        let forward2 = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        let tunnel1 = manager.addTunnel(forward: forward1, for: profileID)
        _ = manager.addTunnel(forward: forward2, for: profileID)

        _ = manager.removeTunnel(id: tunnel1.id)

        #expect(manager.activeTunnels[profileID]?.count == 1)
    }

    // MARK: - List Tunnels

    @Test @MainActor func listTunnelsReturnsProfileTunnels() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward1 = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )
        let forward2 = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)

        _ = manager.addTunnel(forward: forward1, for: profileID)
        _ = manager.addTunnel(forward: forward2, for: profileID)

        let tunnels = manager.listTunnels(for: profileID)

        #expect(tunnels.count == 2)
    }

    @Test @MainActor func listTunnelsReturnsEmptyForUnknownProfile() {
        let manager = SSHTunnelManager()

        let tunnels = manager.listTunnels(for: UUID())

        #expect(tunnels.isEmpty)
    }

    // MARK: - Conflict Detection

    @Test @MainActor func hasConflictDetectsLocalPortCollision() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        _ = manager.addTunnel(forward: forward, for: profileID)

        #expect(manager.hasConflict(port: 8080) == true)
    }

    @Test @MainActor func hasConflictDetectsDynamicPortCollision() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)
        _ = manager.addTunnel(forward: forward, for: profileID)

        #expect(manager.hasConflict(port: 1080) == true)
    }

    @Test @MainActor func hasConflictReturnsFalseForFreePort() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        _ = manager.addTunnel(forward: forward, for: profileID)

        #expect(manager.hasConflict(port: 9090) == false)
    }

    @Test @MainActor func hasConflictReturnsFalseWhenNoTunnels() {
        let manager = SSHTunnelManager()

        #expect(manager.hasConflict(port: 8080) == false)
    }

    // MARK: - Status Tracking

    @Test @MainActor func newTunnelHasActiveStatus() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )

        let tunnel = manager.addTunnel(forward: forward, for: profileID)

        #expect(tunnel.status == .active)
    }

    @Test @MainActor func updateTunnelStatusChangesStatus() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )
        let tunnel = manager.addTunnel(forward: forward, for: profileID)

        manager.updateTunnelStatus(id: tunnel.id, status: .failed("Connection reset"))

        let updated = manager.listTunnels(for: profileID).first
        #expect(updated?.status == .failed("Connection reset"))
    }

    @Test @MainActor func updateTunnelStatusIgnoresUnknownID() {
        let manager = SSHTunnelManager()

        manager.updateTunnelStatus(id: UUID(), status: .failed("error"))

        #expect(manager.activeTunnels.isEmpty)
    }

    // MARK: - Remove All for Profile

    @Test @MainActor func removeAllTunnelsForProfileClearsAll() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        _ = manager.addTunnel(
            forward: .local(localPort: 3000, remotePort: 3000), for: profileID
        )
        _ = manager.addTunnel(
            forward: .local(localPort: 8080, remotePort: 80), for: profileID
        )

        manager.removeAllTunnels(for: profileID)

        #expect(manager.activeTunnels[profileID] == nil)
    }

    @Test @MainActor func removeAllTunnelsDoesNotAffectOtherProfiles() {
        let manager = SSHTunnelManager()
        let profileID1 = UUID()
        let profileID2 = UUID()
        _ = manager.addTunnel(
            forward: .local(localPort: 3000, remotePort: 3000), for: profileID1
        )
        _ = manager.addTunnel(
            forward: .local(localPort: 8080, remotePort: 80), for: profileID2
        )

        manager.removeAllTunnels(for: profileID1)

        #expect(manager.activeTunnels[profileID1] == nil)
        #expect(manager.activeTunnels[profileID2]?.count == 1)
    }
}
