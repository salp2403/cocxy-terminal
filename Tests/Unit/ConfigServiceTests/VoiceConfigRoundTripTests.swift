// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceConfigRoundTripTests.swift - TOML coverage for the `[voice]` section.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Voice TOML round-trip")
struct VoiceConfigRoundTripTests {
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

    @Test("Voice defaults are discoverable local review-first and system-locale first")
    func defaultsAreEnabledLocalReviewFirstAndSystemLocaleFirst() {
        let defaults = CocxyConfig.defaults.voice

        #expect(defaults.enabled == true)
        #expect(defaults.localeIdentifier == VoiceConfig.systemLocaleIdentifier)
        #expect(defaults.autoSendToAgent == false)
    }

    @Test("generated default TOML documents Voice locale policy")
    func generatedDefaultTomlDocumentsVoiceLocalePolicy() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[voice]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("locale = \"system\""))
        #expect(toml.contains("auto-send-to-agent = false"))
    }

    @Test("TOML opt-in preserves explicit Voice locale override")
    func tomlOptInPreservesExplicitLocaleOverride() throws {
        let config = try loadConfig(from: """
        [voice]
        enabled = true
        locale = "es-ES"
        auto-send-to-agent = true
        """)

        #expect(config.voice.enabled == true)
        #expect(config.voice.localeIdentifier == "es-ES")
        #expect(config.voice.autoSendToAgent == true)
    }

    @Test("missing malformed or empty Voice config falls back defensively")
    func missingMalformedOrEmptyVoiceConfigFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [voice]
        enabled = "yes"
        locale = 42
        auto-send-to-agent = "yes"
        """)
        let emptyLocale = try loadConfig(from: """
        [voice]
        locale = "   "
        """)

        #expect(missing.voice == .defaults)
        #expect(malformed.voice == .defaults)
        #expect(emptyLocale.voice.localeIdentifier == VoiceConfig.systemLocaleIdentifier)
    }

    @Test("legacy Codable payloads decode with current Voice defaults")
    func legacyCodablePayloadsDecodeWithCurrentVoiceDefaults() throws {
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
        #expect(decoded.voice == .defaults)
    }

    @Test("legacy Voice payload without auto-send remains review-first")
    func legacyVoicePayloadWithoutAutoSendRemainsReviewFirst() throws {
        let data = Data(#"{"enabled":true,"localeIdentifier":"es-ES"}"#.utf8)

        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)

        #expect(decoded.enabled == true)
        #expect(decoded.localeIdentifier == "es-ES")
        #expect(decoded.autoSendToAgent == false)
    }
}
