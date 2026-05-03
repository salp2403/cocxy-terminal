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

    private func makeViewModel(
        config: CocxyConfig = .defaults,
        iCloudSyncSecrets: ICloudSyncSecrets = ICloudSyncSecrets(store: InMemoryICloudSyncSecretStore()),
        iCloudSyncExporter: any ICloudSyncExporting = RecordingICloudSyncExporter(),
        iCloudSyncArtifactRoots: ICloudSyncArtifactRoots = ICloudSyncArtifactRoots(
            notebooks: URL(fileURLWithPath: "/tmp/cocxy/notebooks", isDirectory: true),
            workflows: URL(fileURLWithPath: "/tmp/cocxy/workflows", isDirectory: true),
            skills: URL(fileURLWithPath: "/tmp/cocxy/skills", isDirectory: true),
            settings: URL(fileURLWithPath: "/tmp/cocxy/config.toml", isDirectory: false),
            themes: URL(fileURLWithPath: "/tmp/cocxy/themes", isDirectory: true)
        )
    ) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        return (
            PreferencesViewModel(
                config: config,
                fileProvider: provider,
                iCloudSyncSecrets: iCloudSyncSecrets,
                iCloudSyncExporter: iCloudSyncExporter,
                iCloudSyncArtifactRoots: iCloudSyncArtifactRoots
            ),
            provider
        )
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

    @Test("iCloud Sync master password saves and deletes through Preferences")
    func iCloudSyncMasterPasswordSaveDelete() throws {
        let secrets = ICloudSyncSecrets(store: InMemoryICloudSyncSecretStore())
        let (vm, _) = makeViewModel(iCloudSyncSecrets: secrets)

        vm.iCloudSyncMasterPasswordDraft = " sync password\n"
        try vm.saveICloudSyncMasterPasswordDraft()

        #expect(vm.iCloudSyncMasterPasswordDraft.isEmpty)
        #expect(vm.iCloudSyncMasterPasswordStatus == "iCloud Sync master password saved.")
        #expect(vm.hasSavedICloudSyncMasterPassword())
        #expect(try secrets.masterPassword() == "sync password")

        try vm.deleteICloudSyncMasterPassword()

        #expect(vm.iCloudSyncMasterPasswordStatus == "iCloud Sync master password deleted.")
        #expect(!vm.hasSavedICloudSyncMasterPassword())
    }

    @Test("manual export uses saved master password and reports exported artifacts")
    func manualExportUsesSavedMasterPasswordAndReportsExportedArtifacts() throws {
        let store = InMemoryICloudSyncSecretStore()
        let secrets = ICloudSyncSecrets(store: store)
        try secrets.saveMasterPassword("sync password")
        let rootURL = URL(fileURLWithPath: "/tmp/cocxy-icloud", isDirectory: true)
        let exporter = RecordingICloudSyncExporter(outcome: .exported(ICloudSyncExportResult(
            rootURL: rootURL,
            manifest: ICloudSyncManifest(entries: []),
            manifestURL: rootURL.appendingPathComponent("manifest.json"),
            writtenArtifactURLs: [
                rootURL.appendingPathComponent("notebooks/daily.cocxynb.cocxyenc"),
                rootURL.appendingPathComponent("settings/config.toml.cocxyenc"),
            ]
        )))
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            iCloudSync: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks, .settings]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(
            config: config,
            iCloudSyncSecrets: secrets,
            iCloudSyncExporter: exporter
        )

        let outcome = try vm.exportICloudSyncArtifactsNow()

        guard case .exported = outcome else {
            Issue.record("Expected exported outcome")
            return
        }
        #expect(exporter.requests.count == 1)
        #expect(exporter.requests[0].config.enabled == true)
        #expect(exporter.requests[0].config.artifactKinds == [.notebooks, .settings])
        #expect(exporter.requests[0].password == "sync password")
        #expect(vm.iCloudSyncExportStatus == "Exported 2 encrypted artifacts.")
    }

    @Test("manual export refuses to run without a saved master password")
    func manualExportRequiresSavedMasterPassword() throws {
        let exporter = RecordingICloudSyncExporter()
        let (vm, _) = makeViewModel(iCloudSyncExporter: exporter)
        vm.iCloudSyncEnabled = true

        #expect(throws: ICloudSyncExportRunError.masterPasswordUnavailable) {
            _ = try vm.exportICloudSyncArtifactsNow()
        }
        #expect(exporter.requests.isEmpty)
    }
}

private final class RecordingICloudSyncExporter: ICloudSyncExporting, @unchecked Sendable {
    struct Request: Equatable {
        let config: ICloudSyncConfig
        let roots: ICloudSyncArtifactRoots
        let password: String
    }

    private(set) var requests: [Request] = []
    var outcome: ICloudSyncExportOutcome

    init(outcome: ICloudSyncExportOutcome = .disabled) {
        self.outcome = outcome
    }

    func exportLocalArtifacts(
        config: ICloudSyncConfig,
        roots: ICloudSyncArtifactRoots,
        password: String
    ) throws -> ICloudSyncExportOutcome {
        requests.append(Request(config: config, roots: roots, password: password))
        return outcome
    }
}
