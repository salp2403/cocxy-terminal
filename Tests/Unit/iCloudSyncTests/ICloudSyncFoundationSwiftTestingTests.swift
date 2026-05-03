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
