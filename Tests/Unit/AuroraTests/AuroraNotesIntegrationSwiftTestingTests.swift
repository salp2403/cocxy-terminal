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
    }

    @Test("refreshAuroraNotesAvailability clears the closure when the user has notes disabled so the sidebar tray button disappears")
    func availabilityClearsClosureWhenDisabled() {
        let mainController = makeController(notesEnabled: false)
        let auroraController = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        // Pre-populate with a closure to make the clearing observable.
        auroraController.onToggleNotes = {}

        mainController.refreshAuroraNotesAvailability(on: auroraController)

        #expect(auroraController.onToggleNotes == nil)
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
}
