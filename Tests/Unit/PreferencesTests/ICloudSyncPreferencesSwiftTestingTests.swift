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
        iCloudSyncImporter: any ICloudSyncImporting = RecordingICloudSyncImporter(),
        iCloudSyncConflictResolver: any ICloudSyncConflictResolving = RecordingICloudSyncConflictResolver(),
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
                iCloudSyncImporter: iCloudSyncImporter,
                iCloudSyncConflictResolver: iCloudSyncConflictResolver,
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
    func iCloudSyncMasterPasswordSaveDelete() async throws {
        let secrets = ICloudSyncSecrets(store: InMemoryICloudSyncSecretStore())
        let (vm, _) = makeViewModel(iCloudSyncSecrets: secrets)

        vm.iCloudSyncMasterPasswordDraft = " sync password\n"
        try await vm.saveICloudSyncMasterPasswordDraft()

        #expect(vm.iCloudSyncMasterPasswordDraft.isEmpty)
        #expect(vm.iCloudSyncMasterPasswordStatus == "iCloud Sync master password saved.")
        #expect(vm.hasSavedICloudSyncMasterPassword())
        #expect(try secrets.masterPassword() == "sync password")

        try await vm.deleteICloudSyncMasterPassword()

        #expect(vm.iCloudSyncMasterPasswordStatus == "iCloud Sync master password deleted.")
        #expect(!vm.hasSavedICloudSyncMasterPassword())
    }

    @Test("saved master password availability refreshes asynchronously")
    func savedMasterPasswordAvailabilityRefreshes() async throws {
        let store = InMemoryICloudSyncSecretStore()
        let secrets = ICloudSyncSecrets(store: store)
        try secrets.saveMasterPassword("sync password")
        let (vm, _) = makeViewModel(iCloudSyncSecrets: secrets)

        #expect(vm.iCloudSyncHasSavedMasterPassword == false)
        await vm.refreshICloudSyncMasterPasswordAvailability()

        #expect(vm.iCloudSyncHasSavedMasterPassword)
        #expect(vm.iCloudSyncOperation == nil)
    }

    @Test("manual export uses saved master password and reports exported artifacts")
    func manualExportUsesSavedMasterPasswordAndReportsExportedArtifacts() async throws {
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

        let outcome = try await vm.exportICloudSyncArtifactsNow()

        guard case .exported = outcome else {
            Issue.record("Expected exported outcome")
            return
        }
        #expect(exporter.requests.count == 1)
        #expect(exporter.requests[0].config.enabled == true)
        #expect(exporter.requests[0].config.artifactKinds == [.notebooks, .settings])
        #expect(exporter.requests[0].password == "sync password")
        #expect(exporter.requests[0].ranOnMainThread == false)
        #expect(vm.iCloudSyncExportStatus == "Exported 2 encrypted artifacts.")
    }

    @Test("manual export runs once off the main thread and rejects overlap")
    func manualExportRejectsOverlappingRun() async throws {
        let store = InMemoryICloudSyncSecretStore()
        let secrets = ICloudSyncSecrets(store: store)
        try secrets.saveMasterPassword("sync password")
        let exporter = RecordingICloudSyncExporter(delay: 0.15)
        let (vm, _) = makeViewModel(
            iCloudSyncSecrets: secrets,
            iCloudSyncExporter: exporter
        )
        vm.iCloudSyncEnabled = true

        let firstRun = Task { @MainActor in
            try await vm.exportICloudSyncArtifactsNow()
        }
        while vm.iCloudSyncOperation != .exporting {
            await Task.yield()
        }

        #expect(vm.iCloudSyncIsBusy)
        await #expect(throws: ICloudSyncOperationError.operationInProgress) {
            _ = try await vm.exportICloudSyncArtifactsNow()
        }
        _ = try await firstRun.value

        #expect(exporter.requests.count == 1)
        #expect(exporter.requests[0].ranOnMainThread == false)
        #expect(vm.iCloudSyncOperation == nil)
        #expect(vm.iCloudSyncIsBusy == false)
    }

    @Test("manual export refuses to run without a saved master password")
    func manualExportRequiresSavedMasterPassword() async throws {
        let exporter = RecordingICloudSyncExporter()
        let (vm, _) = makeViewModel(iCloudSyncExporter: exporter)
        vm.iCloudSyncEnabled = true

        await #expect(throws: ICloudSyncManualRunError.masterPasswordUnavailable) {
            _ = try await vm.exportICloudSyncArtifactsNow()
        }
        #expect(exporter.requests.isEmpty)
    }

    @Test("manual import uses saved master password and keeps conflicts for UI")
    func manualImportUsesSavedMasterPasswordAndKeepsConflictsForUI() async throws {
        let store = InMemoryICloudSyncSecretStore()
        let secrets = ICloudSyncSecrets(store: store)
        try secrets.saveMasterPassword("sync password")
        let localEntry = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: "local",
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        let remoteEntry = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: "remote",
            modifiedAt: Date(timeIntervalSince1970: 2)
        )
        let importer = RecordingICloudSyncImporter(outcome: .imported(ICloudSyncImportResult(
            rootURL: URL(fileURLWithPath: "/tmp/cocxy-icloud", isDirectory: true),
            manifest: ICloudSyncManifest(entries: [remoteEntry]),
            importedArtifactURLs: [URL(fileURLWithPath: "/tmp/cocxy/notebooks/new.cocxynb")],
            conflicts: [ICloudSyncImportConflict(local: localEntry, remote: remoteEntry)]
        )))
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            iCloudSync: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(
            config: config,
            iCloudSyncSecrets: secrets,
            iCloudSyncImporter: importer
        )

        let outcome = try await vm.importICloudSyncArtifactsNow()

        guard case .imported = outcome else {
            Issue.record("Expected imported outcome")
            return
        }
        #expect(importer.requests.count == 1)
        #expect(importer.requests[0].config.enabled == true)
        #expect(importer.requests[0].password == "sync password")
        #expect(importer.requests[0].ranOnMainThread == false)
        #expect(vm.iCloudSyncImportStatus == "Imported 1 encrypted artifact; 1 conflict requires manual resolution.")
        #expect(vm.iCloudSyncConflicts == [ICloudSyncImportConflict(local: localEntry, remote: remoteEntry)])
    }

    @Test("manual conflict resolution removes resolved conflict from Preferences")
    func manualConflictResolutionRemovesResolvedConflictFromPreferences() async throws {
        let store = InMemoryICloudSyncSecretStore()
        let secrets = ICloudSyncSecrets(store: store)
        try secrets.saveMasterPassword("sync password")
        let conflict = ICloudSyncImportConflict(
            local: ICloudSyncManifestEntry(
                kind: .notebooks,
                relativePath: "daily.cocxynb",
                contentHash: "local",
                modifiedAt: Date(timeIntervalSince1970: 1)
            ),
            remote: ICloudSyncManifestEntry(
                kind: .notebooks,
                relativePath: "daily.cocxynb",
                contentHash: "remote",
                modifiedAt: Date(timeIntervalSince1970: 2)
            )
        )
        let resolver = RecordingICloudSyncConflictResolver()
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            iCloudSync: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks]),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(
            config: config,
            iCloudSyncSecrets: secrets,
            iCloudSyncConflictResolver: resolver
        )
        vm.iCloudSyncConflicts = [conflict]

        let outcome = try await vm.resolveICloudSyncConflict(conflict, resolution: .keepLocal)

        guard case .resolved = outcome else {
            Issue.record("Expected resolved outcome")
            return
        }
        #expect(resolver.requests.map(\.resolution) == [.keepLocal])
        #expect(resolver.requests[0].ranOnMainThread == false)
        #expect(vm.iCloudSyncConflicts.isEmpty)
        #expect(vm.iCloudSyncImportStatus == "Resolved conflict for daily.cocxynb.")
    }
}

