// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BackupPreferencesSwiftTestingTests.swift - Preferences coverage for `[backup]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Backup round-trip")
@MainActor
struct BackupPreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func makeViewModel(config: CocxyConfig = .defaults) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("init populates Backup fields from the saved config")
    func initPopulatesBackupFieldsFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            backup: BackupConfig(
                enabled: false,
                storageDirectory: "~/Backups/CocxyCustom",
                dailyRetentionCount: 7,
                monthlyRetentionCount: 3,
                artifactKinds: [.settings, .notebooks, .aiConversations]
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.backupEnabled == false)
        #expect(vm.backupStorageDirectory == "~/Backups/CocxyCustom")
        #expect(vm.backupDailyRetentionCount == 7)
        #expect(vm.backupMonthlyRetentionCount == 3)
        #expect(vm.backupArtifactKinds == [.settings, .notebooks, .aiConversations])
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Backup fields marks Preferences dirty and discard restores")
    func changingBackupFieldsMarksPreferencesDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        vm.backupEnabled = false
        vm.backupStorageDirectory = "~/Backups/Other"
        vm.backupDailyRetentionCount = 5
        vm.backupMonthlyRetentionCount = 2
        vm.setBackupArtifactKind(.aiConversations, enabled: true)

        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.backupEnabled == true)
        #expect(vm.backupStorageDirectory == BackupConfig.defaults.storageDirectory)
        #expect(vm.backupDailyRetentionCount == 30)
        #expect(vm.backupMonthlyRetentionCount == 12)
        #expect(!vm.backupArtifactKinds.contains(.aiConversations))
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("artifact toggles keep at least one Backup artifact selected")
    func artifactTogglesKeepAtLeastOneBackupArtifactSelected() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            backup: BackupConfig(artifactKinds: [.settings]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.setBackupArtifactKind(.settings, enabled: false)

        #expect(vm.backupArtifactKinds == [.settings])
    }

    @Test("save then reload preserves Backup fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.backupEnabled = true
        vm.backupStorageDirectory = "~/Backups/CocxyCustom"
        vm.backupDailyRetentionCount = 9
        vm.backupMonthlyRetentionCount = 4
        vm.backupArtifactKinds = [.settings, .notebooks, .aiConversations]
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.backup.enabled == true)
        #expect(service.current.backup.storageDirectory == "~/Backups/CocxyCustom")
        #expect(service.current.backup.dailyRetentionCount == 9)
        #expect(service.current.backup.monthlyRetentionCount == 4)
        #expect(service.current.backup.artifactKinds == [.settings, .notebooks, .aiConversations])
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("manual restore loads snapshots and restores only the selected Backup artifact")
    func manualRestoreLoadsSnapshotsAndRestoresOnlySelectedBackupArtifact() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()
        let manager = LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })
        _ = try manager.createBackup(
            config: BackupConfig(
                enabled: true,
                storageDirectory: fixture.backupRoot.path,
                artifactKinds: [.settings, .notebooks]
            ),
            roots: fixture.roots
        )
        try FileManager.default.removeItem(at: fixture.roots.notebooks.appendingPathComponent("demo.cocxynb"))
        try "changed-settings".write(to: fixture.roots.settings, atomically: true, encoding: .utf8)

        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            backup: BackupConfig(storageDirectory: fixture.backupRoot.path, artifactKinds: [.settings, .notebooks]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let vm = PreferencesViewModel(
            config: config,
            localBackupManager: LocalBackupManager(),
            backupArtifactRoots: fixture.roots
        )

        vm.refreshBackupSnapshots()
        vm.selectBackupArtifactKind(.notebooks)
        vm.restoreSelectedBackupArtifact()

        let restoredNotebook = try String(
            contentsOf: fixture.roots.notebooks.appendingPathComponent("demo.cocxynb"),
            encoding: .utf8
        )
        let settings = try String(contentsOf: fixture.roots.settings, encoding: .utf8)
        #expect(vm.backupSnapshots.count == 1)
        #expect(vm.selectedBackupArtifactKind == .notebooks)
        #expect(restoredNotebook.contains("notebook"))
        #expect(settings == "changed-settings")
        #expect(vm.backupRestoreStatus == "Restored Notebooks from 1 file.")
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("manual restore refuses to run while Preferences has unsaved changes")
    func manualRestoreRefusesToRunWhilePreferencesHasUnsavedChanges() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()
        _ = try LocalBackupManager(now: { fixture.date("2026-05-03T12:00:00Z") })
            .createBackup(
                config: BackupConfig(
                    enabled: true,
                    storageDirectory: fixture.backupRoot.path,
                    artifactKinds: [.notebooks]
                ),
                roots: fixture.roots
            )
        try FileManager.default.removeItem(at: fixture.roots.notebooks.appendingPathComponent("demo.cocxynb"))

        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            backup: BackupConfig(storageDirectory: fixture.backupRoot.path, artifactKinds: [.notebooks]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let vm = PreferencesViewModel(
            config: config,
            localBackupManager: LocalBackupManager(),
            backupArtifactRoots: fixture.roots
        )

        vm.refreshBackupSnapshots()
        vm.backupDailyRetentionCount = 9
        vm.restoreSelectedBackupArtifact()

        #expect(vm.backupRestoreStatus == "Save or discard preference changes before restoring a backup.")
        #expect(!FileManager.default.fileExists(
            atPath: fixture.roots.notebooks.appendingPathComponent("demo.cocxynb").path
        ))
    }
}
