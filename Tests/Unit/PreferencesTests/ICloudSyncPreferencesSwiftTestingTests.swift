// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncPreferencesSwiftTestingTests.swift - Preferences coverage for `[icloud-sync]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - iCloud Sync round-trip")
@MainActor
struct ICloudSyncPreferencesSwiftTestingTests {
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

    @Test("init populates iCloud Sync fields from the saved config")
    func initPopulatesICloudSyncFieldsFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            iCloudSync: ICloudSyncConfig(
                enabled: true,
                syncDirectoryName: "CocxyPrivate",
                encryptionRequired: true,
                artifactKinds: [.notebooks, .skills, .settings],
                conflictPolicy: .manual
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.iCloudSyncEnabled == true)
        #expect(vm.iCloudSyncDirectoryName == "CocxyPrivate")
        #expect(vm.iCloudSyncEncryptionRequired == true)
        #expect(vm.iCloudSyncArtifactKinds == [.notebooks, .skills, .settings])
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing iCloud Sync fields marks Preferences dirty and discard restores")
    func changingICloudSyncFieldsMarksPreferencesDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        vm.iCloudSyncEnabled = true
        vm.iCloudSyncDirectoryName = "TeamCocxy"
        vm.iCloudSyncArtifactKinds = [.notebooks, .workflows]

        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.iCloudSyncEnabled == false)
        #expect(vm.iCloudSyncDirectoryName == "Cocxy")
        #expect(vm.iCloudSyncArtifactKinds == Set(ICloudSyncArtifactKind.allCases))
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("unsafe directory names normalize in generated config")
    func unsafeDirectoryNamesNormalizeInGeneratedConfig() {
        let (vm, _) = makeViewModel()

        vm.iCloudSyncEnabled = true
        vm.iCloudSyncDirectoryName = "../Cocxy"

        let toml = vm.generateToml()

        #expect(toml.contains("[icloud-sync]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("sync-directory-name = \"Cocxy\""))
        #expect(toml.contains("encryption-required = true"))
        #expect(toml.contains("conflict-policy = \"manual\""))
    }

    @Test("save then reload preserves iCloud Sync fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.iCloudSyncEnabled = true
        vm.iCloudSyncDirectoryName = "CocxyPrivate"
        vm.iCloudSyncArtifactKinds = [.notebooks, .skills]
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.iCloudSync.enabled == true)
        #expect(service.current.iCloudSync.syncDirectoryName == "CocxyPrivate")
        #expect(service.current.iCloudSync.encryptionRequired == true)
        #expect(service.current.iCloudSync.artifactKinds == [.notebooks, .skills])
        #expect(service.current.iCloudSync.conflictPolicy == .manual)
        #expect(vm.hasUnsavedChanges == false)
    }
}