private final class RecordingICloudSyncExporter: ICloudSyncExporting, @unchecked Sendable {
    struct Request: Equatable {
        let config: ICloudSyncConfig
        let roots: ICloudSyncArtifactRoots
        let password: String
        let ranOnMainThread: Bool
    }

    private let lock = NSLock()
    private var storedRequests: [Request] = []
    private let outcome: ICloudSyncExportOutcome
    private let delay: TimeInterval

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(
        outcome: ICloudSyncExportOutcome = .disabled,
        delay: TimeInterval = 0
    ) {
        self.outcome = outcome
        self.delay = delay
    }

    func exportLocalArtifacts(
        config: ICloudSyncConfig,
        roots: ICloudSyncArtifactRoots,
        password: String
    ) throws -> ICloudSyncExportOutcome {
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        lock.lock()
        storedRequests.append(Request(
            config: config,
            roots: roots,
            password: password,
            ranOnMainThread: Thread.isMainThread
        ))
        lock.unlock()
        return outcome
    }
}

private final class RecordingICloudSyncImporter: ICloudSyncImporting, @unchecked Sendable {
    struct Request: Equatable {
        let config: ICloudSyncConfig
        let roots: ICloudSyncArtifactRoots
        let password: String
        let ranOnMainThread: Bool
    }

    private let lock = NSLock()
    private var storedRequests: [Request] = []
    private let outcome: ICloudSyncImportOutcome

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(outcome: ICloudSyncImportOutcome = .disabled) {
        self.outcome = outcome
    }

    func importRemoteArtifacts(
        config: ICloudSyncConfig,
        roots: ICloudSyncArtifactRoots,
        password: String
    ) throws -> ICloudSyncImportOutcome {
        lock.lock()
        storedRequests.append(Request(
            config: config,
            roots: roots,
            password: password,
            ranOnMainThread: Thread.isMainThread
        ))
        lock.unlock()
        return outcome
    }
}

private final class RecordingICloudSyncConflictResolver: ICloudSyncConflictResolving, @unchecked Sendable {
    struct Request: Equatable {
        let config: ICloudSyncConfig
        let conflict: ICloudSyncImportConflict
        let resolution: ICloudSyncConflictResolution
        let roots: ICloudSyncArtifactRoots
        let backupRoot: URL
        let password: String
        let ranOnMainThread: Bool
    }

    private let lock = NSLock()
    private var storedRequests: [Request] = []

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func resolveConflict(
        config: ICloudSyncConfig,
        conflict: ICloudSyncImportConflict,
        resolution: ICloudSyncConflictResolution,
        roots: ICloudSyncArtifactRoots,
        backupRoot: URL,
        password: String
    ) throws -> ICloudSyncConflictResolutionOutcome {
        lock.lock()
        storedRequests.append(Request(
            config: config,
            conflict: conflict,
            resolution: resolution,
            roots: roots,
            backupRoot: backupRoot,
            password: password,
            ranOnMainThread: Thread.isMainThread
        ))
        lock.unlock()
        return .resolved(ICloudSyncConflictResolutionResult(
            conflict: conflict,
            resolution: resolution,
            localURL: URL(fileURLWithPath: "/tmp/cocxy/notebooks/daily.cocxynb"),
            backupURL: nil
        ))
    }
}
