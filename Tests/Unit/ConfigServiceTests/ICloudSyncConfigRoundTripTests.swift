// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncConfigRoundTripTests.swift - TOML coverage for `[icloud-sync]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - iCloud Sync TOML round-trip")
struct ICloudSyncConfigRoundTripTests {
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

    @Test("iCloud Sync defaults are disabled encrypted and manual conflict only")
    func defaultsAreDisabledEncryptedAndManualConflictOnly() {
        let defaults = CocxyConfig.defaults.iCloudSync

        #expect(defaults.enabled == false)
        #expect(defaults.encryptionRequired == true)
        #expect(defaults.syncDirectoryName == "Cocxy")
        #expect(defaults.conflictPolicy == .manual)
        #expect(defaults.artifactKinds == ICloudSyncArtifactKind.allCases)
    }

    @Test("generated default TOML documents disabled iCloud Sync section")
    func generatedDefaultTomlDocumentsDisabledICloudSyncSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[icloud-sync]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("encryption-required = true"))
        #expect(toml.contains("sync-directory-name = \"Cocxy\""))
        #expect(toml.contains("conflict-policy = \"manual\""))
        #expect(toml.contains("artifact-kinds = [\"notebooks\", \"workflows\", \"skills\", \"settings\", \"themes\"]"))
    }

    @Test("TOML opt-in preserves safe iCloud Sync settings")
    func tomlOptInPreservesSafeICloudSyncSettings() throws {
        let config = try loadConfig(from: """
        [icloud-sync]
        enabled = true
        sync-directory-name = "CocxyPrivate"
        encryption-required = true
        artifact-kinds = ["notebooks", "skills", "settings"]
        conflict-policy = "manual"
        """)

        #expect(config.iCloudSync.enabled == true)
        #expect(config.iCloudSync.syncDirectoryName == "CocxyPrivate")
        #expect(config.iCloudSync.encryptionRequired == true)
        #expect(config.iCloudSync.artifactKinds == [.notebooks, .skills, .settings])
        #expect(config.iCloudSync.conflictPolicy == .manual)
    }

    @Test("missing malformed or unsafe iCloud Sync config falls back defensively")
    func missingMalformedOrUnsafeConfigFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [icloud-sync]
        enabled = "yes"
        sync-directory-name = 42
        encryption-required = "yes"
        artifact-kinds = "notebooks"
        conflict-policy = "last-write-wins"
        """)
        let unsafeDirectory = try loadConfig(from: """
        [icloud-sync]
        sync-directory-name = "../Cocxy"
        artifact-kinds = ["unknown"]
        """)

        #expect(missing.iCloudSync == .defaults)
        #expect(malformed.iCloudSync == .defaults)
        #expect(unsafeDirectory.iCloudSync.syncDirectoryName == ICloudSyncConfig.defaults.syncDirectoryName)
        #expect(unsafeDirectory.iCloudSync.artifactKinds == ICloudSyncConfig.defaults.artifactKinds)
    }

    @Test("legacy Codable payloads decode with iCloud Sync disabled")
    func legacyCodablePayloadsDecodeWithICloudSyncDisabled() throws {
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
        #expect(decoded.iCloudSync == .defaults)
    }
}
