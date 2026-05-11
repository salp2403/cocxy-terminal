// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantConfigRoundTripTests.swift - TOML coverage for `[git-assistant]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Git Assistant TOML round-trip")
struct GitAssistantConfigRoundTripTests {
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

    @Test("Git Assistant defaults are local-first and generation is opt-in")
    func defaultsAreLocalFirst() {
        let defaults = CocxyConfig.defaults.gitAssistant

        #expect(defaults.enabled == true)
        #expect(defaults.defaultProvider == .foundationModelsOnDevice)
        #expect(defaults.maxDiffLines == 4_000)
        #expect(defaults.promptStyle == .conventional)
        #expect(defaults.autoGeneratePRBodyOnCreate == false)
        #expect(defaults.autoGenerateCommitMessageOnStage == false)
    }

    @Test("generated default TOML documents the Git Assistant section")
    func generatedDefaultTomlDocumentsSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[git-assistant]"))
        #expect(toml.contains("default-provider = \"foundation-models-on-device\""))
        #expect(toml.contains("max-diff-lines = 4000"))
        #expect(toml.contains("prompt-style = \"conventional\""))
        #expect(toml.contains("auto-generate-pr-body-on-create = false"))
        #expect(toml.contains("auto-generate-commit-message-on-stage = false"))
    }

    @Test("TOML opt-in preserves provider, budget and automation flags")
    func tomlOptInPreservesSettings() throws {
        let config = try loadConfig(from: """
        [git-assistant]
        enabled = true
        default-provider = "openai"
        max-diff-lines = 1200
        prompt-style = "descriptive"
        auto-generate-pr-body-on-create = true
        auto-generate-commit-message-on-stage = true
        """)

        #expect(config.gitAssistant.enabled == true)
        #expect(config.gitAssistant.defaultProvider == .openai)
        #expect(config.gitAssistant.maxDiffLines == 1_200)
        #expect(config.gitAssistant.promptStyle == .descriptive)
        #expect(config.gitAssistant.autoGeneratePRBodyOnCreate == true)
        #expect(config.gitAssistant.autoGenerateCommitMessageOnStage == true)
    }

    @Test("missing or malformed Git Assistant section falls back defensively")
    func missingOrMalformedFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [git-assistant]
        enabled = "yes"
        default-provider = "remote"
        max-diff-lines = 999999
        prompt-style = "verbose"
        auto-generate-pr-body-on-create = "always"
        auto-generate-commit-message-on-stage = "always"
        """)

        #expect(missing.gitAssistant == .defaults)
        #expect(malformed.gitAssistant.enabled == GitAssistantSettings.defaults.enabled)
        #expect(malformed.gitAssistant.defaultProvider == .foundationModelsOnDevice)
        #expect(malformed.gitAssistant.maxDiffLines == GitAssistantSettings.maxMaxDiffLines)
        #expect(malformed.gitAssistant.promptStyle == .conventional)
        #expect(malformed.gitAssistant.autoGeneratePRBodyOnCreate == false)
        #expect(malformed.gitAssistant.autoGenerateCommitMessageOnStage == false)
    }

    @Test("legacy Codable payloads decode with Git Assistant defaults")
    func legacyCodablePayloadsDecodeWithDefaults() throws {
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
        #expect(decoded.gitAssistant == .defaults)
    }
}
