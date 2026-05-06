// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncFoundationSwiftTestingTests.swift - Local iCloud sync foundation contracts.

import CryptoKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("iCloud Sync foundation")
struct ICloudSyncFoundationSwiftTestingTests {
    @Test("root resolver does not query iCloud when sync is disabled")
    func rootResolverDoesNotQueryICloudWhenDisabled() {
        let provider = RecordingICloudContainerProvider(root: URL(fileURLWithPath: "/tmp/iCloudDrive"))
        let resolver = ICloudSyncRootResolver(containerProvider: provider)

        let result = resolver.resolveRoot(for: .defaults)

        #expect(result == .disabled)
        #expect(provider.requestCount == 0)
    }

    @Test("root resolver returns unavailable when enabled without iCloud Drive")
    func rootResolverReturnsUnavailableWhenEnabledWithoutICloudDrive() {
        let provider = RecordingICloudContainerProvider(root: nil)
        let resolver = ICloudSyncRootResolver(containerProvider: provider)
        let config = ICloudSyncConfig(enabled: true)

        let result = resolver.resolveRoot(for: config)

        #expect(result == .unavailable)
        #expect(provider.requestCount == 1)
    }

    @Test("root resolver appends the safe Cocxy sync directory")
    func rootResolverAppendsSafeSyncDirectory() {
        let root = URL(fileURLWithPath: "/tmp/iCloudDrive", isDirectory: true)
        let provider = RecordingICloudContainerProvider(root: root)
        let resolver = ICloudSyncRootResolver(containerProvider: provider)
        let config = ICloudSyncConfig(enabled: true, syncDirectoryName: "CocxyPrivate")

        let result = resolver.resolveRoot(for: config)

        #expect(result == .available(root.appendingPathComponent("CocxyPrivate", isDirectory: true)))
        #expect(provider.requestCount == 1)
    }

    @Test("planner never overwrites divergent artifacts automatically")
    func plannerNeverOverwritesDivergentArtifactsAutomatically() {
        let local = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: "local-hash",
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        let remote = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: "remote-hash",
            modifiedAt: Date(timeIntervalSince1970: 30)
        )
        let planner = ICloudSyncPlanner(conflictPolicy: .manual)

        let plan = planner.plan(local: [local], remote: [remote])

