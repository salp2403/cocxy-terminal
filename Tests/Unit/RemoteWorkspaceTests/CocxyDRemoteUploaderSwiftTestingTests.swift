// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteUploader")
struct CocxyDRemoteUploaderSwiftTestingTests {

    @Test("skips upload when remote checksum matches manifest")
    @MainActor func skipsMatchingRemoteChecksum() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let manifest = CocxyDRemoteManifest.fixture(sha256: "remote-sha")
        let binary = CocxyDRemoteBinaryCandidate(
            localPath: "/local/cocxyd-remote",
            remotePath: "~/.cocxy/bin/cocxyd-remote",
            manifest: manifest
        )
        executor.responses[CocxyDRemoteUploader.remoteChecksumCommand(remotePath: binary.remotePath)] = "remote-sha\n"
        let uploader = CocxyDRemoteUploader(executor: executor)

        let result = try await uploader.uploadIfNeeded(binary, profileID: profileID)

        #expect(!result.uploaded)
        #expect(result.verified)
        #expect(executor.uploads.isEmpty)
    }

    @Test("uploads when binary is missing remotely")
    @MainActor func uploadsMissingBinary() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let binary = CocxyDRemoteBinaryCandidate.fixture(sha256: "local-sha")
        executor.responseQueues[CocxyDRemoteUploader.remoteChecksumCommand(remotePath: binary.remotePath)] = [
            "",
            "local-sha\n",
        ]
        let uploader = CocxyDRemoteUploader(executor: executor)

        let result = try await uploader.uploadIfNeeded(binary, profileID: profileID)

        #expect(result.uploaded)
        #expect(executor.uploads.count == 1)
        #expect(executor.uploads.first?.local == binary.localPath)
        #expect(executor.uploads.first?.remote == binary.remotePath)
        #expect(executor.commands.contains("mkdir -p ~/.cocxy/bin"))
        #expect(executor.commands.contains("chmod 700 ~/.cocxy/bin && chmod 755 \(binary.remotePath)"))
    }

    @Test("reuploads when remote checksum differs")
    @MainActor func reuploadsChecksumMismatch() async throws {
        let executor = MockDeployExecutor()
        let binary = CocxyDRemoteBinaryCandidate.fixture(sha256: "expected-sha")
        executor.responseQueues[CocxyDRemoteUploader.remoteChecksumCommand(remotePath: binary.remotePath)] = [
            "old-sha\n",
            "expected-sha\n",
        ]
        let uploader = CocxyDRemoteUploader(executor: executor)

        let result = try await uploader.uploadIfNeeded(binary, profileID: UUID())

        #expect(result.uploaded)
        #expect(result.reason == .checksumMismatch(remote: "old-sha", expected: "expected-sha"))
    }

    @Test("verifies checksum again after upload")
    @MainActor func verifiesChecksumAgainAfterUpload() async throws {
        let executor = MockDeployExecutor()
        let binary = CocxyDRemoteBinaryCandidate.fixture(sha256: "expected-sha")
        let checksumCommand = CocxyDRemoteUploader.remoteChecksumCommand(remotePath: binary.remotePath)
        executor.responseQueues[checksumCommand] = ["old-sha\n", "expected-sha\n"]
        let uploader = CocxyDRemoteUploader(executor: executor)

        let result = try await uploader.uploadIfNeeded(binary, profileID: UUID())

        #expect(result.uploaded)
        #expect(result.verified)
        #expect(executor.commands.filter { $0 == checksumCommand }.count == 2)
    }

    @Test("uses strict shell quoted path for checksum command")
    func checksumCommandQuotesRemotePath() {
        let command = CocxyDRemoteUploader.remoteChecksumCommand(remotePath: "~/.cocxy/bin/cocxyd-remote")
        #expect(command.contains("sha256sum"))
        #expect(command.contains("$HOME/.cocxy/bin/cocxyd-remote"))
        #expect(command.contains("2>/dev/null"))
    }

    @Test("resolves bundled binary candidate for platform")
    func resolvesBundledBinaryCandidateForPlatform() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let daemonDir = root.appendingPathComponent("RemoteDaemon", isDirectory: true)
        try FileManager.default.createDirectory(at: daemonDir, withIntermediateDirectories: true)
        let binaryURL = daemonDir.appendingPathComponent("cocxyd-remote-linux-x86_64")
        try Data("binary".utf8).write(to: binaryURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let candidate = try CocxyDRemoteUploader.bundledBinaryCandidate(
            for: RemotePlatform(os: "Linux", arch: "x86_64"),
            resourcesURL: root
        )

        #expect(candidate.localPath == binaryURL.path)
        #expect(candidate.remotePath == "~/.cocxy/bin/cocxyd-remote")
        #expect(candidate.manifest.sha256 == CocxyDRemoteManifest.sha256Hex(for: Data("binary".utf8)))
        #expect(candidate.manifest.capabilities.contains("session"))
    }
}

private extension CocxyDRemoteManifest {
    static func fixture(sha256: String) -> CocxyDRemoteManifest {
        CocxyDRemoteManifest(
            version: "1.0.0",
            platform: RemotePlatform(os: "Linux", arch: "x86_64"),
            sha256: sha256,
            sizeBytes: 128,
            capabilities: ["session", "proxy", "cli-relay"]
        )
    }
}

private extension CocxyDRemoteBinaryCandidate {
    static func fixture(sha256: String) -> CocxyDRemoteBinaryCandidate {
        CocxyDRemoteBinaryCandidate(
            localPath: "/local/cocxyd-remote",
            remotePath: "~/.cocxy/bin/cocxyd-remote",
            manifest: .fixture(sha256: sha256)
        )
    }
}
