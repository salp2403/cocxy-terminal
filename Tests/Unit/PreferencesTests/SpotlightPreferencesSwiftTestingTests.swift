// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SpotlightPreferencesSwiftTestingTests.swift - Preferences coverage for `[spotlight]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Spotlight round-trip")
@MainActor
struct SpotlightPreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(_ content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func makeViewModel(config: CocxyConfig = .defaults) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("init populates Spotlight fields from the saved config")
    func initPopulatesSpotlightFieldsFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            spotlight: SpotlightIndexConfig(
                enabled: true,
                indexCommandHistory: true,
                indexAgentConversations: false,
                includeCommandOutput: true,
                includeWorkingDirectories: false,
                includeToolMetadata: false
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.spotlightIndexingEnabled == true)
        #expect(vm.spotlightIndexCommandHistory == true)
        #expect(vm.spotlightIndexAgentConversations == false)
        #expect(vm.spotlightIncludeCommandOutput == true)
        #expect(vm.spotlightIncludeWorkingDirectories == false)
        #expect(vm.spotlightIncludeToolMetadata == false)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Spotlight fields marks Preferences dirty and discard restores")
    func changingSpotlightFieldsMarksDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        vm.spotlightIndexingEnabled = true
        vm.spotlightIndexCommandHistory = false
        vm.spotlightIndexAgentConversations = false
        vm.spotlightIncludeCommandOutput = true
        vm.spotlightIncludeWorkingDirectories = true
        vm.spotlightIncludeToolMetadata = true

        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.spotlightIndexingEnabled == false)
        #expect(vm.spotlightIndexCommandHistory == true)
        #expect(vm.spotlightIndexAgentConversations == true)
        #expect(vm.spotlightIncludeCommandOutput == false)
        #expect(vm.spotlightIncludeWorkingDirectories == false)
        #expect(vm.spotlightIncludeToolMetadata == false)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("disabling Spotlight keeps broad scopes documented but writes disabled")
    func disablingSpotlightWritesDisabledMasterSwitch() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            spotlight: SpotlightIndexConfig(enabled: true),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.spotlightIndexingEnabled = false

        let toml = vm.generateToml()
        #expect(toml.contains("[spotlight]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("index-command-history = true"))
        #expect(toml.contains("index-agent-conversations = true"))
    }

    @Test("save then reload preserves Spotlight fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.spotlightIndexingEnabled = true
        vm.spotlightIndexCommandHistory = true
        vm.spotlightIndexAgentConversations = true
        vm.spotlightIncludeCommandOutput = false
        vm.spotlightIncludeWorkingDirectories = true
        vm.spotlightIncludeToolMetadata = false
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.spotlight.enabled == true)
        #expect(service.current.spotlight.indexCommandHistory == true)
        #expect(service.current.spotlight.indexAgentConversations == true)
        #expect(service.current.spotlight.includeCommandOutput == false)
        #expect(service.current.spotlight.includeWorkingDirectories == true)
        #expect(service.current.spotlight.includeToolMetadata == false)
        #expect(vm.hasUnsavedChanges == false)
    }
}
