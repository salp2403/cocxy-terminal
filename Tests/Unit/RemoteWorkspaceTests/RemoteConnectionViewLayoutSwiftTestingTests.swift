// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionViewLayoutSwiftTestingTests.swift - Remote workspace panel layout contracts.

import Testing
import Combine
import Foundation
@testable import CocxyTerminal

private final class FailingRemoteProfileStore: RemoteProfileStoring, @unchecked Sendable {
    func loadAll() throws -> [RemoteConnectionProfile] { [] }

    func save(_ profile: RemoteConnectionProfile) throws {
        throw RemoteProfileStoreError.saveFailed("disk full")
    }

    func delete(id: UUID) throws {}

    func findByName(_ name: String) throws -> RemoteConnectionProfile? { nil }

    func findByGroup(_ group: String) throws -> [RemoteConnectionProfile] { [] }
}

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

    @Test("externally initiated connection changes refresh the remote workspace UI")
    @MainActor
    func externalConnectionChangesRefreshRemoteWorkspaceUI() async {
        let connectionManager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let viewModel = RemoteConnectionViewModel(
            profileStore: MockRemoteProfileStore(),
            connectionManager: connectionManager,
            tunnelManager: SSHTunnelManager()
        )
        let profile = RemoteConnectionProfile(name: "CLI connection", host: "127.0.0.1")
        var publishedUpdates = 0
        let subscription = viewModel.objectWillChange.sink {
            publishedUpdates += 1
        }

        await connectionManager.connect(profile: profile)

        #expect(publishedUpdates >= 2)
        #expect(viewModel.connectionState(for: profile.id) == .connected(latencyMs: nil))
        withExtendedLifetime(subscription) {}
    }

    @Test("connection refreshes preserve unsaved profile editor state")
    @MainActor
    func connectionRefreshPreservesProfileEditorState() async throws {
        let connectionManager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let viewModel = RemoteConnectionViewModel(
            profileStore: MockRemoteProfileStore(),
            connectionManager: connectionManager,
            tunnelManager: SSHTunnelManager()
        )
        let profile = RemoteConnectionProfile(name: "Original", host: "127.0.0.1")
        viewModel.presentEditProfile(profile)
        let editor = try #require(viewModel.profileEditorViewModel)
        editor.name = "Unsaved name"
        editor.host = "unsaved.internal"

        await connectionManager.connect(profile: profile)

        #expect(viewModel.profileEditorViewModel === editor)
        #expect(editor.name == "Unsaved name")
        #expect(editor.host == "unsaved.internal")
        #expect(viewModel.isEditorPresented)
    }

    @Test("duplicate profile reports persistence failures")
    @MainActor
    func duplicateProfileReportsPersistenceFailures() throws {
        let connectionManager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let viewModel = RemoteConnectionViewModel(
            profileStore: FailingRemoteProfileStore(),
            connectionManager: connectionManager,
            tunnelManager: SSHTunnelManager(),
            localizer: AppLocalizer(languagePreference: .english)
        )
        let profile = RemoteConnectionProfile(name: "Production", host: "prod.internal")

        #expect(!viewModel.duplicateProfile(profile))
        let message = try #require(viewModel.profileActionErrorMessage)
        #expect(message.contains("Production"))
        #expect(message.contains("disk full"))

        viewModel.dismissProfileActionError()
        #expect(viewModel.profileActionErrorMessage == nil)
    }
}