        #expect(plan.operations == [
            .conflict(local: local, remote: remote)
        ])
    }

    @Test("planner separates upload and download operations")
    func plannerSeparatesUploadAndDownloadOperations() {
        let localOnly = ICloudSyncManifestEntry(
            kind: .workflows,
            relativePath: "build.toml",
            contentHash: "local-only",
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let remoteOnly = ICloudSyncManifestEntry(
            kind: .skills,
            relativePath: "review/SKILL.md",
            contentHash: "remote-only",
            modifiedAt: Date(timeIntervalSince1970: 11)
        )
        let planner = ICloudSyncPlanner(conflictPolicy: .manual)

        let plan = planner.plan(local: [localOnly], remote: [remoteOnly])

        #expect(plan.operations == [
            .download(remoteOnly),
            .upload(localOnly)
        ])
    }

    @Test("encryption round trips locally and rejects the wrong password")
    func encryptionRoundTripsLocallyAndRejectsWrongPassword() throws {
        let encryption = ICloudSyncEncryption()
        let plaintext = Data("private notebook body".utf8)

        let sealed = try encryption.seal(plaintext, password: "correct horse battery staple")
        let opened = try encryption.open(sealed, password: "correct horse battery staple")

        #expect(opened == plaintext)
        #expect(throws: ICloudSyncEncryptionError.self) {
            _ = try encryption.open(sealed, password: "wrong password")
        }
    }

    @Test("artifact scanner inventories supported local files only")
    func artifactScannerInventoriesSupportedLocalFilesOnly() throws {
        let root = temporaryDirectory(named: "icloud-sync-scan")
        let roots = try makeArtifactRoots(in: root)
        try "notebook".write(
            to: roots.notebooks.appendingPathComponent("daily.cocxynb"),
            atomically: true,
            encoding: .utf8
        )
        try "ignore".write(
            to: roots.notebooks.appendingPathComponent("scratch.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "workflow".write(
            to: roots.workflows.appendingPathComponent("build.toml"),
            atomically: true,
            encoding: .utf8
        )
        let skillDirectory = roots.skills.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "# Review".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "config".write(to: roots.settings, atomically: true, encoding: .utf8)
        try "theme".write(
            to: roots.themes.appendingPathComponent("solarized.toml"),
            atomically: true,
            encoding: .utf8
        )

        let artifacts = try ICloudSyncArtifactScanner().scan(
            roots: roots,
            kinds: ICloudSyncArtifactKind.allCases
        )

        #expect(artifacts.map(\.entry.kind) == [.notebooks, .workflows, .skills, .settings, .themes])
        #expect(artifacts.map(\.entry.relativePath) == [
            "daily.cocxynb",
            "build.toml",
            "review/SKILL.md",
            "config.toml",
            "solarized.toml"
        ])
        #expect(artifacts.allSatisfy { !$0.entry.contentHash.isEmpty })
    }

    @Test("export service stays inert while sync is disabled")
    func exportServiceStaysInertWhileSyncIsDisabled() throws {
        let root = temporaryDirectory(named: "icloud-sync-disabled")
        let roots = try makeArtifactRoots(in: root.appendingPathComponent("local", isDirectory: true))
        try "notebook".write(
            to: roots.notebooks.appendingPathComponent("daily.cocxynb"),
            atomically: true,
            encoding: .utf8
        )
        let remoteRoot = root.appendingPathComponent("remote", isDirectory: true)
        let provider = RecordingICloudContainerProvider(root: remoteRoot)
        let service = ICloudSyncExportService(
            rootResolver: ICloudSyncRootResolver(containerProvider: provider)
        )

        let outcome = try service.exportLocalArtifacts(
            config: .defaults,
            roots: roots,
            password: "sync password"
        )

        #expect(outcome == .disabled)
        #expect(provider.requestCount == 0)
        #expect(FileManager.default.fileExists(atPath: remoteRoot.path) == false)
    }

    @Test("export service writes encrypted artifacts and manifest with private permissions")
    func exportServiceWritesEncryptedArtifactsAndManifestWithPrivatePermissions() throws {
        let root = temporaryDirectory(named: "icloud-sync-export")
        let roots = try makeArtifactRoots(in: root.appendingPathComponent("local", isDirectory: true))
        let notebookURL = roots.notebooks.appendingPathComponent("daily.cocxynb")
        try "notebook body".write(to: notebookURL, atomically: true, encoding: .utf8)
        let remoteRoot = root.appendingPathComponent("remote", isDirectory: true)
        let provider = RecordingICloudContainerProvider(root: remoteRoot)
        let service = ICloudSyncExportService(
            rootResolver: ICloudSyncRootResolver(containerProvider: provider)
        )
        let config = ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks])

        let outcome = try service.exportLocalArtifacts(
            config: config,
            roots: roots,
            password: "sync password"
        )

        guard case .exported(let result) = outcome else {
            Issue.record("Expected exported outcome")
            return
        }
        #expect(result.manifest.entries.map(\.relativePath) == ["daily.cocxynb"])
        #expect(result.writtenArtifactURLs.count == 1)
        let encryptedData = try Data(contentsOf: result.writtenArtifactURLs[0])
        let decrypted = try ICloudSyncEncryption().open(encryptedData, password: "sync password")
        #expect(String(decoding: decrypted, as: UTF8.self) == "notebook body")
        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path))
        let manifestPermissions = try posixPermissions(at: result.manifestURL)
        let artifactPermissions = try posixPermissions(at: result.writtenArtifactURLs[0])
        #expect(manifestPermissions == 0o600)
        #expect(artifactPermissions == 0o600)
    }

    @Test("import service decrypts remote-only artifacts without overwriting locals")
    func importServiceDecryptsRemoteOnlyArtifactsWithoutOverwritingLocals() throws {
        let root = temporaryDirectory(named: "icloud-sync-import")
        let roots = try makeArtifactRoots(in: root.appendingPathComponent("local", isDirectory: true))
        let remoteContainer = root.appendingPathComponent("remote", isDirectory: true)
        let remoteSyncRoot = remoteContainer.appendingPathComponent("Cocxy", isDirectory: true)
        try FileManager.default.createDirectory(at: remoteSyncRoot, withIntermediateDirectories: true)
        let remoteEntry = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: sha256Hex("remote notebook"),
            modifiedAt: Date(timeIntervalSince1970: 40)
        )
        try writeRemoteManifest([remoteEntry], to: remoteSyncRoot)
        try writeEncryptedRemoteArtifact(
            entry: remoteEntry,
            plaintext: "remote notebook",
            rootURL: remoteSyncRoot,
            password: "sync password"
        )
        let service = ICloudSyncImportService(
            rootResolver: ICloudSyncRootResolver(containerProvider: RecordingICloudContainerProvider(root: remoteContainer))
        )

        let outcome = try service.importRemoteArtifacts(
            config: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks]),
            roots: roots,
            password: "sync password"
        )

        guard case .imported(let result) = outcome else {
            Issue.record("Expected imported outcome")
            return
        }
        let importedURL = roots.notebooks.appendingPathComponent("daily.cocxynb")
        #expect(result.importedArtifactURLs == [importedURL.standardizedFileURL])
        #expect(result.conflicts.isEmpty)
        #expect(try String(contentsOf: importedURL, encoding: .utf8) == "remote notebook")
        #expect(try posixPermissions(at: importedURL) == 0o600)
    }

    @Test("import service reports conflicts and preserves local files")
    func importServiceReportsConflictsAndPreservesLocalFiles() throws {
        let root = temporaryDirectory(named: "icloud-sync-import-conflict")
        let roots = try makeArtifactRoots(in: root.appendingPathComponent("local", isDirectory: true))
        let localURL = roots.notebooks.appendingPathComponent("daily.cocxynb")
        try "local notebook".write(to: localURL, atomically: true, encoding: .utf8)
        let remoteContainer = root.appendingPathComponent("remote", isDirectory: true)
        let remoteSyncRoot = remoteContainer.appendingPathComponent("Cocxy", isDirectory: true)
        try FileManager.default.createDirectory(at: remoteSyncRoot, withIntermediateDirectories: true)
        let remoteEntry = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: sha256Hex("remote notebook"),
            modifiedAt: Date(timeIntervalSince1970: 41)
        )
        try writeRemoteManifest([remoteEntry], to: remoteSyncRoot)
        try writeEncryptedRemoteArtifact(
            entry: remoteEntry,
            plaintext: "remote notebook",
            rootURL: remoteSyncRoot,
            password: "sync password"
        )
        let service = ICloudSyncImportService(
            rootResolver: ICloudSyncRootResolver(containerProvider: RecordingICloudContainerProvider(root: remoteContainer))
        )

        let outcome = try service.importRemoteArtifacts(
            config: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks]),
            roots: roots,
            password: "sync password"
        )

        guard case .imported(let result) = outcome else {
            Issue.record("Expected imported outcome")
            return
        }
        #expect(result.importedArtifactURLs.isEmpty)
        #expect(result.conflicts.count == 1)
        guard let conflict = result.conflicts.first else { return }
        #expect(conflict.local.kind == .notebooks)
        #expect(conflict.local.relativePath == "daily.cocxynb")
        #expect(conflict.local.contentHash == sha256Hex("local notebook"))
        #expect(conflict.remote == remoteEntry)
        #expect(try String(contentsOf: localURL, encoding: .utf8) == "local notebook")
    }

    @Test("conflict resolver can keep local without touching files")
    func conflictResolverCanKeepLocalWithoutTouchingFiles() throws {
        let root = temporaryDirectory(named: "icloud-sync-keep-local")
        let roots = try makeArtifactRoots(in: root.appendingPathComponent("local", isDirectory: true))
        let localURL = roots.notebooks.appendingPathComponent("daily.cocxynb")
        try "local notebook".write(to: localURL, atomically: true, encoding: .utf8)
        let conflict = ICloudSyncImportConflict(
            local: ICloudSyncManifestEntry(
                kind: .notebooks,
                relativePath: "daily.cocxynb",
                contentHash: sha256Hex("local notebook"),
                modifiedAt: Date(timeIntervalSince1970: 1)
            ),
            remote: ICloudSyncManifestEntry(
                kind: .notebooks,
                relativePath: "daily.cocxynb",
                contentHash: sha256Hex("remote notebook"),
                modifiedAt: Date(timeIntervalSince1970: 2)
            )
        )
        let service = ICloudSyncConflictResolutionService()

        let outcome = try service.resolveConflict(
            config: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks]),
            conflict: conflict,
            resolution: .keepLocal,
            roots: roots,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            password: "sync password"
        )

        guard case .resolved(let result) = outcome else {
            Issue.record("Expected resolved outcome")
            return
        }
        #expect(result.resolution == .keepLocal)
        #expect(result.backupURL == nil)
        #expect(try String(contentsOf: localURL, encoding: .utf8) == "local notebook")
    }

    @Test("conflict resolver uses remote only after backing up local")
    func conflictResolverUsesRemoteOnlyAfterBackingUpLocal() throws {
        let root = temporaryDirectory(named: "icloud-sync-use-remote")
        let roots = try makeArtifactRoots(in: root.appendingPathComponent("local", isDirectory: true))
        let localURL = roots.notebooks.appendingPathComponent("daily.cocxynb")
        try "local notebook".write(to: localURL, atomically: true, encoding: .utf8)
        let remoteContainer = root.appendingPathComponent("remote", isDirectory: true)
        let remoteSyncRoot = remoteContainer.appendingPathComponent("Cocxy", isDirectory: true)
        try FileManager.default.createDirectory(at: remoteSyncRoot, withIntermediateDirectories: true)
        let localEntry = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: sha256Hex("local notebook"),
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        let remoteEntry = ICloudSyncManifestEntry(
            kind: .notebooks,
            relativePath: "daily.cocxynb",
            contentHash: sha256Hex("remote notebook"),
            modifiedAt: Date(timeIntervalSince1970: 2)
        )
        try writeEncryptedRemoteArtifact(
            entry: remoteEntry,
            plaintext: "remote notebook",
            rootURL: remoteSyncRoot,
            password: "sync password"
        )
        let service = ICloudSyncConflictResolutionService(
            rootResolver: ICloudSyncRootResolver(containerProvider: RecordingICloudContainerProvider(root: remoteContainer))
        )

        let outcome = try service.resolveConflict(
            config: ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks]),
            conflict: ICloudSyncImportConflict(local: localEntry, remote: remoteEntry),
            resolution: .useRemote,
            roots: roots,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            password: "sync password"
        )

        guard case .resolved(let result) = outcome else {
            Issue.record("Expected resolved outcome")
            return
        }
        let backupURL = try #require(result.backupURL)
        #expect(result.resolution == .useRemote)
        #expect(result.localURL == localURL.standardizedFileURL)
        #expect(try String(contentsOf: localURL, encoding: .utf8) == "remote notebook")
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == "local notebook")
        #expect(try posixPermissions(at: localURL) == 0o600)
        #expect(try posixPermissions(at: backupURL) == 0o600)
    }

    @Test("local two device smoke exports imports and resolves manual conflicts")
    func localTwoDeviceSmokeExportsImportsAndResolvesManualConflicts() throws {
        let root = temporaryDirectory(named: "icloud-sync-two-device")
        let deviceARoots = try makeArtifactRoots(in: root.appendingPathComponent("device-a", isDirectory: true))
        let deviceBRoots = try makeArtifactRoots(in: root.appendingPathComponent("device-b", isDirectory: true))
        let remoteContainer = root.appendingPathComponent("ubiquity", isDirectory: true)
        let provider = RecordingICloudContainerProvider(root: remoteContainer)
        let rootResolver = ICloudSyncRootResolver(containerProvider: provider)
        let config = ICloudSyncConfig(enabled: true, artifactKinds: [.notebooks, .settings])
        let password = "sync password"

        let deviceANotebook = deviceARoots.notebooks.appendingPathComponent("daily.cocxynb")
        try "device A v1".write(to: deviceANotebook, atomically: true, encoding: .utf8)
        try "theme = \"dark\"".write(to: deviceARoots.settings, atomically: true, encoding: .utf8)

        let exporter = ICloudSyncExportService(rootResolver: rootResolver)
        let initialExport = try exporter.exportLocalArtifacts(
            config: config,
            roots: deviceARoots,
            password: password
        )
        guard case .exported(let initialExportResult) = initialExport else {
            Issue.record("Expected initial export")
            return
        }
        #expect(initialExportResult.manifest.entries.map(\.relativePath) == ["daily.cocxynb", "config.toml"])

        let importer = ICloudSyncImportService(rootResolver: rootResolver)
        let firstImport = try importer.importRemoteArtifacts(
            config: config,
            roots: deviceBRoots,
            password: password
        )
        guard case .imported(let firstImportResult) = firstImport else {
            Issue.record("Expected first import")
            return
        }
        let deviceBNotebook = deviceBRoots.notebooks.appendingPathComponent("daily.cocxynb")
        #expect(firstImportResult.conflicts.isEmpty)
        #expect(Set(firstImportResult.importedArtifactURLs) == [
            deviceBNotebook.standardizedFileURL,
            deviceBRoots.settings.standardizedFileURL,
        ])
        #expect(try String(contentsOf: deviceBNotebook, encoding: .utf8) == "device A v1")

        try "device A v2".write(to: deviceANotebook, atomically: true, encoding: .utf8)
        _ = try exporter.exportLocalArtifacts(config: config, roots: deviceARoots, password: password)
        try "device B local edit".write(to: deviceBNotebook, atomically: true, encoding: .utf8)

        let conflictedImport = try importer.importRemoteArtifacts(
            config: config,
            roots: deviceBRoots,
            password: password
        )
        guard case .imported(let conflictedImportResult) = conflictedImport else {
            Issue.record("Expected conflicted import")
            return
        }
        #expect(conflictedImportResult.importedArtifactURLs.isEmpty)
        #expect(conflictedImportResult.conflicts.count == 1)
        let conflict = try #require(conflictedImportResult.conflicts.first)
        #expect(conflict.local.relativePath == "daily.cocxynb")
        #expect(conflict.remote.relativePath == "daily.cocxynb")
        #expect(try String(contentsOf: deviceBNotebook, encoding: .utf8) == "device B local edit")

        let resolver = ICloudSyncConflictResolutionService(rootResolver: rootResolver)
        let resolution = try resolver.resolveConflict(
            config: config,
            conflict: conflict,
            resolution: .useRemote,
            roots: deviceBRoots,
            backupRoot: root.appendingPathComponent("conflict-backups", isDirectory: true),
            password: password
        )
        guard case .resolved(let resolutionResult) = resolution else {
            Issue.record("Expected conflict resolution")
            return
        }
        let backupURL = try #require(resolutionResult.backupURL)
        #expect(resolutionResult.localURL == deviceBNotebook.standardizedFileURL)
        #expect(try String(contentsOf: deviceBNotebook, encoding: .utf8) == "device A v2")
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == "device B local edit")
        #expect(try posixPermissions(at: deviceBNotebook) == 0o600)
        #expect(try posixPermissions(at: backupURL) == 0o600)
    }
}

