// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandCorrectionsPreferencesSwiftTestingTests.swift - Preferences wiring coverage.

import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - command corrections round-trip")
@MainActor
struct CommandCorrectionsPreferencesSwiftTestingTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        commandCorrections: CommandCorrectionsConfig = .defaults
    ) -> (PreferencesViewModel, InMemoryProvider) {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            commandCorrections: commandCorrections,
            codeReview: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("load reflects saved command correction values")
    func loadReflectsSavedValues() {
        let (vm, _) = makeViewModel(
            commandCorrections: CommandCorrectionsConfig(
                enabled: false,
                editDistanceThreshold: 1,
                foundationModelsEnabled: false,
                agentFallback: true,
                autoShowOnFailure: false,
                showConfidenceBadge: false,
                maxSuggestionsShown: 5
            )
        )

        #expect(vm.commandCorrectionsEnabled == false)
        #expect(vm.commandCorrectionsEditDistanceThreshold == 1)
        #expect(vm.commandCorrectionsFoundationModelsEnabled == false)
        #expect(vm.commandCorrectionsAgentFallback == true)
        #expect(vm.commandCorrectionsAutoShowOnFailure == false)
        #expect(vm.commandCorrectionsShowConfidenceBadge == false)
        #expect(vm.commandCorrectionsMaxSuggestionsShown == 5)
    }

    @Test("toggle marks dirty and discard restores original")
    func toggleMarksDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        #expect(vm.hasUnsavedChanges == false)
        vm.commandCorrectionsEnabled = false
        #expect(vm.hasUnsavedChanges == true)
        vm.discardChanges()
        #expect(vm.commandCorrectionsEnabled == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save writes command corrections section")
    func saveWritesCommandCorrectionsSection() throws {
        let (vm, provider) = makeViewModel()
        vm.commandCorrectionsEnabled = false
        vm.commandCorrectionsEditDistanceThreshold = 1
        vm.commandCorrectionsFoundationModelsEnabled = false
        vm.commandCorrectionsAgentFallback = true
        vm.commandCorrectionsAutoShowOnFailure = false
        vm.commandCorrectionsShowConfidenceBadge = false
        vm.commandCorrectionsMaxSuggestionsShown = 5

        try vm.save()

        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("[command-corrections]") == true)
        #expect(provider.lastWrite?.contains("enabled = false") == true)
        #expect(provider.lastWrite?.contains("edit-distance-threshold = 1") == true)
        #expect(provider.lastWrite?.contains("agent-fallback = true") == true)
        #expect(provider.lastWrite?.contains("max-suggestions-shown = 5") == true)
    }
}
