// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteUploader.swift - SHA-256 verified binary upload for cocxyd-remote.

import Foundation

struct CocxyDRemoteBinaryCandidate: Equatable, Sendable {
    let localPath: String
    let remotePath: String
    let manifest: CocxyDRemoteManifest
}

enum CocxyDRemoteUploadReason: Equatable, Sendable {
    case missing
    case checksumMismatch(remote: String, expected: String)
}

struct CocxyDRemoteUploadResult: Equatable, Sendable {
    let uploaded: Bool
    let verified: Bool
    let remotePath: String
    let reason: CocxyDRemoteUploadReason?
}

enum CocxyDRemoteUploadError: Error, Equatable {
    case unsupportedPlatform(os: String, arch: String)
    case bundledBinaryMissing(String)
    case postUploadChecksumMismatch(remote: String, expected: String)
}

@MainActor
final class CocxyDRemoteUploader {
    private weak var executor: (any DaemonDeployExecuting)?

    init(executor: any DaemonDeployExecuting) {
        self.executor = executor
    }

    func uploadIfNeeded(
        _ binary: CocxyDRemoteBinaryCandidate,
        profileID: UUID
    ) async throws -> CocxyDRemoteUploadResult {
        guard let executor else { throw DaemonProtocolError.connectionLost }

        let checksumCommand = Self.remoteChecksumCommand(remotePath: binary.remotePath)
        let remoteChecksum = try await executor.executeRemote(checksumCommand, profileID: profileID)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if remoteChecksum == binary.manifest.sha256 {
            return CocxyDRemoteUploadResult(
                uploaded: false,
                verified: true,
                remotePath: binary.remotePath,
                reason: nil
            )
        }

        let reason: CocxyDRemoteUploadReason = remoteChecksum.isEmpty
            ? .missing
            : .checksumMismatch(remote: remoteChecksum, expected: binary.manifest.sha256)

        _ = try await executor.executeRemote("mkdir -p ~/.cocxy/bin", profileID: profileID)
        try await executor.uploadFile(
            localPath: binary.localPath,
            remotePath: binary.remotePath,
            profileID: profileID
        )
        _ = try await executor.executeRemote(
            "chmod 700 ~/.cocxy/bin && chmod 755 \(binary.remotePath)",
            profileID: profileID
        )
        let postUploadChecksum = try await executor.executeRemote(checksumCommand, profileID: profileID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard postUploadChecksum == binary.manifest.sha256 else {
            throw CocxyDRemoteUploadError.postUploadChecksumMismatch(
                remote: postUploadChecksum,
                expected: binary.manifest.sha256
            )
        }

        return CocxyDRemoteUploadResult(
            uploaded: true,
            verified: true,
            remotePath: binary.remotePath,
            reason: reason
        )
    }

    nonisolated static func remoteChecksumCommand(remotePath: String) -> String {
        let path = remotePath.hasPrefix("~/")
            ? "$HOME/" + remotePath.dropFirst(2)
            : shellQuote(remotePath)
        return "sha256sum \(path) 2>/dev/null | awk '{print $1}'"
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func bundledBinaryCandidate(
        for platform: RemotePlatform,
        resourcesURL: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    ) throws -> CocxyDRemoteBinaryCandidate {
        let binaryName = try bundledBinaryName(for: platform)
        let binaryURL = resourcesURL
            .appendingPathComponent("RemoteDaemon", isDirectory: true)
            .appendingPathComponent(binaryName)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw CocxyDRemoteUploadError.bundledBinaryMissing(binaryURL.path)
        }
        let data = try Data(contentsOf: binaryURL)
        let manifest = CocxyDRemoteManifest(
            version: CocxyVersion.current == "dev" ? "1.0.0" : CocxyVersion.current,
            platform: platform,
            sha256: CocxyDRemoteManifest.sha256Hex(for: data),
            sizeBytes: data.count,
            capabilities: ["session", "proxy", "cli-relay"]
        )
        return CocxyDRemoteBinaryCandidate(
            localPath: binaryURL.path,
            remotePath: "~/.cocxy/bin/cocxyd-remote",
            manifest: manifest
        )
    }

    private nonisolated static func bundledBinaryName(for platform: RemotePlatform) throws -> String {
        let os = platform.os.lowercased()
        let arch = platform.arch.lowercased()
        switch (os, arch) {
        case ("linux", "x86_64"), ("linux", "amd64"):
            return "cocxyd-remote-linux-x86_64"
        case ("linux", "aarch64"), ("linux", "arm64"):
            return "cocxyd-remote-linux-arm64"
        case ("darwin", "arm64"), ("macos", "arm64"):
            return "cocxyd-remote-macos-arm64"
        default:
            throw CocxyDRemoteUploadError.unsupportedPlatform(os: platform.os, arch: platform.arch)
        }
    }
}
