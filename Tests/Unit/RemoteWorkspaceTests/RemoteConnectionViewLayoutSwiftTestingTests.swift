// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionViewLayoutSwiftTestingTests.swift - Remote workspace panel layout contracts.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("Remote connection view layout")
struct RemoteConnectionViewLayoutSwiftTestingTests {
    @Test("sub-panel picker shows every destination inside the dock width")
    func subPanelPickerFitsAllDestinationsInsideDockWidth() {
        let columns = RemoteConnectionView.subPanelPickerColumnCount(for: RemoteConnectionView.panelWidth)
        let rows = Int(ceil(Double(RemoteConnectionViewModel.SubPanel.allCases.count) / Double(columns)))

        #expect(columns >= 4)
        #expect(rows <= 2)
    }

    @Test("sub-panel picker keeps a usable fallback on narrow widths")
    func subPanelPickerKeepsUsableFallbackOnNarrowWidths() {
        #expect(RemoteConnectionView.subPanelPickerColumnCount(for: 0) == 1)
        #expect(RemoteConnectionView.subPanelPickerColumnCount(for: 220) >= 2)
    }

    @Test("quick connect creates a selectable transient profile")
    @MainActor
    func quickConnectCreatesSelectableTransientProfile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-quick-connect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let profileStore = RemoteProfileStore(basePath: tempDirectory.path)
        let connectionManager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let viewModel = RemoteConnectionViewModel(
            profileStore: profileStore,
            connectionManager: connectionManager,
            tunnelManager: SSHTunnelManager()
        )

        viewModel.loadProfiles()
        viewModel.quickConnectText = "cocxy@127.0.0.1:2222"

        viewModel.quickConnect()

        let profile = try #require(viewModel.profiles.first)
        #expect(viewModel.selectedProfileID == profile.id)
        #expect(profile.name == "cocxy@127.0.0.1:2222")
        #expect(profile.user == "cocxy")
        #expect(profile.host == "127.0.0.1")
        #expect(profile.port == 2222)
        #expect(viewModel.quickConnectText.isEmpty)
    }

    @Test("loading profiles selects an already connected host for tunnel suggestions")
    @MainActor
    func loadingProfilesSelectsAlreadyConnectedHostForTunnels() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-connected-profile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let profile = RemoteConnectionProfile(
            name: "ui-smoke-localhost",
            host: "127.0.0.1",
            user: "cocxy",
            port: 2222
        )
        let profileStore = RemoteProfileStore(basePath: tempDirectory.path)
        try profileStore.save(profile)
        let connectionManager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        await connectionManager.connect(profile: profile)
        let viewModel = RemoteConnectionViewModel(
            profileStore: profileStore,
            connectionManager: connectionManager,
            tunnelManager: SSHTunnelManager()
        )

        viewModel.loadProfiles()

        #expect(viewModel.selectedProfileID == profile.id)
        #expect(viewModel.selectedSubPanel == .tunnels)
    }
}
