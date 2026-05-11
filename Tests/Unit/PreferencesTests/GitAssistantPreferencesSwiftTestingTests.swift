// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantPreferencesSwiftTestingTests.swift - Preferences coverage for `[git-assistant]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Git Assistant round-trip")
@MainActor
struct GitAssistantPreferencesSwiftTestingTests {
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

    @Test("init populates Git Assistant fields from the saved config")
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
            gitAssistant: GitAssistantSettings(
                enabled: false,
                defaultProvider: .google,
                maxDiffLines: 1_500,
                promptStyle: .minimal,
                autoGeneratePRBodyOnCreate: true,
                autoGenerateCommitMessageOnStage: true
            )
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.gitAssistantEnabled == false)
        #expect(vm.gitAssistantDefaultProvider == .google)
        #expect(vm.gitAssistantMaxDiffLines == 1_500)
        #expect(vm.gitAssistantPromptStyle == .minimal)
        #expect(vm.gitAssistantAutoGeneratePRBodyOnCreate == true)
        #expect(vm.gitAssistantAutoGenerateCommitMessageOnStage == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Git Assistant fields marks Preferences dirty")
    func changingFieldsMarksUnsaved() {
        let (vm, _) = makeViewModel()
        #expect(vm.hasUnsavedChanges == false)

        vm.gitAssistantDefaultProvider = .openai
        vm.gitAssistantMaxDiffLines = 1_200
        vm.gitAssistantPromptStyle = .descriptive

        #expect(vm.hasUnsavedChanges == true)
    }

    @Test("discard restores Git Assistant fields")
    func discardRestoresFields() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            gitAssistant: GitAssistantSettings(defaultProvider: .anthropic, maxDiffLines: 2_000)
        )
        let (vm, _) = makeViewModel(config: config)

        vm.gitAssistantEnabled = false
        vm.gitAssistantDefaultProvider = .openai
        vm.gitAssistantMaxDiffLines = 400
        vm.gitAssistantPromptStyle = .minimal
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.gitAssistantEnabled == true)
        #expect(vm.gitAssistantDefaultProvider == .anthropic)
        #expect(vm.gitAssistantMaxDiffLines == 2_000)
        #expect(vm.gitAssistantPromptStyle == .conventional)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save then reload preserves Git Assistant fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.gitAssistantEnabled = true
        vm.gitAssistantDefaultProvider = .openai
        vm.gitAssistantMaxDiffLines = 900
        vm.gitAssistantPromptStyle = .descriptive
        vm.gitAssistantAutoGeneratePRBodyOnCreate = true
        vm.gitAssistantAutoGenerateCommitMessageOnStage = true
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.gitAssistant.enabled == true)
        #expect(service.current.gitAssistant.defaultProvider == .openai)
        #expect(service.current.gitAssistant.maxDiffLines == 900)
        #expect(service.current.gitAssistant.promptStyle == .descriptive)
        #expect(service.current.gitAssistant.autoGeneratePRBodyOnCreate == true)
        #expect(service.current.gitAssistant.autoGenerateCommitMessageOnStage == true)
        #expect(vm.hasUnsavedChanges == false)
    }
}
