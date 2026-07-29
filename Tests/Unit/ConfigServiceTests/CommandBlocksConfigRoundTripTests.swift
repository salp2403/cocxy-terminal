// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("ConfigService - command blocks TOML round-trip")
struct CommandBlocksConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test("defaults enable unobtrusive command blocks")
    func defaultsEnableUnobtrusiveCommandBlocks() {
        #expect(CommandBlocksConfig.defaults.enabled)
        #expect(CommandBlocksConfig.defaults.showOnlyOnHover)
    }

    @Test("generated TOML includes command block settings")
    func generatedTomlIncludesCommandBlockSettings() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[command-blocks]"))
        #expect(toml.contains("show-only-on-hover = true"))
    }

    @Test("TOML preserves explicit command block settings")
    func tomlPreservesExplicitCommandBlockSettings() throws {
        let config = try loadConfig(from: """
        [command-blocks]
        enabled = false
        show-only-on-hover = false
        """)

        #expect(!config.commandBlocks.enabled)
        #expect(!config.commandBlocks.showOnlyOnHover)
    }

    @Test("malformed command block settings fall back safely")
    func malformedCommandBlockSettingsFallBackSafely() throws {
        let config = try loadConfig(from: """
        [command-blocks]
        enabled = "yes"
        show-only-on-hover = 1
        """)

        #expect(config.commandBlocks == .defaults)
    }

    @Test("project overrides preserve global command presentation settings")
    func projectOverridesPreserveGlobalCommandPresentationSettings() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            commandCorrections: CommandCorrectionsConfig(enabled: false),
            commandBlocks: CommandBlocksConfig(enabled: false, showOnlyOnHover: false),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let merged = config.applying(projectOverrides: ProjectConfig(fontSize: 18))

        #expect(merged.commandCorrections == config.commandCorrections)
        #expect(merged.commandBlocks == config.commandBlocks)
    }
}
