// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityConfigRoundTripTests.swift - TOML coverage for `[activity]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Activity TOML round-trip")
struct ActivityConfigRoundTripTests {
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

    @Test("Activity defaults are disabled local")
    func defaultsAreDisabledLocal() {
        let defaults = CocxyConfig.defaults.activity

        #expect(defaults.enabled == false)
        #expect(defaults.costTrackingEnabled == false)
        #expect(defaults.storageDirectory == "~/.config/cocxy/activity")
        #expect(defaults.privacyPolicy == .disabled)
    }

    @Test("generated default TOML documents disabled Activity section")
    func generatedDefaultTomlDocumentsDisabledActivitySection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[activity]"))
        #expect(toml.contains("cost-tracking = false"))
        #expect(toml.contains("storage-directory = \"~/.config/cocxy/activity\""))
    }

    @Test("TOML opt-in preserves Activity privacy settings")
    func tomlOptInPreservesActivityPrivacySettings() throws {
        let config = try loadConfig(from: """
        [activity]
        enabled = true
        cost-tracking = true
        storage-directory = "~/.config/cocxy/activity-custom"
        """)

        #expect(config.activity.enabled == true)
        #expect(config.activity.costTrackingEnabled == true)
        #expect(config.activity.storageDirectory == "~/.config/cocxy/activity-custom")
        #expect(config.activity.privacyPolicy == .enabled)
    }

    @Test("missing malformed or empty Activity config falls back defensively")
    func missingMalformedOrEmptyActivityConfigFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [activity]
        enabled = "yes"
        cost-tracking = "yes"
        storage-directory = 42
        """)
        let emptyStorage = try loadConfig(from: """
        [activity]
        storage-directory = "   "
        """)

        #expect(missing.activity == .defaults)
        #expect(malformed.activity == .defaults)
        #expect(emptyStorage.activity.storageDirectory == ActivityConfig.defaults.storageDirectory)
    }

    @Test("legacy Codable payloads decode with Activity disabled")
    func legacyCodablePayloadsDecodeWithActivityDisabled() throws {
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
        #expect(decoded.activity == .defaults)
    }
}
