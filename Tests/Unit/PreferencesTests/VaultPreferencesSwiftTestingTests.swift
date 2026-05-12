// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultPreferencesSwiftTestingTests.swift - Preferences coverage for `[vault]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Vault round-trip")
@MainActor
struct VaultPreferencesSwiftTestingTests {
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

    @Test("init populates Vault fields from saved config")
    func initPopulatesFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            vault: VaultConfig(
                enabled: true,
                autoResumeOnLaunch: true,
                autoResumeOnRestore: true,
                confirmBeforeResume: false,
                encryptedStorage: true,
                sessionRetentionDays: 12,
                agents: [
                    "codex": VaultAgentConfig(enabled: false),
                    "local-agent": VaultAgentConfig(
                        enabled: true,
                        detectProcess: "local-agent",
                        resumeCommand: "local-agent resume {session_id}"
                    ),
                ]
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.vaultEnabled == true)
        #expect(vm.vaultAutoResumeOnLaunch == true)
        #expect(vm.vaultAutoResumeOnRestore == true)
        #expect(vm.vaultConfirmBeforeResume == false)
        #expect(vm.vaultSessionRetentionDays == 12)
        #expect(vm.vaultAgentEnabled("codex") == false)
        #expect(vm.vaultAgentEnabled("local-agent") == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Vault fields marks Preferences dirty")
    func changingVaultFieldsMarksUnsaved() {
        let (vm, _) = makeViewModel()
        #expect(vm.hasUnsavedChanges == false)

        vm.vaultEnabled = true
        vm.vaultAutoResumeOnRestore = true
        vm.vaultSessionRetentionDays = 5
        vm.setVaultAgent("codex", enabled: false)

        #expect(vm.hasUnsavedChanges == true)
    }

    @Test("discard restores Vault fields")
    func discardRestoresVaultFields() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            vault: VaultConfig(
                enabled: true,
                autoResumeOnLaunch: true,
                autoResumeOnRestore: true,
                confirmBeforeResume: false,
                encryptedStorage: true,
                sessionRetentionDays: 7,
                agents: ["codex": VaultAgentConfig(enabled: false)]
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.vaultEnabled = false
        vm.vaultAutoResumeOnLaunch = false
        vm.vaultConfirmBeforeResume = true
        vm.vaultSessionRetentionDays = 90
        vm.setVaultAgent("codex", enabled: true)
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.vaultEnabled == true)
        #expect(vm.vaultAutoResumeOnLaunch == true)
        #expect(vm.vaultAutoResumeOnRestore == true)
        #expect(vm.vaultConfirmBeforeResume == false)
        #expect(vm.vaultSessionRetentionDays == 7)
        #expect(vm.vaultAgentEnabled("codex") == false)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save then reload preserves Vault config")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.vaultEnabled = true
        vm.vaultAutoResumeOnRestore = true
        vm.vaultConfirmBeforeResume = false
        vm.vaultSessionRetentionDays = 45
        vm.setVaultAgent("codex", enabled: false)
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.vault.enabled == true)
        #expect(service.current.vault.autoResumeOnRestore == true)
        #expect(service.current.vault.confirmBeforeResume == false)
        #expect(service.current.vault.sessionRetentionDays == 45)
        #expect(service.current.vault.agents["codex"]?.enabled == false)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("generated TOML writes the Vault section")
    func generatedTomlContainsVaultSection() {
        let (vm, _) = makeViewModel()

        let defaultToml = vm.generateToml()
        #expect(defaultToml.contains("[vault]"))
        #expect(defaultToml.contains("enabled = false"))
        #expect(defaultToml.contains("[vault.agents.codex]\nenabled = true"))

        vm.vaultEnabled = true
        vm.vaultAutoResumeOnLaunch = true
        vm.setVaultAgent("codex", enabled: false)

        let toml = vm.generateToml()
        #expect(toml.contains("[vault]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("auto-resume-on-launch = true"))
        #expect(toml.contains("[vault.agents.codex]\nenabled = false"))
    }
}