private final class RecordingICloudContainerProvider: ICloudContainerProviding, @unchecked Sendable {
    private let root: URL?
    private(set) var requestCount = 0

    init(root: URL?) {
        self.root = root
    }

    func iCloudDocumentsDirectory() -> URL? {
        requestCount += 1
        return root
    }
}

private func makeArtifactRoots(in root: URL) throws -> ICloudSyncArtifactRoots {
    let roots = ICloudSyncArtifactRoots(
        notebooks: root.appendingPathComponent("notebooks", isDirectory: true),
        workflows: root.appendingPathComponent("workflows", isDirectory: true),
        skills: root.appendingPathComponent("skills", isDirectory: true),
        settings: root.appendingPathComponent("config.toml", isDirectory: false),
        themes: root.appendingPathComponent("themes", isDirectory: true)
    )
    try [
        roots.notebooks,
        roots.workflows,
        roots.skills,
        roots.themes
    ].forEach {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
    }
    return roots
}

private func temporaryDirectory(named name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return attributes[.posixPermissions] as? Int ?? -1
}

private func writeRemoteManifest(_ entries: [ICloudSyncManifestEntry], to rootURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let manifest = ICloudSyncManifest(generatedAt: Date(timeIntervalSince1970: 42), entries: entries)
    try encoder.encode(manifest).write(to: rootURL.appendingPathComponent("manifest.json"), options: .atomic)
}

private func writeEncryptedRemoteArtifact(
    entry: ICloudSyncManifestEntry,
    plaintext: String,
    rootURL: URL,
    password: String
) throws {
    let destination = rootURL
        .appendingPathComponent(entry.kind.rawValue, isDirectory: true)
        .appendingPathComponent(entry.relativePath + ".cocxyenc", isDirectory: false)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encrypted = try ICloudSyncEncryption().seal(Data(plaintext.utf8), password: password)
    try encrypted.write(to: destination, options: .atomic)
}

private func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
