// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentModePreferencesSwiftTestingTests.swift - Preferences coverage for `[agent]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Agent Mode round-trip")
@MainActor
struct AgentModePreferencesSwiftTestingTests {

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

    private func makeViewModelWithSecrets(
        config: CocxyConfig = .defaults
    ) -> (PreferencesViewModel, InMemoryProvider, AgentSecrets) {
        let provider = InMemoryProvider()
        let secrets = AgentSecrets(store: InMemoryAgentSecretStore())
        let vm = PreferencesViewModel(
            config: config,
            fileProvider: provider,
            agentSecrets: secrets
        )
        return (vm, provider, secrets)
    }

    @Test("init populates Agent Mode fields from the saved config")
    func initPopulatesFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            agent: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                autoMode: true,
                maxIterations: 14,
                conversationStorageDir: "~/.config/cocxy/custom-agent"
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.agentModeEnabled == true)
        #expect(vm.agentPreferredProvider == .openai)
        #expect(vm.agentAutoMode == true)
        #expect(vm.agentMaxIterations == 14)
        #expect(vm.agentConversationStorageDir == "~/.config/cocxy/custom-agent")
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Agent Mode fields marks Preferences dirty")
    func changingAgentModeFieldsMarksUnsaved() {
        let (vm, _) = makeViewModel()
        #expect(vm.hasUnsavedChanges == false)

        vm.agentModeEnabled = true
        vm.agentPreferredProvider = .google
        vm.agentMaxIterations = 10

        #expect(vm.hasUnsavedChanges == true)
    }

    @Test("discard restores Agent Mode fields")
    func discardRestoresAgentModeFields() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            agent: AgentModeConfig(
                enabled: true,
                preferredProvider: .anthropic,
                maxIterations: 12
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.agentModeEnabled = false
        vm.agentPreferredProvider = .openai
        vm.agentAutoMode = true
        vm.agentMaxIterations = 3
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.agentModeEnabled == true)
        #expect(vm.agentPreferredProvider == .anthropic)
        #expect(vm.agentAutoMode == false)
        #expect(vm.agentMaxIterations == 12)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save then reload preserves Agent Mode fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.agentModeEnabled = true
        vm.agentPreferredProvider = .google
        vm.agentAutoMode = true
        vm.agentMaxIterations = 15
        vm.agentConversationStorageDir = "~/.config/cocxy/agent/custom"
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.agent.enabled == true)
        #expect(service.current.agent.preferredProvider == .google)
        #expect(service.current.agent.autoMode == true)
        #expect(service.current.agent.maxIterations == 15)
        #expect(service.current.agent.conversationStorageDir == "~/.config/cocxy/agent/custom")
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save normalizes empty Agent Mode storage and clears dirty state")
    func saveNormalizesEmptyStorageAndClearsDirtyState() throws {
        let (vm, provider) = makeViewModel()

        vm.agentModeEnabled = true
        vm.agentConversationStorageDir = "   "
        #expect(vm.hasUnsavedChanges == true)

        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.agent.conversationStorageDir == AgentModeConfig.defaults.conversationStorageDir)
        #expect(vm.agentConversationStorageDir == AgentModeConfig.defaults.conversationStorageDir)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("saving Agent provider key stores trimmed value outside config dirty state")
    func savingProviderKeyStoresTrimmedValueOutsideConfigDirtyState() throws {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            agent: AgentModeConfig(preferredProvider: .openai),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _, secrets) = makeViewModelWithSecrets(config: config)

        vm.agentAPIKeyDraft = "  user-openai-key  "
        try vm.saveAgentAPIKeyDraft(for: .openai)

        #expect(try secrets.apiKey(for: .openai) == "user-openai-key")
        #expect(vm.agentAPIKeyDraft.isEmpty)
        #expect(vm.agentAPIKeyStatus == "OpenAI API key saved.")
        #expect(vm.hasSavedAgentAPIKey(for: .openai) == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("Foundation Models never exposes API key storage from Preferences")
    func foundationModelsNeverExposesAPIKeyStorage() {
        let (vm, _, _) = makeViewModelWithSecrets()

        vm.agentAPIKeyDraft = "not-needed"

        #expect(throws: AgentSecretError.providerDoesNotUseAPIKey(.foundationModelsOnDevice)) {
            try vm.saveAgentAPIKeyDraft(for: .foundationModelsOnDevice)
        }
        #expect(vm.hasSavedAgentAPIKey(for: .foundationModelsOnDevice) == false)
    }

    @Test("deleting Agent provider key removes it from local secrets")
    func deletingProviderKeyRemovesLocalSecret() throws {
        let (vm, _, secrets) = makeViewModelWithSecrets()
        try secrets.saveAPIKey("user-google-key", for: .google)
        #expect(vm.hasSavedAgentAPIKey(for: .google) == true)

        try vm.deleteAgentAPIKey(for: .google)

        #expect(try secrets.apiKey(for: .google) == nil)
        #expect(vm.agentAPIKeyStatus == "Google API key deleted.")
        #expect(vm.hasSavedAgentAPIKey(for: .google) == false)
    }

    @Test("generated TOML writes the Agent Mode section")
    func generatedTomlContainsAgentSection() {
        let (vm, _) = makeViewModel()

        let defaultToml = vm.generateToml()
        #expect(defaultToml.contains("[agent]"))
        #expect(defaultToml.contains("enabled = false"))
        #expect(defaultToml.contains("preferred-provider = \"foundation-models-on-device\""))
        #expect(defaultToml.contains("auto-mode = false"))

        vm.agentModeEnabled = true
        vm.agentPreferredProvider = .openai
        vm.agentAutoMode = true
        vm.agentMaxIterations = 200

        let toml = vm.generateToml()
        #expect(toml.contains("[agent]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("preferred-provider = \"openai\""))
        #expect(toml.contains("auto-mode = true"))
        #expect(toml.contains("max-iterations = 50"))
    }
}
