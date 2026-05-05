// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayPanelViewModelSwiftTestingTests.swift - UI state for local replay library.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Session Replay panel view model")
struct SessionReplayPanelViewModelSwiftTestingTests {
    @Test("refresh loads newest recordings and selects newest")
    func refreshLoadsNewestRecordingsAndSelectsNewest() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-list")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let older = try makeRecording(
            store: store,
            title: "Older build",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationNs: 1_000_000_000
        )
        let newer = try makeRecording(
            store: store,
            title: "Newer smoke",
            createdAt: Date(timeIntervalSince1970: 1_800_000_100),
            durationNs: 2_500_000_000
        )

        let viewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: nil,
            targetSurfaceProvider: { nil }
        )

        try viewModel.refresh()

        #expect(viewModel.recordings.map(\.id) == [newer.id, older.id])
        #expect(viewModel.selectedRecordingID == newer.id)
        #expect(viewModel.selectedRecording?.durationText == "00:02.500")
        #expect(viewModel.statusText == "2 recordings")
    }

    @Test("search result jumps update seek position")
    func searchResultJumpsUpdateSeekPosition() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-search")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let recording = try makeRecording(store: store, title: "Searchable")
        let viewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: nil,
            targetSurfaceProvider: { nil }
        )

        try viewModel.refresh()
        #expect(viewModel.selectedRecordingID == recording.id)

        viewModel.searchQuery = "swift test"
        try viewModel.searchSelectedRecording()

        #expect(viewModel.searchMatches.count == 1)
        #expect(viewModel.searchMatches[0].offsetNs == 1_250_000_000)

        viewModel.jumpToSearchMatch(viewModel.searchMatches[0])

        #expect(viewModel.seekNs == 1_250_000_000)
        #expect(viewModel.seekText == "00:01.250")
    }

    @Test("bookmark export and delete operate on selected recording")
    func bookmarkExportAndDeleteOperateOnSelectedRecording() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-actions")
        let exportRoot = try makeTemporaryDirectory(named: "session-replay-panel-export")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportRoot)
        }

        let store = SessionReplayStore(rootDirectory: root)
        let recording = try makeRecording(
            store: store,
            title: "Actions",
            durationNs: 1_500_000_000
        )
        let viewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: nil,
            targetSurfaceProvider: { nil }
        )

        try viewModel.refresh()
        viewModel.seekNs = 9_000_000_000
        viewModel.bookmarkLabel = "Failure line"
        try viewModel.addBookmarkAtSeek()

        #expect(viewModel.selectedRecording?.bookmarks.map(\.label) == ["Failure line"])
        #expect(viewModel.selectedRecording?.bookmarks.map(\.offsetText) == ["00:01.500"])
        #expect(viewModel.bookmarkLabel.isEmpty)

        let exportURL = exportRoot.appendingPathComponent("actions.cast")
        try viewModel.exportSelected(to: exportURL)

        #expect(try String(contentsOf: exportURL, encoding: .utf8) == sampleCast())
        #expect(viewModel.statusText == "Exported actions.cast")

        try viewModel.deleteSelected()

        #expect(viewModel.recordings.isEmpty)
        #expect(viewModel.selectedRecordingID == nil)
        #expect(throws: SessionReplayStoreError.recordingNotFound(recording.id)) {
            try store.recording(id: recording.id)
        }
    }

    @Test("delete all clears recordings selection and stored bundles")
    func deleteAllClearsRecordingsSelectionAndStoredBundles() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-delete-all")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let first = try makeRecording(store: store, title: "First")
        let second = try makeRecording(store: store, title: "Second")
        let viewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: nil,
            targetSurfaceProvider: { nil }
        )

        try viewModel.refresh()
        #expect(viewModel.recordings.count == 2)

        try viewModel.deleteAll()

        #expect(viewModel.recordings.isEmpty)
        #expect(viewModel.selectedRecordingID == nil)
        #expect(viewModel.statusText == "No recordings")
        #expect(throws: SessionReplayStoreError.recordingNotFound(first.id)) {
            try store.recording(id: first.id)
        }
        #expect(throws: SessionReplayStoreError.recordingNotFound(second.id)) {
            try store.recording(id: second.id)
        }
    }

    @Test("replay selected recording uses seek target and half speed")
    func replaySelectedRecordingUsesSeekTargetAndHalfSpeed() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-replay")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let recording = try makeRecording(store: store, title: "Replay")
        let targetSurface = SurfaceID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let playback = RecordingSessionReplayPanelPlayback()
        let viewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: playback,
            targetSurfaceProvider: { targetSurface }
        )

        try viewModel.refresh()
        viewModel.seekNs = 500_000_000
        viewModel.speedMultiplier = 0.5
        try viewModel.replaySelected()

        #expect(playback.requests == [
            RecordingSessionReplayPanelPlayback.Request(
                recordingID: recording.id,
                surfaceID: targetSurface,
                seekNs: 500_000_000,
                speedMultiplier: 0.5
            )
        ])
        #expect(viewModel.statusText == "Replaying Replay at 0.5x")
    }

    @Test("replay selected recording requires enabled config and target surface")
    func replaySelectedRecordingRequiresEnabledConfigAndTargetSurface() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-gates")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        _ = try makeRecording(store: store, title: "Gated")
        let playback = RecordingSessionReplayPanelPlayback()
        let disabledViewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: false),
            store: store,
            playback: playback,
            targetSurfaceProvider: { SurfaceID() }
        )
        let noSurfaceViewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: playback,
            targetSurfaceProvider: { nil }
        )

        try disabledViewModel.refresh()
        try noSurfaceViewModel.refresh()

        #expect(throws: SessionReplayPanelError.replayDisabled) {
            try disabledViewModel.replaySelected()
        }
        #expect(throws: SessionReplayPanelError.targetSurfaceUnavailable) {
            try noSurfaceViewModel.replaySelected()
        }
        #expect(playback.requests.isEmpty)
    }

    @Test("Spanish localizer updates Session Replay status copy")
    func spanishLocalizerUpdatesSessionReplayStatusCopy() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-panel-spanish")
        let exportRoot = try makeTemporaryDirectory(named: "session-replay-panel-spanish-export")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportRoot)
        }

        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let store = SessionReplayStore(rootDirectory: root)
        let recording = try makeRecording(store: store, title: "Demo")
        let viewModel = SessionReplayPanelViewModel(
            config: SessionReplayConfig(enabled: true),
            store: store,
            playback: nil,
            targetSurfaceProvider: { nil },
            localizer: spanish
        )

        try viewModel.refresh()

        #expect(viewModel.selectedRecordingID == recording.id)
        #expect(viewModel.statusText == "1 grabación")

        viewModel.searchQuery = "swift test"
        try viewModel.searchSelectedRecording()

        #expect(viewModel.statusText == "1 coincidencia")

        let exportURL = exportRoot.appendingPathComponent("demo.cast")
        try viewModel.exportSelected(to: exportURL)

        #expect(viewModel.statusText == "Exportado demo.cast")

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))

        #expect(viewModel.statusText == "Exported demo.cast")
    }

    @Test("delete-all Session Replay confirmation copy follows configured app language")
    func deleteAllSessionReplayConfirmationCopyFollowsConfiguredAppLanguage() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        let copy = SessionReplayPanelView.localizedDeleteAllRecordingsCopy(localizer: localizer)

        #expect(copy.messageText == "¿Eliminar todas las grabaciones?")
        #expect(copy.informativeText == "Esto elimina todas las grabaciones locales de Session Replay de esta Mac.")
        #expect(copy.primaryButton == "Eliminar todo")
        #expect(copy.secondaryButton == "Cancelar")

        let exportCopy = SessionReplayPanelView.localizedExportPanelCopy(localizer: localizer)
        #expect(exportCopy.title == "Exportar Session Replay")
        #expect(exportCopy.message == "Elige dónde guardar esta grabación.")
        #expect(exportCopy.prompt == "Exportar")
    }

    private func makeRecording(
        store: SessionReplayStore,
        title: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        durationNs: UInt64 = 1_500_000_000
    ) throws -> SessionReplayRecording {
        let prepared = try store.prepareRecording(
            title: title,
            surfaceID: SurfaceID(),
            createdAt: createdAt
        )
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        try store.finishRecording(
            id: prepared.recording.id,
            durationNs: durationNs,
            byteCount: sampleCast().utf8.count,
            updatedAt: createdAt.addingTimeInterval(Double(durationNs) / 1_000_000_000)
        )
        return try store.recording(id: prepared.recording.id)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func sampleCast() -> String {
        """
        {"version":2,"width":80,"height":24,"timestamp":1800000000,"env":{"TERM":"xterm-256color"}}
        [0.0,"o","hello world\\r\\n"]
        [1.25,"o","swift test --filter SessionReplay\\r\\n"]

        """
    }
}

@MainActor
private final class RecordingSessionReplayPanelPlayback: SessionReplayPlaybackControlling {
    struct Request: Equatable {
        let recordingID: UUID
        let surfaceID: SurfaceID
        let seekNs: UInt64
        let speedMultiplier: Float
    }

    private(set) var requests: [Request] = []

    func replay(
        recordingID: UUID,
        to surfaceID: SurfaceID,
        seekNs: UInt64,
        speedMultiplier: Float
    ) throws {
        requests.append(Request(
            recordingID: recordingID,
            surfaceID: surfaceID,
            seekNs: seekNs,
            speedMultiplier: speedMultiplier
        ))
    }
}
