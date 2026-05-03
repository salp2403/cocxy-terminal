// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentModeConfigRoundTripTests.swift - TOML coverage for the `[agent]` section.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — Agent Mode TOML round-trip")
struct AgentModeConfigRoundTripTests {
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

    @Test("Agent Mode defaults are safe and local-first")
    func defaultsAreSafeAndLocalFirst() {
        let defaults = CocxyConfig.defaults.agent

        #expect(defaults.enabled == false)
        #expect(defaults.preferredProvider == .foundationModelsOnDevice)
        #expect(defaults.foundationModelsFallback == .requireExplicitChoice)
        #expect(defaults.autoMode == false)
        #expect(defaults.computerUseConfirm == true)
        #expect(defaults.maxIterations == 8)
        #expect(defaults.conversationStorageDir == "~/.config/cocxy/agent/conversations")
        #expect(defaults.conversationEncryption == .disabled)
        #expect(defaults.effectiveProvider(foundationModelsAvailable: true) == .provider(.foundationModelsOnDevice))
        #expect(defaults.effectiveProvider(foundationModelsAvailable: false) == .explicitChoiceRequired)
    }

    @Test("generated default TOML documents disabled Agent Mode")
    func generatedDefaultTomlDocumentsDisabledAgentMode() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[agent]"))
        #expect(toml.contains("preferred-provider = \"foundation-models-on-device\""))
        #expect(toml.contains("foundation-models-fallback = \"require-explicit-choice\""))
        #expect(toml.contains("auto-mode = false"))
        #expect(toml.contains("computer-use-confirm = true"))
        #expect(toml.contains("max-iterations = 8"))
        #expect(toml.contains("conversation-encryption = \"disabled\""))
    }

    @Test("TOML opt-in preserves provider policy and limits")
    func tomlOptInPreservesProviderPolicy() throws {
        let config = try loadConfig(from: """
        [agent]
        enabled = true
        preferred-provider = "anthropic"
        foundation-models-fallback = "require-explicit-choice"
        auto-mode = true
        computer-use-confirm = false
        max-iterations = 12
        conversation-storage-dir = "~/.config/cocxy/custom-agent"
        conversation-encryption = "master-password"
        """)

        #expect(config.agent.enabled == true)
        #expect(config.agent.preferredProvider == .anthropic)
        #expect(config.agent.foundationModelsFallback == .requireExplicitChoice)
        #expect(config.agent.autoMode == true)
        #expect(config.agent.computerUseConfirm == false)
        #expect(config.agent.maxIterations == 12)
        #expect(config.agent.conversationStorageDir == "~/.config/cocxy/custom-agent")
        #expect(config.agent.conversationEncryption == .masterPassword)
        #expect(config.agent.effectiveProvider(foundationModelsAvailable: false) == .provider(.anthropic))
    }

    @Test("missing or malformed Agent Mode section falls back defensively")
    func missingOrMalformedFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [agent]
        enabled = "yes"
        preferred-provider = "cocxy-cloud"
        foundation-models-fallback = "remote-provider"
        auto-mode = "always"
        computer-use-confirm = "sometimes"
        max-iterations = 500
        conversation-storage-dir = 42
        conversation-encryption = "cloud"
        """)

        #expect(missing.agent == .defaults)
        #expect(malformed.agent.enabled == false)
        #expect(malformed.agent.preferredProvider == .foundationModelsOnDevice)
        #expect(malformed.agent.foundationModelsFallback == .requireExplicitChoice)
        #expect(malformed.agent.autoMode == false)
        #expect(malformed.agent.computerUseConfirm == true)
        #expect(malformed.agent.maxIterations == AgentModeConfig.maxMaxIterations)
        #expect(malformed.agent.conversationStorageDir == AgentModeConfig.defaults.conversationStorageDir)
        #expect(malformed.agent.conversationEncryption == .disabled)
    }

    @Test("legacy Codable payloads decode with Agent Mode disabled")
    func legacyCodablePayloadsDecodeWithAgentModeDisabled() throws {
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
        #expect(decoded.agent == .defaults)
    }
}
