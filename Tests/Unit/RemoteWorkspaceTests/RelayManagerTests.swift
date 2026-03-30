// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManagerTests.swift - Tests for relay manager channel orchestration.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("RelayManager")
struct RelayManagerTests {

    // MARK: - Helpers

    @MainActor
    private func makeManager() -> (RelayManagerImpl, MockPortForwarder, SSHTunnelManager) {
        let forwarder = MockPortForwarder()
        let tunnelManager = SSHTunnelManager()
        let manager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: forwarder
        )
        return (manager, forwarder, tunnelManager)
    }

    // MARK: - Open/Close

    @Test("Open channel creates reverse tunnel")
    @MainActor func openChannel() throws {
        let (manager, forwarder, _) = makeManager()
        let profileID = UUID()

        let channel = try manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )

        #expect(channel.name == "api")
        #expect(channel.localPort == 3000)
        #expect(channel.remotePort == 9000)
        #expect(forwarder.forwardedPorts.count == 1)
    }

    @Test("Close channel removes tunnel")
    @MainActor func closeChannel() throws {
        let (manager, forwarder, _) = makeManager()
        let profileID = UUID()

        let channel = try manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )

        manager.closeChannel(channelID: channel.id)
        #expect(forwarder.cancelledPorts.count == 1)
        #expect(manager.listChannels(profileID: profileID).isEmpty)
    }

    @Test("Close all channels for profile")
    @MainActor func closeAllChannels() throws {
        let (manager, forwarder, _) = makeManager()
        let profileID = UUID()

        _ = try manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: profileID
        )
        _ = try manager.openChannel(
            config: RelayChannelConfig(name: "db", localPort: 5432, remotePort: 9001),
            profileID: profileID
        )

        manager.closeAllChannels(profileID: profileID)
        #expect(forwarder.cancelledPorts.count == 2)
        #expect(manager.listChannels(profileID: profileID).isEmpty)
    }

    @Test("List channels returns only for given profile")
    @MainActor func listChannels() throws {
        let (manager, forwarder, _) = makeManager()
        _ = forwarder // retain
        let profileA = UUID()
        let profileB = UUID()

        _ = try manager.openChannel(
            config: RelayChannelConfig(name: "a", localPort: 3000, remotePort: 9000),
            profileID: profileA
        )
        _ = try manager.openChannel(
            config: RelayChannelConfig(name: "b", localPort: 4000, remotePort: 9001),
            profileID: profileB
        )

        let channelsA = manager.listChannels(profileID: profileA)
        let channelsB = manager.listChannels(profileID: profileB)
        #expect(channelsA.count == 1)
        #expect(channelsA[0].name == "a")
        #expect(channelsB.count == 1)
        #expect(channelsB[0].name == "b")
    }

    @Test("Token rotation creates new token for channel")
    @MainActor func tokenRotation() throws {
        let (manager, forwarder, _) = makeManager()
        _ = forwarder // retain

        let channel = try manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: UUID()
        )

        let oldToken = manager.token(for: channel.id)
        manager.rotateToken(channelID: channel.id)
        let newToken = manager.token(for: channel.id)

        #expect(oldToken != nil)
        #expect(newToken != nil)
        #expect(oldToken?.secret != newToken?.secret)
    }

    @Test("Close non-existent channel is safe no-op")
    @MainActor func closeNonExistent() {
        let (manager, forwarder, _) = makeManager()
        manager.closeChannel(channelID: UUID())
        #expect(forwarder.cancelledPorts.isEmpty)
    }

    @Test("Open channel failure does not add channel")
    @MainActor func openFailure() {
        let (manager, forwarder, _) = makeManager()
        forwarder.shouldThrow = true

        do {
            _ = try manager.openChannel(
                config: RelayChannelConfig(name: "fail", localPort: 3000, remotePort: 9000),
                profileID: UUID()
            )
            Issue.record("Expected error")
        } catch {
            #expect(manager.listChannels(profileID: UUID()).isEmpty)
        }
    }
}
