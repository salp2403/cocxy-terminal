// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayConfigRoundTripTests.swift - TOML coverage for `[session-replay]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Session Replay TOML round-trip")
struct SessionReplayConfigRoundTripTests {
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

    @Test("Session Replay defaults are disabled and local")
    func defaultsAreDisabledAndLocal() {
        let defaults = CocxyConfig.defaults.sessionReplay

        #expect(defaults.enabled == false)
        #expect(defaults.autoRecord == false)
        #expect(defaults.consentGranted == false)
        #expect(defaults.storageDirectory == "~/Library/Application Support/Cocxy/Recordings")
        #expect(defaults.maxRecordingBytes == 512 * 1024 * 1024)
        #expect(defaults.policy.canAutoRecord == false)
    }

    @Test("generated default TOML documents disabled Session Replay section")
    func generatedDefaultTomlDocumentsDisabledSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[session-replay]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("auto-record = false"))
        #expect(toml.contains("consent-granted = false"))
        #expect(toml.contains("storage-directory = \"~/Library/Application Support/Cocxy/Recordings\""))
        #expect(toml.contains("max-recording-bytes = 536870912"))
    }

    @Test("TOML opt-in preserves Session Replay privacy settings")
    func tomlOptInPreservesPrivacySettings() throws {
        let config = try loadConfig(from: """
        [session-replay]
        enabled = true
        auto-record = true
        consent-granted = true
        storage-directory = "~/.cocxy/recordings"
        max-recording-bytes = 1048576
        """)

        #expect(config.sessionReplay.enabled == true)
        #expect(config.sessionReplay.autoRecord == true)
        #expect(config.sessionReplay.consentGranted == true)
        #expect(config.sessionReplay.storageDirectory == "~/.cocxy/recordings")
        #expect(config.sessionReplay.maxRecordingBytes == 1_048_576)
        #expect(config.sessionReplay.policy.canAutoRecord == true)
    }

    @Test("auto recording cannot be enabled without explicit consent")
    func autoRecordingRequiresConsent() throws {
        let config = try loadConfig(from: """
        [session-replay]
        enabled = true
        auto-record = true
        consent-granted = false
        """)

        #expect(config.sessionReplay.enabled == true)
        #expect(config.sessionReplay.autoRecord == true)
        #expect(config.sessionReplay.policy.canAutoRecord == false)
    }

    @Test("missing malformed or empty Session Replay config falls back defensively")
    func missingMalformedOrEmptyConfigFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [session-replay]
        enabled = "yes"
        auto-record = "yes"
        consent-granted = "yes"
        storage-directory = 42
        max-recording-bytes = "huge"
        """)
        let emptyStorage = try loadConfig(from: """
        [session-replay]
        storage-directory = "   "
        """)
        let negativeLimit = try loadConfig(from: """
        [session-replay]
        max-recording-bytes = -1
        """)

        #expect(missing.sessionReplay == .defaults)
        #expect(malformed.sessionReplay == .defaults)
        #expect(emptyStorage.sessionReplay.storageDirectory == SessionReplayConfig.defaults.storageDirectory)
        #expect(negativeLimit.sessionReplay.maxRecordingBytes == SessionReplayConfig.defaults.maxRecordingBytes)
    }

    @Test("legacy Codable payloads decode with Session Replay disabled")
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
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sessionReplay")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CocxyConfig.self, from: legacyData)
        #expect(decoded.sessionReplay == .defaults)
    }
}
