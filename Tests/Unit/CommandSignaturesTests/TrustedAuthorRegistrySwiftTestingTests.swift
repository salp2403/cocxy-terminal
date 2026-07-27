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

    @Test("default registry path is shared under Cocxy security storage")
    func defaultRegistryPathIsCanonical() {
        #expect(TrustedAuthorRegistry.defaultFileURL.path.hasSuffix(
            "/.cocxy/security/trusted-authors.json"
        ))
    }

    @Test("default loading fails closed for malformed registry data")
    func defaultLoadingFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registryURL = directory.appendingPathComponent("trusted-authors.json")
        try Data("not-json".utf8).write(to: registryURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: registryURL.path
        )

        let registry = TrustedAuthorRegistry.loadDefault(from: registryURL)

        #expect(registry.entries.isEmpty)
        #expect(registry.fileURL == registryURL)
    }

    @Test("registry rejects duplicate trust identities before persistence")
    func registryRejectsDuplicateKeyIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let entry = TrustedAuthorEntry(
            keyID: keyPair.keyID,
            displayName: "Cocxy",
            publicKey: keyPair.publicKey
        )
        let registry = TrustedAuthorRegistry(
            entries: [entry, entry],
            fileURL: directory.appendingPathComponent("trusted-authors.json")
        )

        #expect(throws: TrustedAuthorRegistryError.duplicateKeyID(keyPair.keyID)) {
            try registry.save()
        }
    }

    @Test("registry refuses symbolic-link storage")
    func registryRejectsSymbolicLinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("trusted-authors.json")
        try Data("[]".utf8).write(to: target)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: TrustedAuthorRegistryError.unsafeRegistryFile) {
            _ = try TrustedAuthorRegistry.load(from: link)
        }
    }
}
