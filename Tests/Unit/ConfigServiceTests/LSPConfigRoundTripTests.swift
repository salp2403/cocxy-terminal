// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPConfigRoundTripTests.swift - TOML coverage for the `[lsp]` section.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — LSP TOML round-trip")
struct LSPConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        private(set) var writtenContent: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
            writtenContent = content
            self.content = content
        }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test("LSP defaults are disabled and opt-in only")
    func defaultsAreDisabled() {
        #expect(CocxyConfig.defaults.lsp.enabled == false)
        #expect(CocxyConfig.defaults.lsp.enabledLanguageIDs.isEmpty)
        #expect(CocxyConfig.defaults.lsp.managerConfiguration.enabledLanguageIDs.isEmpty)
    }

    @Test("generated default TOML documents the disabled LSP section")
    func generatedTomlDocumentsDisabledSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[lsp]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("enabled-languages = []"))
    }

    @Test("TOML opt-in preserves normalized enabled languages")
    func tomlOptInPreservesEnabledLanguages() throws {
        let config = try loadConfig(from: """
        [lsp]
        enabled = true
        enabled-languages = ["swift", "go", "Swift", " python "]
        """)

        #expect(config.lsp.enabled == true)
        #expect(config.lsp.enabledLanguageIDs == ["go", "python", "swift"])
        #expect(config.lsp.managerConfiguration.enabledLanguageIDs == Set(["go", "python", "swift"]))
    }

    @Test("disabled master switch suppresses enabled language list")
    func disabledMasterSwitchSuppressesLanguages() throws {
        let config = try loadConfig(from: """
        [lsp]
        enabled = false
        enabled-languages = ["swift", "go"]
        """)

        #expect(config.lsp.enabled == false)
        #expect(config.lsp.enabledLanguageIDs == ["go", "swift"])
        #expect(config.lsp.managerConfiguration.enabledLanguageIDs.isEmpty)
    }

    @Test("missing or malformed LSP section falls back to defaults")
    func missingOrMalformedFallsBackToDefaults() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [lsp]
        enabled = "yes"
        enabled-languages = [1, true, "swift"]
        """)

        #expect(missing.lsp == .defaults)
        #expect(malformed.lsp.enabled == false)
        #expect(malformed.lsp.enabledLanguageIDs == ["swift"])
    }
}
