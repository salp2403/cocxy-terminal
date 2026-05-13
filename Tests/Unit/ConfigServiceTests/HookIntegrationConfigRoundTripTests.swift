// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookIntegrationConfigRoundTripTests.swift - TOML coverage for `[hooks]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Hooks TOML round-trip")
struct HookIntegrationConfigRoundTripTests {
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

    @Test("Hooks default to enabled for existing installed bridges")
    func defaultsPreserveInstalledBridges() {
        let defaults = CocxyConfig.defaults.hooks

        #expect(defaults.enabled == true)
        #expect(defaults.agents.count == 12)
        #expect(defaults.isAgentEnabled(.codex))
        #expect(defaults.isAgentEnabled(.qoder))
        #expect(defaults.disablingEnvironment()["COCXY_CLAUDE_HOOKS"] == "1")
        #expect(defaults.disablingEnvironment()["COCXY_HOOKS_DISABLED"] == nil)
    }

    @Test("generated default TOML documents hooks config and built-in agents")
    func generatedDefaultTomlDocumentsHooks() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[hooks]"))
        #expect(toml.contains("[hooks.agents.codex]"))
        #expect(toml.contains("[hooks.agents.rovo-dev]"))
        #expect(toml.contains("[hooks.agents.qoder]"))
    }

    @Test("TOML parses global and per-agent hook overrides")
    func tomlParsesOverrides() throws {
        let config = try loadConfig(from: """
        [hooks]
        enabled = false

        [hooks.agents.codex]
        enabled = false

        [hooks.agents.rovo-dev]
        enabled = false
        """)

        #expect(config.hooks.enabled == false)
        #expect(config.hooks.isAgentEnabled(.codex) == false)
        #expect(config.hooks.isAgentEnabled(.rovoDev) == false)
        #expect(config.hooks.isAgentEnabled(.opencode) == true)

        let env = config.hooks.disablingEnvironment()
        #expect(env["COCXY_HOOKS_DISABLED"] == "1")
        #expect(env["COCXY_CODEX_HOOKS_DISABLED"] == "1")
        #expect(env["COCXY_ROVODEV_HOOKS_DISABLED"] == "1")
        #expect(env["COCXY_OPENCODE_HOOKS_DISABLED"] == nil)
    }

    @Test("missing or malformed hooks section falls back defensively")
    func missingOrMalformedFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [hooks]
        enabled = "yes"

        [hooks.agents.codex]
        enabled = "no"
        """)

        #expect(missing.hooks == .defaults)
        #expect(malformed.hooks.enabled == true)
        #expect(malformed.hooks.isAgentEnabled(.codex) == true)
    }

    @Test("legacy Codable payloads decode with hook defaults")
    func legacyCodablePayloadsDecodeWithHookDefaults() throws {
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

        #expect(decoded.hooks == .defaults)
    }

    @Test("Codable payloads keep agent IDs as stable string keys")
    func codablePayloadsKeepAgentIDsStable() throws {
        let config = HookIntegrationConfig(
            enabled: false,
            agents: [
                .codex: HookIntegrationAgentConfig(enabled: false),
                .rovoDev: HookIntegrationAgentConfig(enabled: false),
            ]
        )

        let data = try JSONEncoder().encode(config)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(HookIntegrationConfig.self, from: data)

        #expect(json.contains(#""codex""#))
        #expect(json.contains(#""rovo-dev""#))
        #expect(decoded.enabled == false)
        #expect(decoded.isAgentEnabled(.codex) == false)
        #expect(decoded.isAgentEnabled(.rovoDev) == false)
    }
}
