// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LocalBackupSwiftTestingTests.swift - Local backup, restore, and retention coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Local backup manager")
struct LocalBackupSwiftTestingTests {
    @Test("creates timestamped local backup with manifest and selected artifacts")
    func createsTimestampedLocalBackupWithManifestAndSelectedArtifacts() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()

        let config = BackupConfig(
            enabled: true,
            storageDirectory: fixture.backupRoot.path,
            dailyRetentionCount: 30,
            monthlyRetentionCount: 12,
            artifactKinds: [.settings, .notebooks, .workflows, .skills, .notes, .macros, .themes, .encryptedSSHHosts]
        )
        let manager = LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })

        let result = try manager.createBackup(config: config, roots: fixture.roots)

        #expect(result.backupURL.lastPathComponent == "2026-05-03_12-00-00")
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("settings/config.toml").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("notebooks/demo.cocxynb").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("workflows/build.toml").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("skills/custom/SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("notes/workspace/note.md").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("macros/snippets.json").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("themes/custom.toml").path))
        #expect(FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("encrypted-ssh-hosts/hosts.enc").path))
        #expect(!FileManager.default.fileExists(atPath: result.backupURL.appendingPathComponent("ai-conversations/session.jsonl").path))
        #expect(result.manifest.artifacts.map(\.kind).contains(.encryptedSSHHosts))
    }

    @Test("restores one artifact kind without touching unrelated local files")
    func restoresOneArtifactKindWithoutTouchingUnrelatedLocalFiles() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()
        let manager = LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })
        let result = try manager.createBackup(
            config: BackupConfig(
                enabled: true,
                storageDirectory: fixture.backupRoot.path,
                artifactKinds: [.settings, .notebooks]
            ),
            roots: fixture.roots
        )

        try FileManager.default.removeItem(at: fixture.roots.notebooks.appendingPathComponent("demo.cocxynb"))
        try "changed".write(
            to: fixture.roots.settings,
            atomically: true,
            encoding: .utf8
        )

        let restore = try manager.restore(
            kind: .notebooks,
            from: result.backupURL,
            to: fixture.roots
        )

        let restoredNotebook = try String(
            contentsOf: fixture.roots.notebooks.appendingPathComponent("demo.cocxynb"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: fixture.roots.settings,
            encoding: .utf8
        )
        #expect(restore.restoredFiles == 1)
        #expect(restoredNotebook.contains("notebook"))
        #expect(settings == "changed")
    }

    @Test("restores single-file artifacts to exact destinations")
    func restoresSingleFileArtifactsToExactDestinations() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()
        let manager = LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })
        let result = try manager.createBackup(
            config: BackupConfig(
                enabled: true,
                storageDirectory: fixture.backupRoot.path,
                artifactKinds: [.settings, .macros, .encryptedSSHHosts]
            ),
            roots: fixture.roots
        )

        try "changed-config".write(to: fixture.roots.settings, atomically: true, encoding: .utf8)
        try "changed-snippets".write(to: fixture.roots.macros, atomically: true, encoding: .utf8)
        try "changed-hosts".write(to: fixture.roots.encryptedSSHHosts, atomically: true, encoding: .utf8)

        let restoredSettings = try manager.restore(kind: .settings, from: result.backupURL, to: fixture.roots)
        let restoredMacros = try manager.restore(kind: .macros, from: result.backupURL, to: fixture.roots)
        let restoredHosts = try manager.restore(kind: .encryptedSSHHosts, from: result.backupURL, to: fixture.roots)

        #expect(restoredSettings.restoredFiles == 1)
        #expect(restoredMacros.restoredFiles == 1)
        #expect(restoredHosts.restoredFiles == 1)
        #expect(try String(contentsOf: fixture.roots.settings, encoding: .utf8) == "theme = \"test\"")
        #expect(try String(contentsOf: fixture.roots.macros, encoding: .utf8) == "[]")
        #expect(try String(contentsOf: fixture.roots.encryptedSSHHosts, encoding: .utf8) == "encrypted")
    }

    @Test("retention keeps latest daily backups and monthly representatives")
    func retentionKeepsLatestDailyBackupsAndMonthlyRepresentatives() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()

        for offset in 0..<45 {
            let date = fixture.dateByAdding(days: -offset, to: fixture.date("2026-05-03T12:00:00Z"))
            let manager = LocalBackupManager(now: { date })
            _ = try manager.createBackup(
                config: BackupConfig(
                    enabled: true,
                    storageDirectory: fixture.backupRoot.path,
                    dailyRetentionCount: 30,
                    monthlyRetentionCount: 1,
                    artifactKinds: [.settings]
                ),
                roots: fixture.roots
            )
        }

        let prune = try LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })
            .pruneBackups(
                config: BackupConfig(
                    enabled: true,
                    storageDirectory: fixture.backupRoot.path,
                    dailyRetentionCount: 30,
                    monthlyRetentionCount: 1,
                    artifactKinds: [.settings]
                )
            )
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.backupRoot.path).sorted()

        #expect(prune.deletedCount == 14)
        #expect(names.count == 31)
        #expect(names.contains("2026-05-03_12-00-00"))
        #expect(names.contains("2026-04-01_12-00-00"))
    }

    @Test("available backups are read from manifests and sorted newest first")
    func availableBackupsAreReadFromManifestsAndSortedNewestFirst() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()

        let older = try LocalBackupManager(now: { fixture.date("2026-05-02T12:00:00Z") })
            .createBackup(
                config: BackupConfig(
                    enabled: true,
                    storageDirectory: fixture.backupRoot.path,
                    artifactKinds: [.settings]
                ),
                roots: fixture.roots
            )
        let newer = try LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })
            .createBackup(
                config: BackupConfig(
                    enabled: true,
                    storageDirectory: fixture.backupRoot.path,
                    artifactKinds: [.settings, .notebooks]
                ),
                roots: fixture.roots
            )
        try FileManager.default.createDirectory(
            at: fixture.backupRoot.appendingPathComponent("2026-05-04_12-00-00", isDirectory: true),
            withIntermediateDirectories: true
        )

        let snapshots = try LocalBackupManager().availableBackups(storageDirectory: fixture.backupRoot.path)

        #expect(snapshots.map(\.backupURL.lastPathComponent) == [
            newer.backupURL.lastPathComponent,
            older.backupURL.lastPathComponent,
        ])
        #expect(snapshots[0].artifacts.map(\.kind) == [.notebooks, .settings])
        #expect(snapshots[0].totalFileCount == 2)
    }
}

