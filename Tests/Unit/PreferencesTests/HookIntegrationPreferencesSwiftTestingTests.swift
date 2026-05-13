// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookIntegrationPreferencesSwiftTestingTests.swift - Preferences coverage for `[hooks]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Hooks round-trip")
@MainActor
struct HookIntegrationPreferencesSwiftTestingTests {
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

    @Test("init populates Hooks fields from saved config")
    func initPopulatesFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            hooks: HookIntegrationConfig(
                enabled: false,
                agents: [
                    .codex: HookIntegrationAgentConfig(enabled: false),
                    .opencode: HookIntegrationAgentConfig(enabled: true),
                ]
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.hooksIntegrationEnabled == false)
        #expect(vm.hookAgentEnabled(.codex) == false)
        #expect(vm.hookAgentEnabled(.opencode) == true)
        #expect(vm.availableHookAgents.count == 12)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Hooks fields marks Preferences dirty and discard restores them")
    func changingHooksMarksUnsavedAndDiscardRestores() {
        let (vm, _) = makeViewModel()
        #expect(vm.hasUnsavedChanges == false)

        vm.hooksIntegrationEnabled = false
        vm.setHookAgent(.codex, enabled: false)
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()
        #expect(vm.hooksIntegrationEnabled == true)
        #expect(vm.hookAgentEnabled(.codex) == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save then reload preserves Hooks config")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.hooksIntegrationEnabled = false
        vm.setHookAgent(.codex, enabled: false)
        vm.setHookAgent(.rovoDev, enabled: false)
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.hooks.enabled == false)
        #expect(service.current.hooks.isAgentEnabled(.codex) == false)
        #expect(service.current.hooks.isAgentEnabled(.rovoDev) == false)
        #expect(service.current.hooks.isAgentEnabled(.pi) == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("generated TOML writes Hooks section")
    func generatedTomlContainsHooksSection() {
        let (vm, _) = makeViewModel()

        let defaultToml = vm.generateToml()
        #expect(defaultToml.contains("[hooks]"))
        #expect(defaultToml.contains("[hooks.agents.codex]\nenabled = true"))

        vm.hooksIntegrationEnabled = false
        vm.setHookAgent(.codex, enabled: false)

        let toml = vm.generateToml()
        #expect(toml.contains("[hooks]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("[hooks.agents.codex]\nenabled = false"))
    }

    @Test("Hook preferences section renders agent rows")
    func sectionRendersAgentRows() {
        let (vm, _) = makeViewModel()
        let section = HookIntegrationPreferencesSection(
            viewModel: vm,
            saveStatus: .constant(nil)
        )

        _ = section.body
        #expect(vm.availableHookAgents.map(\.rawValue).contains("rovo-dev"))
    }
}
