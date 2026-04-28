// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraNotesIntegrationSwiftTestingTests.swift - Pin the wiring
// between `[notes].enabled`, `MainWindowController.toggleNotes()`,
// and the `onToggleNotes` callback the Aurora sidebar uses to render
// (or hide) the note tray button.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Aurora — Notes integration", .serialized)
struct AuroraNotesIntegrationSwiftTestingTests {

    private final class InMemoryNotesConfigProvider: ConfigFileProviding, @unchecked Sendable {
        private var content: String?

        init(content: String?) { self.content = content }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    /// Builds a `MainWindowController` whose `ConfigService` carries the
    /// supplied `[notes]` section. Other sections fall back to defaults
    /// so the test stays focused on the notes wiring.
    private func makeController(notesEnabled: Bool) -> MainWindowController {
        let toml = """
        [notes]
        enabled = \(notesEnabled)
        """
        let provider = InMemoryNotesConfigProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try? service.reload()
        return MainWindowController(bridge: MockTerminalEngine(), configService: service)
    }

    // MARK: - Controller defaults

    @Test("AuroraChromeController.onToggleNotes is nil by default so the sidebar tray omits the note button until the integration layer wires it")
    func onToggleNotesNilByDefault() {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )

        #expect(controller.onToggleNotes == nil)
    }

    @Test("AuroraChromeController.onToggleNotes invokes the supplied closure so the SwiftUI host can forward sidebar taps to the host")
    func onToggleNotesInvokesSuppliedClosure() {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        var fired = false
        controller.onToggleNotes = { fired = true }

        controller.onToggleNotes?()

        #expect(fired == true)
    }

    @Test("AuroraChromeController.onToggleNotes publishes so config hot-reload re-renders the tray button")
    func onToggleNotesPublishesForHotReload() {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        var published = false
        let cancellable = controller.objectWillChange.sink {
            published = true
        }

        controller.onToggleNotes = {}

        #expect(published == true)
        cancellable.cancel()
    }

    // MARK: - MainWindowController wiring

    @Test("refreshAuroraNotesAvailability assigns a non-nil closure when the user has notes enabled so the sidebar tray button shows up")
    func availabilityAssignsClosureWhenEnabled() {
        let mainController = makeController(notesEnabled: true)
        let auroraController = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )

        mainController.refreshAuroraNotesAvailability(on: auroraController)

