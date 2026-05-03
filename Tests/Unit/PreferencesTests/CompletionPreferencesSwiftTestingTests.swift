// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionPreferencesSwiftTestingTests.swift - Preferences coverage for `[completions]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — completions round-trip")
@MainActor
struct CompletionPreferencesSwiftTestingTests {

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

    @Test("init populates completion fields from saved config")
    func initPopulatesFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            completions: CompletionConfig(
                inlineAIEnabled: true,
                idleDelaySeconds: 0.35,
                maxContextUTF16Length: 8_192,
                enabledLanguageIDs: ["Swift", " python "]
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.completionInlineAIEnabled == true)
        #expect(vm.completionIdleDelaySeconds == 0.35)
        #expect(vm.completionMaxContextUTF16Length == 8_192)
        #expect(vm.completionEnabledLanguageIDs == Set(["python", "swift"]))
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("completion toggles and language edits mark Preferences dirty")
    func editsMarkUnsaved() {
        let (vm, _) = makeViewModel()

        vm.completionInlineAIEnabled = true
        vm.setCompletionLanguage(" Swift ", enabled: false)
        vm.setCompletionLanguage("go", enabled: true)

        #expect(vm.hasUnsavedChanges == true)
        #expect(vm.isCompletionLanguageEnabled("SWIFT") == false)
        #expect(vm.isCompletionLanguageEnabled("go") == true)
    }

    @Test("discard restores completion fields")
    func discardRestoresCompletionFields() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            completions: CompletionConfig(inlineAIEnabled: true, enabledLanguageIDs: ["swift"]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.completionInlineAIEnabled = false
        vm.setCompletionLanguage("python", enabled: true)
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.hasUnsavedChanges == false)
        #expect(vm.completionInlineAIEnabled == true)
        #expect(vm.completionEnabledLanguageIDs == Set(["swift"]))
    }

    @Test("save then reload preserves completion fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.completionInlineAIEnabled = true
        vm.completionIdleDelaySeconds = 0.4
        vm.completionMaxContextUTF16Length = 7_680
        vm.completionEnabledLanguageIDs = []
        vm.setCompletionLanguage("swift", enabled: true)
        vm.setCompletionLanguage("python", enabled: true)

        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.completions.inlineAIEnabled == true)
        #expect(service.current.completions.idleDelaySeconds == 0.4)
        #expect(service.current.completions.maxContextUTF16Length == 7_680)
        #expect(service.current.completions.enabledLanguageIDs == ["python", "swift"])
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("generated TOML writes completion section from Preferences")
    func generatedTomlContainsCompletionSection() {
        let (vm, _) = makeViewModel()

        let defaultToml = vm.generateToml()
        #expect(defaultToml.contains("[completions]"))
        #expect(defaultToml.contains("inline-ai = false"))
        #expect(defaultToml.contains("provider = \"foundation-models-on-device\""))

        vm.completionInlineAIEnabled = true
        vm.completionEnabledLanguageIDs = ["swift"]
        let toml = vm.generateToml()

        #expect(toml.contains("inline-ai = true"))
        #expect(toml.contains("enabled-languages = [\"swift\"]"))
    }
}
