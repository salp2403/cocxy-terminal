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
}
