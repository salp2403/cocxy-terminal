// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UXPolishPreferencesSwiftTestingTests.swift - Preferences wiring coverage.

import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - UX polish round-trip")
@MainActor
struct UXPolishPreferencesSwiftTestingTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        uxPolish: UXPolishConfig = .defaults
    ) -> (PreferencesViewModel, InMemoryProvider) {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            uxPolish: uxPolish,
            codeReview: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("load reflects saved UX polish values")
    func loadReflectsSavedValues() {
        let (vm, _) = makeViewModel(
            uxPolish: UXPolishConfig(
                alwaysShowShortcutHints: true,
                shortcutHintDebugOverlay: true,
                shortcutHintOffsetX: 7,
                shortcutHintOffsetY: -3,
                shortcutHintScale: 1.1
            )
        )

        #expect(vm.alwaysShowShortcutHints == true)
        #expect(vm.shortcutHintDebugOverlay == true)
        #expect(vm.shortcutHintOffsetX == 7)
        #expect(vm.shortcutHintOffsetY == -3)
        #expect(vm.shortcutHintScale == 1.1)
    }

    @Test("toggle marks unsaved changes and discard restores original")
    func toggleMarksDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        #expect(vm.hasUnsavedChanges == false)
        vm.alwaysShowShortcutHints = true
        #expect(vm.hasUnsavedChanges == true)
        vm.discardChanges()
        #expect(vm.alwaysShowShortcutHints == false)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save writes UX polish section and resets dirty state")
    func saveWritesUXPolishSection() throws {
        let (vm, provider) = makeViewModel()
        vm.alwaysShowShortcutHints = true
        vm.shortcutHintDebugOverlay = true
        vm.shortcutHintOffsetX = 10
        vm.shortcutHintOffsetY = -6
        vm.shortcutHintScale = 1.2

        try vm.save()

        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("[ux-polish]") == true)
        #expect(provider.lastWrite?.contains("always-show-shortcut-hints = true") == true)
        #expect(provider.lastWrite?.contains("shortcut-hint-debug-overlay = true") == true)
        #expect(provider.lastWrite?.contains("shortcut-hint-offset-x = 10") == true)
        #expect(provider.lastWrite?.contains("shortcut-hint-offset-y = -6") == true)
        #expect(provider.lastWrite?.contains("shortcut-hint-scale = 1.2") == true)
    }
}
