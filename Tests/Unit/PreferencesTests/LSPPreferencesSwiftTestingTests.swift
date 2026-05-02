// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPPreferencesSwiftTestingTests.swift - Preferences coverage for `[lsp]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — LSP round-trip")
@MainActor
struct LSPPreferencesSwiftTestingTests {

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

    @Test("init populates LSP fields from the saved config")
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
            lsp: LSPConfig(enabled: true, enabledLanguageIDs: ["Swift", " go "])
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.lspEnabled == true)
        #expect(vm.lspEnabledLanguageIDs == Set(["go", "swift"]))
        #expect(vm.availableLSPLanguages.map(\.languageID).contains("swift"))
        #expect(vm.availableLSPLanguages.map(\.languageID).contains("typescript"))
    }

    @Test("changing LSP master switch marks Preferences dirty")
    func lspMasterChangeMarksUnsaved() {
        let (vm, _) = makeViewModel()
        #expect(vm.hasUnsavedChanges == false)

        vm.lspEnabled = true

        #expect(vm.hasUnsavedChanges == true)
    }

    @Test("language toggle normalizes ids and marks Preferences dirty")
    func languageToggleNormalizesIDs() {
        let (vm, _) = makeViewModel()

        vm.setLSPLanguage(" Swift ", enabled: true)
        vm.setLSPLanguage("go", enabled: true)
        vm.setLSPLanguage("swift", enabled: true)

        #expect(vm.lspEnabledLanguageIDs == Set(["go", "swift"]))
        #expect(vm.isLSPLanguageEnabled("SWIFT"))
        #expect(vm.hasUnsavedChanges == true)

        vm.setLSPLanguage("swift", enabled: false)

        #expect(vm.lspEnabledLanguageIDs == Set(["go"]))
        #expect(vm.isLSPLanguageEnabled("swift") == false)
    }

    @Test("discard restores LSP fields")
    func discardRestoresLSPFields() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            lsp: LSPConfig(enabled: true, enabledLanguageIDs: ["swift", "python"])
        )
        let (vm, _) = makeViewModel(config: config)

        vm.lspEnabled = false
        vm.setLSPLanguage("go", enabled: true)
        vm.setLSPLanguage("python", enabled: false)
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.hasUnsavedChanges == false)
        #expect(vm.lspEnabled == true)
        #expect(vm.lspEnabledLanguageIDs == Set(["python", "swift"]))
    }

    @Test("save then reload preserves LSP fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.lspEnabled = true
        vm.setLSPLanguage("swift", enabled: true)
        vm.setLSPLanguage("go", enabled: true)

        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()
        #expect(service.current.lsp.enabled == true)
        #expect(service.current.lsp.enabledLanguageIDs == ["go", "swift"])
    }

    @Test("generated TOML writes disabled default and sorted enabled languages")
    func generatedTomlContainsLSPSection() {
        let (vm, _) = makeViewModel()

        let defaultToml = vm.generateToml()
        #expect(defaultToml.contains("[lsp]"))
        #expect(defaultToml.contains("enabled-languages = []"))

        vm.lspEnabled = true
        vm.setLSPLanguage("swift", enabled: true)
        vm.setLSPLanguage("go", enabled: true)

        let toml = vm.generateToml()
        #expect(toml.contains("[lsp]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("enabled-languages = [\"go\", \"swift\"]"))
    }
}
