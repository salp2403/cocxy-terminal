// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCommandSignatures

@Suite("Trusted author registry")
struct TrustedAuthorRegistrySwiftTestingTests {
    @Test("registry stores and looks up trusted public keys")
    func registryStoresAndLooksUpTrustedPublicKeys() throws {
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        var registry = TrustedAuthorRegistry()

        let entry = try registry.trust(
            displayName: "Cocxy Templates",
            publicKey: keyPair.publicKey
        )

        #expect(entry.keyID == keyPair.keyID)
        #expect(registry.publicKey(for: keyPair.keyID) == keyPair.publicKey)
        #expect(registry.entries.count == 1)
    }

    @Test("registry persists to disk with private file permissions")
    func registryPersistsToDiskWithPrivateFilePermissions() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let registryURL = tempDirectory.appendingPathComponent("trusted-authors.json")
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        var registry = TrustedAuthorRegistry(fileURL: registryURL)
        _ = try registry.trust(displayName: "Cocxy", publicKey: keyPair.publicKey)
        try registry.save()

        let loaded = try TrustedAuthorRegistry.load(from: registryURL)
        #expect(loaded.publicKey(for: keyPair.keyID) == keyPair.publicKey)

        let attributes = try FileManager.default.attributesOfItem(atPath: registryURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }
}
