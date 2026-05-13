// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteManifest")
struct CocxyDRemoteManifestSwiftTestingTests {

    @Test("computes stable SHA-256 hex")
    func computesStableSHA256Hex() {
        let digest = CocxyDRemoteManifest.sha256Hex(for: Data("cocxy-remote".utf8))
        #expect(digest == "459626a11194dc5f48dfe6123fa359d5efa8f537b43d9c9adb0851c059eaeda0")
    }

    @Test("verifies matching binary data")
    func verifiesMatchingBinaryData() {
        let payload = Data("binary-v1".utf8)
        let manifest = CocxyDRemoteManifest(
            version: "1.0.0",
            platform: RemotePlatform(os: "Linux", arch: "x86_64"),
            sha256: CocxyDRemoteManifest.sha256Hex(for: payload),
            sizeBytes: payload.count,
            capabilities: ["session", "proxy", "cli-relay"]
        )

        #expect(manifest.verifies(data: payload))
    }

    @Test("rejects checksum mismatch")
    func rejectsChecksumMismatch() {
        let manifest = CocxyDRemoteManifest(
            version: "1.0.0",
            platform: RemotePlatform(os: "Linux", arch: "x86_64"),
            sha256: "0000",
            sizeBytes: 4,
            capabilities: ["session"]
        )

        #expect(!manifest.verifies(data: Data("nope".utf8)))
    }

    @Test("rejects size mismatch even when checksum field is present")
    func rejectsSizeMismatch() {
        let payload = Data("binary-v1".utf8)
        let manifest = CocxyDRemoteManifest(
            version: "1.0.0",
            platform: RemotePlatform(os: "Linux", arch: "x86_64"),
            sha256: CocxyDRemoteManifest.sha256Hex(for: payload),
            sizeBytes: payload.count + 1,
            capabilities: ["session"]
        )

        #expect(!manifest.verifies(data: payload))
    }

    @Test("round trips through JSON manifest format")
    func roundTripsJSON() throws {
        let manifest = CocxyDRemoteManifest(
            version: "1.0.0",
            platform: RemotePlatform(os: "Darwin", arch: "arm64"),
            sha256: "abc123",
            sizeBytes: 42,
            capabilities: ["session", "proxy"]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(CocxyDRemoteManifest.self, from: data)

        #expect(decoded == manifest)
    }
}