struct BackupFixture {
    let root: URL
    let backupRoot: URL
    let roots: BackupArtifactRoots

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-backup-tests-\(UUID().uuidString)", isDirectory: true)
        backupRoot = root.appendingPathComponent("Backups", isDirectory: true)
        roots = BackupArtifactRoots(
            settings: root.appendingPathComponent("config/cocxy/config.toml", isDirectory: false),
            notebooks: root.appendingPathComponent("notebooks", isDirectory: true),
            workflows: root.appendingPathComponent("workflows", isDirectory: true),
            skills: root.appendingPathComponent("skills", isDirectory: true),
            notes: root.appendingPathComponent("notes", isDirectory: true),
            macros: root.appendingPathComponent("macros/snippets.json", isDirectory: false),
            themes: root.appendingPathComponent("themes", isDirectory: true),
            encryptedSSHHosts: root.appendingPathComponent("config/cocxy/ssh/hosts.enc"),
            aiConversations: root.appendingPathComponent("agent/conversations", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeFixtureFiles() throws {
        try write("theme = \"test\"", to: roots.settings)
        try write("# notebook", to: roots.notebooks.appendingPathComponent("demo.cocxynb"))
        try write("[workflow]\nid = \"build\"", to: roots.workflows.appendingPathComponent("build.toml"))
        try write("# custom skill", to: roots.skills.appendingPathComponent("custom/SKILL.md"))
        try write("# note", to: roots.notes.appendingPathComponent("workspace/note.md"))
        try write("[]", to: roots.macros)
        try write("name = \"custom\"", to: roots.themes.appendingPathComponent("custom.toml"))
        try write("encrypted", to: roots.encryptedSSHHosts)
        try write("conversation", to: roots.aiConversations.appendingPathComponent("session.jsonl"))
    }

    func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    func dateByAdding(days: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date)!
    }
}
