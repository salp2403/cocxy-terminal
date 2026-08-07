// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Security
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror TLS keychain", .serialized)
struct MobileMirrorTLSKeychainSwiftTestingTests {
    @Test("startup sweep uses real process liveness for current boot identities")
    func realProcessLivenessSweep() throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        let reapedProcessIdentifier = child.processIdentifier
        child.waitUntilExit()
        let staleIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: reapedProcessIdentifier
        )
        let activeIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: getpid()
        )

        MobileMirrorEphemeralTLSIdentity.removeStaleKeychainItems(keychain: keychain.reference)

        #expect(keyStatus(staleIdentity.storageKeyTag, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(activeIdentity.storageKeyTag, in: keychain.reference) == errSecSuccess)
    }

    @Test("startup sweep rejects another boot and collects obsolete tag formats")
    func bootAndLegacySweep() throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let currentBoot = try #require(MobileMirrorTLSKeychainOwnership.currentBootSessionIdentifier())
        let staleBoot = UUID().uuidString.lowercased()
        let staleIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: getpid(),
            bootSessionIdentifier: staleBoot
        )
        let activeIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: getpid(),
            bootSessionIdentifier: currentBoot
        )
        let deadV2Tag = Data(
            "dev.cocxy.mobile.tls.v2.91001.\(UUID().uuidString.lowercased())".utf8
        )
        let liveV2Tag = Data(
            "dev.cocxy.mobile.tls.v2.91002.\(UUID().uuidString.lowercased())".utf8
        )
        let legacyTag = Data(
            "dev.cocxy.mobile.tls.\(UUID().uuidString.lowercased())".utf8
        )
        let unrelatedTag = Data("dev.cocxy.tests.unrelated.\(UUID().uuidString)".utf8)
        for tag in [deadV2Tag, liveV2Tag, legacyTag, unrelatedTag] {
            _ = try makeKey(tag: tag, in: keychain.reference)
        }

        MobileMirrorEphemeralTLSIdentity.removeStaleKeychainItems(
            keychain: keychain.reference,
            bootSessionIdentifier: currentBoot,
            processIsAlive: { $0 == 91_002 || $0 == getpid() }
        )

        #expect(keyStatus(staleIdentity.storageKeyTag, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(activeIdentity.storageKeyTag, in: keychain.reference) == errSecSuccess)
        #expect(keyStatus(deadV2Tag, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(liveV2Tag, in: keychain.reference) == errSecSuccess)
        #expect(keyStatus(legacyTag, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(unrelatedTag, in: keychain.reference) == errSecSuccess)
    }

    @Test("temporary keychains stay outside the default search list and sweep old residue")
    func temporaryKeychainIsolationAndCleanup() throws {
        let staleFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-mobile-tests-v2.2147483647.\(UUID().uuidString).keychain-db"
        )
        let stalePath = ProjectPathCanonicalizer.canonicalURL(staleFile).path
        let password = UUID().uuidString
        var staleKeychain: SecKeychain?
        let createStatus = password.withCString { pointer in
            SecKeychainCreate(
                staleFile.path,
                UInt32(password.utf8.count),
                pointer,
                false,
                nil,
                &staleKeychain
            )
        }
        #expect(createStatus == errSecSuccess)
        let resolvedStaleKeychain = try #require(staleKeychain)
        var originalSearchList: CFArray?
        #expect(SecKeychainCopySearchList(&originalSearchList) == errSecSuccess)
        let originalKeychains = try #require(originalSearchList as? [SecKeychain])
        defer {
            SecKeychainSetSearchList(originalKeychains as CFArray)
            SecKeychainDelete(resolvedStaleKeychain)
            try? FileManager.default.removeItem(at: staleFile)
        }
        #expect(SecKeychainSetSearchList(
            (originalKeychains + [resolvedStaleKeychain]) as CFArray
        ) == errSecSuccess)
        #expect(TemporaryMobileMirrorKeychain.defaultSearchListPaths().contains(stalePath))

        let keychain = try TemporaryMobileMirrorKeychain()

        #expect(!FileManager.default.fileExists(atPath: staleFile.path))
        #expect(!TemporaryMobileMirrorKeychain.defaultSearchListPaths().contains(stalePath))
        let keychainPath = ProjectPathCanonicalizer.canonicalURL(keychain.fileURL).path
        #expect(!TemporaryMobileMirrorKeychain.defaultSearchListPaths().contains(keychainPath))
    }

    private func makeKey(tag: Data, in keychain: SecKeychain) throws -> SecKey {
        var error: Unmanaged<CFError>?
        return try #require(SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecUseKeychain as String: keychain,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
            ],
        ] as CFDictionary, &error))
    }

    private func keyStatus(_ tag: Data, in keychain: SecKeychain) -> OSStatus {
        var item: CFTypeRef?
        return SecItemCopyMatching([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecMatchSearchList as String: [keychain],
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)
    }
}
