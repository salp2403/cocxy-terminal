// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultConfigRoundTripTests.swift - TOML coverage for the `[vault]` section.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Vault TOML round-trip")
struct VaultConfigRoundTripTests {
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

    @Test("Vault defaults are local-only and manual by default")
    func defaultsAreLocalOnlyAndManual() {
        let defaults = CocxyConfig.defaults.vault

        #expect(defaults.enabled == false)
        #expect(defaults.autoResumeOnLaunch == false)
        #expect(defaults.autoResumeOnRestore == false)
        #expect(defaults.confirmBeforeResume == true)
        #expect(defaults.encryptedStorage == true)
        #expect(defaults.sessionRetentionDays == 30)
        #expect(defaults.agents.count == 11)
        #expect(defaults.agents["codex"]?.enabled == true)
        #expect(defaults.agents["qoder"]?.enabled == true)
    }

    @Test("generated default TOML documents disabled Vault config and built-in agents")
    func generatedDefaultTomlDocumentsVault() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[vault]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("auto-resume-on-launch = false"))
        #expect(toml.contains("auto-resume-on-restore = false"))
        #expect(toml.contains("confirm-before-resume = true"))
        #expect(toml.contains("encrypted-storage = true"))
        #expect(toml.contains("session-retention-days = 30"))
        #expect(toml.contains("[vault.agents.codex]"))
        #expect(toml.contains("[vault.agents.qoder]"))
    }

    @Test("TOML parses built-in overrides and custom agents")
    func tomlParsesBuiltInOverridesAndCustomAgents() throws {
        let config = try loadConfig(from: """
        [vault]
        enabled = true
        auto-resume-on-launch = true
        auto-resume-on-restore = true
        confirm-before-resume = false
        encrypted-storage = true
        session-retention-days = 14

        [vault.agents.codex]
        enabled = false
        detect-process = "codex"
        detect-argv-contains = "--session"
        session-id-source = "argv"
        session-id-argv-option = "--session"
        resume-command = "codex resume {session_id}"
        cwd-policy = "preserve"
        session-directory = "~/.codex/sessions"

        [vault.agents.local-agent]
        enabled = true
        detect-process = "local-agent"
        detect-argv-contains = "continue"
        session-id-source = "argv"
        session-id-argv-option = "--conversation"
        resume-command = "local-agent continue {session_id}"
        cwd-policy = "last-seen"
        session-directory = "~/.local/share/local-agent"
        """)

        #expect(config.vault.enabled == true)
        #expect(config.vault.autoResumeOnLaunch == true)
        #expect(config.vault.autoResumeOnRestore == true)
        #expect(config.vault.confirmBeforeResume == false)
        #expect(config.vault.sessionRetentionDays == 14)

        let codex = try #require(config.vault.agents["codex"])
        #expect(codex.enabled == false)
        #expect(codex.detectProcess == "codex")
        #expect(codex.detectArgvContains == "--session")
        #expect(codex.sessionIDSource == "argv")
        #expect(codex.sessionIDArgvOption == "--session")
        #expect(codex.resumeCommand == "codex resume {session_id}")
        #expect(codex.cwdPolicy == "preserve")
        #expect(codex.sessionDirectory == "~/.codex/sessions")

        let custom = try #require(config.vault.agents["local-agent"])
        #expect(custom.enabled == true)
        #expect(custom.detectProcess == "local-agent")
        #expect(custom.resumeCommand == "local-agent continue {session_id}")
        #expect(custom.sessionDirectory == "~/.local/share/local-agent")
    }

    @Test("agent IDs and optional fields are normalized")
    func agentFieldsAreNormalized() throws {
        let config = try loadConfig(from: """
        [vault.agents.Local-Agent]
        enabled = true
        detect-process = "  local-agent  "
        detect-argv-contains = "  continue  "
        session-id-source = "  argv  "
        session-id-argv-option = "  --conversation  "
        resume-command = "  local-agent continue {session_id}  "
        cwd-policy = "  last-seen  "
        session-directory = "  ~/.local/share/local-agent  "
        """)

        let custom = try #require(config.vault.agents["local-agent"])
        #expect(custom.detectProcess == "local-agent")
        #expect(custom.detectArgvContains == "continue")
        #expect(custom.sessionIDSource == "argv")
        #expect(custom.sessionIDArgvOption == "--conversation")
        #expect(custom.resumeCommand == "local-agent continue {session_id}")
        #expect(custom.cwdPolicy == "last-seen")
        #expect(custom.sessionDirectory == "~/.local/share/local-agent")
    }

    @Test("missing or malformed Vault section falls back defensively")
    func missingOrMalformedFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [vault]
        enabled = "yes"
        auto-resume-on-launch = "always"
        auto-resume-on-restore = "always"
        confirm-before-resume = "sometimes"
        encrypted-storage = false
        session-retention-days = 5000

        [vault.agents.codex]
        enabled = "no"
        detect-process = 42
        """)

        #expect(missing.vault == .defaults)
        #expect(malformed.vault.enabled == false)
        #expect(malformed.vault.autoResumeOnLaunch == false)
        #expect(malformed.vault.autoResumeOnRestore == false)
        #expect(malformed.vault.confirmBeforeResume == true)
        #expect(malformed.vault.encryptedStorage == true)
        #expect(malformed.vault.sessionRetentionDays == VaultConfig.maxSessionRetentionDays)
        #expect(malformed.vault.agents["codex"]?.enabled == true)
    }

    @Test("legacy Codable payloads decode with Vault defaults")
    func legacyCodablePayloadsDecodeWithVaultDefaults() throws {
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

        #expect(decoded.vault == .defaults)
    }
}
