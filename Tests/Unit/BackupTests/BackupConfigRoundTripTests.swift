// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BackupConfigRoundTripTests.swift - TOML coverage for `[backup]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - Backup TOML round-trip")
struct BackupConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(_ content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test("Backup defaults are local automatic with conservative artifact selection")
    func defaultsAreLocalAutomaticWithConservativeArtifactSelection() {
        let defaults = CocxyConfig.defaults.backup

        #expect(defaults.enabled == true)
        #expect(defaults.storageDirectory == "~/Library/Backups/Cocxy")
        #expect(defaults.dailyRetentionCount == 30)
        #expect(defaults.monthlyRetentionCount == 12)
        #expect(defaults.artifactKinds.contains(.settings))
        #expect(defaults.artifactKinds.contains(.encryptedSSHHosts))
        #expect(!defaults.artifactKinds.contains(.aiConversations))
    }

    @Test("default roots match production artifact stores without broad home copies")
    func defaultRootsMatchProductionArtifactStoresWithoutBroadHomeCopies() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let roots = BackupArtifactRoots.defaults(homeDirectory: home)

        #expect(roots.settings.path == "/Users/example/.config/cocxy/config.toml")
        #expect(roots.notebooks.path == "/Users/example/.cocxy/notebooks")
        #expect(roots.workflows.path == "/Users/example/.cocxy/workflows")
        #expect(roots.skills.path == "/Users/example/.cocxy/skills")
        #expect(roots.macros.path == "/Users/example/.cocxy/snippets.json")
        #expect(roots.themes.path == "/Users/example/.config/cocxy/themes")
        #expect(roots.aiConversations.path == "/Users/example/.config/cocxy/agent/conversations")
    }

    @Test("generated default TOML documents Backup section")
    func generatedDefaultTomlDocumentsBackupSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[backup]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("storage-directory = \"~/Library/Backups/Cocxy\""))
        #expect(toml.contains("daily-retention-count = 30"))
        #expect(toml.contains("monthly-retention-count = 12"))
        #expect(toml.contains("artifact-kinds = ["))
        let artifactLine = toml
            .split(separator: "\n")
            .first { $0.hasPrefix("artifact-kinds = [") }
        #expect(artifactLine?.contains("\"ai-conversations\"") == false)
    }

    @Test("TOML opt-in preserves Backup retention and artifacts")
    func tomlOptInPreservesBackupRetentionAndArtifacts() throws {
        let config = try loadConfig(from: """
        [backup]
        enabled = false
        storage-directory = "~/Backups/CocxyCustom"
        daily-retention-count = 7
        monthly-retention-count = 3
        artifact-kinds = ["settings", "notebooks", "ai-conversations"]
        """)

        #expect(config.backup.enabled == false)
        #expect(config.backup.storageDirectory == "~/Backups/CocxyCustom")
        #expect(config.backup.dailyRetentionCount == 7)
        #expect(config.backup.monthlyRetentionCount == 3)
        #expect(config.backup.artifactKinds == [.settings, .notebooks, .aiConversations])
    }

    @Test("missing malformed or empty Backup config falls back defensively")
    func missingMalformedOrEmptyBackupConfigFallsBackDefensively() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [backup]
        enabled = "yes"
        storage-directory = 42
        daily-retention-count = "30"
        monthly-retention-count = "12"
        artifact-kinds = ["settings", 3, "unknown"]
        """)
        let emptyStorage = try loadConfig(from: """
        [backup]
        storage-directory = "   "
        """)
        let negativeRetention = try loadConfig(from: """
        [backup]
        daily-retention-count = -5
        monthly-retention-count = -6
        """)

        #expect(missing.backup == .defaults)
        #expect(malformed.backup == .defaults)
        #expect(emptyStorage.backup.storageDirectory == BackupConfig.defaults.storageDirectory)
        #expect(negativeRetention.backup.dailyRetentionCount == 1)
        #expect(negativeRetention.backup.monthlyRetentionCount == 0)
    }
}
