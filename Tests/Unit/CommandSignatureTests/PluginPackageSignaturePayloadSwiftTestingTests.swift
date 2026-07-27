// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyCommandSignatures

@Suite("Plugin package signature payload")
struct PluginPackageSignaturePayloadSwiftTestingTests {
    @Test("payload is deterministic and covers nested executable content")
    func payloadIsDeterministicAndCoversScripts() throws {
        let first = try makePluginDirectory(name: "first", reverseCreationOrder: false)
        let second = try makePluginDirectory(name: "second", reverseCreationOrder: true)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let firstPayload = try PluginPackageSignaturePayload.payload(at: first)
        let secondPayload = try PluginPackageSignaturePayload.payload(at: second)
        #expect(firstPayload == secondPayload)

        try "echo changed\n".write(
            to: second.appendingPathComponent("scripts/on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        #expect(try PluginPackageSignaturePayload.payload(at: second) != firstPayload)
    }

    @Test("embedded signature metadata and generic sidecar are excluded")
    func signatureMetadataIsExcluded() throws {
        let directory = try makePluginDirectory(name: "metadata", reverseCreationOrder: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifestURL = directory.appendingPathComponent("cocxy-plugin.toml")
        let unsignedPayload = try PluginPackageSignaturePayload.payload(at: directory)

        try """
        name = "Signed Plugin"
        version = "1.0.0"
        events = ["session-start"]
        signature = "base64"
        signature-algorithm = "ed25519"
        signature-key-id = "key"
        signature-author = "Author"
        signature-timestamp = "2027-01-15T08:00:00Z"
        signature-payload-sha256 = "digest"
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        try Data("sidecar".utf8).write(
            to: directory.appendingPathComponent(".cocxy-signature.json")
        )

        #expect(try PluginPackageSignaturePayload.payload(at: directory) == unsignedPayload)
    }

    @Test("payload rejects symbolic links instead of signing their current target")
    func payloadRejectsSymbolicLinks() throws {
        let directory = try makePluginDirectory(name: "symlink", reverseCreationOrder: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("on-command-complete.sh"),
            withDestinationURL: directory.appendingPathComponent("scripts/on-session-start.sh")
        )

        #expect(throws: PluginPackageSignaturePayloadError.self) {
            _ = try PluginPackageSignaturePayload.payload(at: directory)
        }
    }

    @Test("payload requires the marketplace manifest")
    func payloadRequiresManifest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-signature-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "echo no manifest\n".write(
            to: directory.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        #expect(
            throws: PluginPackageSignaturePayloadError.missingManifest("cocxy-plugin.toml")
        ) {
            _ = try PluginPackageSignaturePayload.payload(at: directory)
        }
    }

    private func makePluginDirectory(
        name: String,
        reverseCreationOrder: Bool
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-signature-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent("cocxy-plugin.toml")
        let scriptsURL = directory.appendingPathComponent("scripts", isDirectory: true)
        let scriptURL = scriptsURL.appendingPathComponent("on-session-start.sh")
        let manifest = """
        name = "Signed Plugin"
        version = "1.0.0"
        events = ["session-start"]
        """

        if reverseCreationOrder {
            try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
            try "echo signed\n".write(to: scriptURL, atomically: true, encoding: .utf8)
            try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        } else {
            try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
            try "echo signed\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        }
        return directory
    }
}
