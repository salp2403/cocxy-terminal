// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ExperimentalConfigSwiftTestingTests.swift - Feature gate defaults.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ExperimentalConfig")
struct ExperimentalConfigSwiftTestingTests {
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

    @Test("experimental feature gates default off")
    func defaultsAreOff() {
        #expect(CocxyConfig.defaults.experimental.pipEnabled == false)
        #expect(CocxyConfig.defaults.experimental.ptyDaemonEnabled == false)
        #expect(CocxyConfig.defaults.experimental.browserV2.enabled == false)
        #expect(CocxyConfig.defaults.experimental.remoteBrowser.enabled == false)
        #expect(CocxyConfig.defaults.experimental.cells.enabled == false)
        #expect(CocxyConfig.defaults.experimental.cocxyCoreMoat.enabled == false)
        #expect(CocxyConfig.defaults.experimental.agentTeamsV2.enabled == false)
    }

    @Test("generated default TOML documents experimental gates")
    func generatedDefaultTomlIncludesGates() {
        let toml = ConfigService.generateDefaultToml()
        #expect(toml.contains("[experimental]"))
        #expect(toml.contains("pip-enabled = false"))
        #expect(toml.contains("pty-daemon = false"))
        #expect(toml.contains("[experimental.browser-v2]"))
        #expect(toml.contains("[experimental.remote-browser]"))
        #expect(toml.contains("[experimental.cells]"))
        #expect(toml.contains("[experimental.cocxycore-moat]"))
        #expect(toml.contains("[experimental.agent-teams-v2]"))
    }

    @Test("TOML parses strategic rollout namespaces")
    func tomlParsesStrategicRolloutNamespaces() throws {
        let config = try loadConfig(from: """
        [experimental]
        pip-enabled = true
        pty-daemon = true

        [experimental.browser-v2]
        enabled = true

        [experimental.remote-browser]
        enabled = true

        [experimental.cells]
        enabled = true

        [experimental.cocxycore-moat]
        enabled = true

        [experimental.agent-teams-v2]
        enabled = true
        """)

        #expect(config.experimental.pipEnabled)
        #expect(config.experimental.ptyDaemonEnabled)
        #expect(config.experimental.browserV2.enabled)
        #expect(config.experimental.remoteBrowser.enabled)
        #expect(config.experimental.cells.enabled)
        #expect(config.experimental.cocxyCoreMoat.enabled)
        #expect(config.experimental.agentTeamsV2.enabled)
    }

    @Test("missing or malformed rollout namespaces fall back off")
    func missingOrMalformedRolloutNamespacesFallBackOff() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [experimental.browser-v2]
        enabled = "yes"

        [experimental.remote-browser]
        enabled = 1
        """)

        #expect(missing.experimental == .defaults)
        #expect(malformed.experimental.browserV2 == .defaults)
        #expect(malformed.experimental.remoteBrowser == .defaults)
    }

    @Test("codable fallback keeps gates off when section is absent")
    func codableFallbackKeepsGatesOff() throws {
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
        #expect(decoded.experimental == .defaults)
    }

    @Test("legacy ExperimentalConfig payloads decode rollout namespaces off")
    func legacyExperimentalPayloadsDecodeRolloutNamespacesOff() throws {
        let json = """
        {
          "pipEnabled": true,
          "ptyDaemonEnabled": true
        }
        """

        let decoded = try JSONDecoder().decode(ExperimentalConfig.self, from: Data(json.utf8))

        #expect(decoded.pipEnabled)
        #expect(decoded.ptyDaemonEnabled)
        #expect(decoded.browserV2 == .defaults)
        #expect(decoded.remoteBrowser == .defaults)
        #expect(decoded.cells == .defaults)
        #expect(decoded.cocxyCoreMoat == .defaults)
        #expect(decoded.agentTeamsV2 == .defaults)
    }
}
