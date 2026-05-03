// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncFoundationSwiftTestingTests.swift - Local iCloud sync foundation contracts.

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