        #expect(auroraController.onToggleNotes != nil)
        #expect(auroraController.notesSummariesProvider != nil)
        #expect(auroraController.onOpenNoteInWorkspace != nil)
    }

    @Test("refreshAuroraNotesAvailability clears every notes hook and stale summaries when the user disables notes so the whole sidebar feature disappears")
    func availabilityClearsHooksAndSummariesWhenDisabled() async throws {
        let mainController = makeController(notesEnabled: false)
        let auroraController = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        auroraController.workspaces = [
            Design.AuroraWorkspace(
                id: "alpha",
                name: "alpha",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: "id-alpha"
            )
        ]
        // Pre-populate the full hook surface to make the clearing observable.
        auroraController.onToggleNotes = {}
        auroraController.notesSummariesProvider = { _ in
            [
                "id-alpha": Design.AuroraWorkspaceNotesSummary(
                    workspaceID: "id-alpha",
                    count: 1,
                    recentNotes: []
                )
            ]
        }
        auroraController.onOpenNoteInWorkspace = { _, _ in }
        auroraController.refreshNotesSummaries()
        _ = try await waitForMap(
            on: auroraController,
            condition: { $0["id-alpha"]?.count == 1 },
            timeout: 1.0
        )

        mainController.refreshAuroraNotesAvailability(on: auroraController)

        #expect(auroraController.onToggleNotes == nil)
        #expect(auroraController.notesSummariesProvider == nil)
        #expect(auroraController.onOpenNoteInWorkspace == nil)
        let cleared = try await waitForMap(
            on: auroraController,
            condition: { $0.isEmpty },
            timeout: 1.0
        )
        #expect(cleared.isEmpty)
    }

    @Test("refreshAuroraNotesAvailability defaults to enabled when no config service is wired so a fresh window does not hide the button while bootstrapping")
    func availabilityFallsBackToEnabledWithoutConfig() {
        // A controller built without a configService should rely on
        // `NotesConfig.defaults.enabled` (true), which keeps the
        // affordance visible during the brief window between window
        // creation and config load on first launch.
        let mainController = MainWindowController(bridge: MockTerminalEngine())
        let auroraController = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )

        mainController.refreshAuroraNotesAvailability(on: auroraController)

        #expect(auroraController.onToggleNotes != nil)
    }

    // MARK: - Aurora summaries provider

    @Test("fetchAuroraNotesSummaries returns an empty map when notes are disabled so the sidebar hides every workspace section the moment the preference flips off")
    func fetchSummariesEmptyWhenNotesDisabled() async {
        let mainController = makeController(notesEnabled: false)

        let result = await mainController.fetchAuroraNotesSummaries(for: ["any-id"])

        #expect(result.isEmpty)
    }

    @Test("fetchAuroraNotesSummaries returns an empty map when the input set is empty so the controller never hits the disk for nothing")
    func fetchSummariesEmptyWhenInputEmpty() async {
        let mainController = makeController(notesEnabled: true)

        let result = await mainController.fetchAuroraNotesSummaries(for: [])

        #expect(result.isEmpty)
    }

    @Test("fetchAuroraNotesSummaries reads the live storage path so the sidebar mirrors what the user has on disk")
    func fetchSummariesReadsConfiguredStorageDirectory() async throws {
        // Stage a custom storage directory pre-populated with a note
        // for a specific workspace, then build a MainWindowController
        // whose config points at that directory. The fetch must surface
        // the seeded note's title and count.
        let storageRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-aurora-summaries-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: storageRoot) }

        let workspaceID = NoteWorkspaceID(rawValue: "alpha000000a")
        let store = NoteStore(storageRoot: storageRoot, format: .markdown, autoSaveInterval: 0)
        let seed = try await store.create(in: workspaceID, body: "# Hello")

        let toml = """
        [notes]
        enabled = true
        storage-dir = "\(storageRoot.path)"
        format = "markdown"
        """
        let provider = InMemoryNotesConfigProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let mainController = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )

        let result = await mainController.fetchAuroraNotesSummaries(
            for: [workspaceID.rawValue]
        )

        let summary = try #require(result[workspaceID.rawValue])
        #expect(summary.count == 1)
        #expect(summary.recentNotes.first?.id == seed.id.uuidString)
        #expect(summary.recentNotes.first?.title == "Hello")
    }

    // MARK: - Tab resolution

    @Test("tabForNotesWorkspace returns nil for an unknown identifier so a stale sidebar tap from a closed tab is silently dropped")
    func tabForNotesWorkspaceNilWhenUnknown() {
        let mainController = makeController(notesEnabled: true)

        let resolved = mainController.tabForNotesWorkspace(rawID: "not-a-known-workspace")

        #expect(resolved == nil)
    }

    // MARK: - Open note safety net

    @Test("openNote is a no-op when notes are disabled so a stale Aurora sidebar tap cannot resurface the overlay against the user's preference")
    func openNoteNoOpWhenNotesDisabled() {
        let mainController = makeController(notesEnabled: false)

        mainController.openNote(workspaceIDRaw: "ws", noteIDRaw: "note")

        #expect(mainController.isNotesVisible == false)
    }

    @Test("openNote is a no-op when no tab matches the workspace identifier so a sidebar refresh racing a tab close cannot crash the window")
    func openNoteNoOpWhenWorkspaceUnknown() {
        let mainController = makeController(notesEnabled: true)

        mainController.openNote(workspaceIDRaw: "absent000abc", noteIDRaw: "note")

        #expect(mainController.isNotesVisible == false)
    }

    private func waitForMap(
        on controller: AuroraChromeController,
        condition: @escaping ([String: Design.AuroraWorkspaceNotesSummary]) -> Bool,
        timeout: TimeInterval
    ) async throws -> [String: Design.AuroraWorkspaceNotesSummary] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(controller.notesByWorkspace) {
                return controller.notesByWorkspace
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw WaitError.timeout
    }

    private enum WaitError: Error { case timeout }
}
