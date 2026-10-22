// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceConfigRoundTripTests.swift - TOML coverage for the `[voice]` section.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Voice TOML round-trip")
struct VoiceConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        private(set) var writeCount = 0

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws {
            writeCount += 1
            self.content = content
        }
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
        #expect(defaults.consentPrompted == false)
    }

    @Test("generated default TOML documents Voice locale policy")
    func generatedDefaultTomlDocumentsVoiceLocalePolicy() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[voice]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("locale = \"system\""))
        #expect(toml.contains("auto-send-to-agent = false"))
        #expect(toml.contains("consent-prompted = false"))
    }

    @Test("TOML opt-in preserves explicit Voice locale override")
    func tomlOptInPreservesExplicitLocaleOverride() throws {
        let config = try loadConfig(from: """
        [voice]
        enabled = true
        locale = "es-ES"
        auto-send-to-agent = true
        consent-prompted = true
        """)

        #expect(config.voice.enabled == true)
        #expect(config.voice.localeIdentifier == "es-ES")
        #expect(config.voice.autoSendToAgent == true)
        #expect(config.voice.consentPrompted == true)
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
        #expect(decoded.consentPrompted == false)
    }

    @Test("Voice consent response updates both flags in one write")
    func voiceConsentResponseUsesOneAtomicWrite() throws {
        let provider = InMemoryProvider(content: """
        [voice]
        enabled = true
        locale = "es-ES"
        auto-send-to-agent = true

        [appearance]
        theme = "catppuccin-mocha"
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        try service.updateVoiceConsent(enabled: false, consentPrompted: true)

        #expect(provider.writeCount == 1)
        #expect(service.current.voice.enabled == false)
        #expect(service.current.voice.consentPrompted == true)
        #expect(service.current.voice.localeIdentifier == "es-ES")
        #expect(service.current.voice.autoSendToAgent == true)
        #expect(provider.content?.contains("[appearance]") == true)
    }

    @Test("keeping Voice enabled records consent without rewriting enabled")
    func keepingVoiceEnabledOnlyRecordsConsent() throws {
        let provider = InMemoryProvider(content: """
        [voice]
        enabled = true
        consent-prompted = false
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        try service.updateVoiceConsent(enabled: nil, consentPrompted: true)

        #expect(provider.writeCount == 1)
        #expect(service.current.voice.enabled == true)
        #expect(service.current.voice.consentPrompted == true)
    }
}
