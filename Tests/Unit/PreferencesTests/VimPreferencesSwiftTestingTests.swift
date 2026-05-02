// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VimPreferencesSwiftTestingTests.swift - Preferences coverage for `[vim]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — Vim round-trip")
@MainActor
struct VimPreferencesSwiftTestingTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func makeViewModel(config: CocxyConfig = .defaults) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        let vm = PreferencesViewModel(config: config, fileProvider: provider)
        return (vm, provider)
    }

    @Test("init populates Vim mode from the saved config")
    func initPopulatesFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            vim: VimConfig(enabled: true)
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.vimEnabled == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Vim mode marks Preferences dirty")
    func vimToggleMarksUnsaved() {
        let (vm, _) = makeViewModel()
        #expect(vm.hasUnsavedChanges == false)

        vm.vimEnabled = true

        #expect(vm.hasUnsavedChanges == true)
    }

    @Test("discard restores Vim mode")
    func discardRestoresVimMode() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            vim: VimConfig(enabled: true)
        )
        let (vm, _) = makeViewModel(config: config)

        vm.vimEnabled = false
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.vimEnabled == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save then reload preserves Vim mode")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.vimEnabled = true
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.vim.enabled == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("generated TOML writes the Vim section")
    func generatedTomlContainsVimSection() {
        let (vm, _) = makeViewModel()

        let defaultToml = vm.generateToml()
        #expect(defaultToml.contains("[vim]\nenabled = false"))

        vm.vimEnabled = true

        let toml = vm.generateToml()
        #expect(toml.contains("[vim]\nenabled = true"))
    }
}
