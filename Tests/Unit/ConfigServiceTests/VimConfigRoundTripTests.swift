// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VimConfigRoundTripTests.swift - TOML coverage for the `[vim]` section.

import Testing
@testable import CocxyTerminal

@Suite("ConfigService — Vim TOML round-trip")
struct VimConfigRoundTripTests {
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

    @Test("Vim defaults off so editor typing is unchanged after upgrade")
    func defaultsOff() {
        #expect(CocxyConfig.defaults.vim.enabled == false)
    }

    @Test("generated default TOML documents the disabled Vim section")
    func generatedTomlDocumentsDisabledSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[vim]"))
        #expect(toml.contains("enabled = false"))
    }

    @Test("TOML opt-in enables editor-only Vim mode")
    func tomlOptInEnablesVim() throws {
        let config = try loadConfig(from: """
        [vim]
        enabled = true
        """)

        #expect(config.vim.enabled)
    }

    @Test("missing or malformed Vim section falls back to disabled")
    func missingOrMalformedFallsBackToDisabled() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [vim]
        enabled = "yes"
        """)

        #expect(missing.vim == .defaults)
        #expect(malformed.vim == .defaults)
    }
}
