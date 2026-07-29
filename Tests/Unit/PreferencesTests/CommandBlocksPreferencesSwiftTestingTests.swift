// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - command blocks round-trip")
@MainActor
struct CommandBlocksPreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?

        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        commandBlocks: CommandBlocksConfig = .defaults
    ) -> (PreferencesViewModel, InMemoryProvider) {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            commandBlocks: commandBlocks,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("load reflects saved command block values")
    func loadReflectsSavedValues() {
        let (viewModel, _) = makeViewModel(
            commandBlocks: CommandBlocksConfig(enabled: false, showOnlyOnHover: false)
        )

        #expect(!viewModel.commandBlocksEnabled)
        #expect(!viewModel.commandBlocksShowOnlyOnHover)
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("toggle marks dirty and discard restores original")
    func toggleMarksDirtyAndDiscardRestoresOriginal() {
        let (viewModel, _) = makeViewModel()

        viewModel.commandBlocksEnabled = false
        viewModel.commandBlocksShowOnlyOnHover = false
        #expect(viewModel.hasUnsavedChanges)

        viewModel.discardChanges()
        #expect(viewModel.commandBlocksEnabled)
        #expect(viewModel.commandBlocksShowOnlyOnHover)
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("save writes command blocks section")
    func saveWritesCommandBlocksSection() throws {
        let (viewModel, provider) = makeViewModel()
        viewModel.commandBlocksEnabled = false
        viewModel.commandBlocksShowOnlyOnHover = false

        try viewModel.save()

        #expect(!viewModel.hasUnsavedChanges)
        #expect(provider.lastWrite?.contains("""
        [command-blocks]
        enabled = false
        show-only-on-hover = false
        """) == true)
    }
}
