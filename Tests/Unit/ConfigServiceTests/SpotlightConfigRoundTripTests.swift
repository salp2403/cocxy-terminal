// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SpotlightConfigRoundTripTests.swift - TOML coverage for `[spotlight]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Spotlight TOML round-trip")
struct SpotlightConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(_ content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test("Spotlight defaults are disabled and privacy preserving")
    func defaultsAreDisabledAndPrivate() {
        let defaults = CocxyConfig.defaults.spotlight

        #expect(defaults.enabled == false)
        #expect(defaults.indexCommandHistory == true)
        #expect(defaults.indexAgentConversations == true)
        #expect(defaults.includeCommandOutput == false)
        #expect(defaults.includeWorkingDirectories == false)
        #expect(defaults.includeToolMetadata == false)
    }

    @Test("generated default TOML documents the disabled Spotlight section")
    func generatedDefaultTomlDocumentsDisabledSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[spotlight]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("index-command-history = true"))
        #expect(toml.contains("index-agent-conversations = true"))
        #expect(toml.contains("include-command-output = false"))
        #expect(toml.contains("include-working-directories = false"))
        #expect(toml.contains("include-tool-metadata = false"))
    }

    @Test("TOML opt-in preserves every Spotlight privacy field")
    func tomlOptInPreservesFields() throws {
        let config = try loadConfig(from: """
        [spotlight]
        enabled = true
        index-command-history = false
        index-agent-conversations = true
        include-command-output = true
        include-working-directories = true
        include-tool-metadata = true
        """)

        #expect(config.spotlight.enabled == true)
        #expect(config.spotlight.indexCommandHistory == false)
        #expect(config.spotlight.indexAgentConversations == true)
        #expect(config.spotlight.includeCommandOutput == true)
        #expect(config.spotlight.includeWorkingDirectories == true)
        #expect(config.spotlight.includeToolMetadata == true)
    }

    @Test("missing or malformed Spotlight config falls back to disabled defaults")
    func missingOrMalformedFallsBackToDefaults() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [spotlight]
        enabled = "yes"
        index-command-history = "yes"
        index-agent-conversations = "yes"
        include-command-output = "yes"
        include-working-directories = "yes"
        include-tool-metadata = "yes"
        """)

        #expect(missing.spotlight == .defaults)
        #expect(malformed.spotlight == .defaults)
    }

    @Test("legacy Codable payloads decode with Spotlight disabled")
    func legacyCodablePayloadsDecodeWithSpotlightDisabled() throws {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CocxyConfig.self, from: data)

        #expect(decoded.spotlight == .defaults)
    }
}
