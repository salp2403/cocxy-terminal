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

    @Test("pre-boot-session identities are collected only when their owner cannot still run")
    func legacyIdentitiesFollowTheirCertificateTimeline() throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let now = Date()
        let boot = try LaunchdBootIdentity.currentLegacyBootTime()
        let bootTime = Date(timeIntervalSince1970: TimeInterval(try #require(boot.legacySeconds)))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        var retained: [MobileMirrorEphemeralTLSIdentity] = []
        func legacy(
            _ suffix: String,
            createdAt: Date = now,
            validFor: TimeInterval = MobileMirrorPairingAuthority.sessionTTL + 600
        ) throws -> Data {
            let identity = try MobileMirrorEphemeralTLSIdentity.generateForTesting(
                bindAddress: "127.0.0.1",
                validFor: validFor,
                now: createdAt,
                keychain: keychain.reference,
                storageIdentifier: suffix
            )
            retained.append(identity)
            #expect(keyStatus(identity.storageKeyTag, in: keychain.reference) == errSecSuccess)
            return identity.storageKeyTag
        }
        let owner = getpid()
        let currentV1 = try legacy(UUID().uuidString.lowercased())
        let expiredV1 = try legacy(
            UUID().uuidString.lowercased(),
            createdAt: now.addingTimeInterval(-120),
            validFor: 60
        )
        let preBootV1 = try legacy(
            UUID().uuidString.lowercased(),
            createdAt: bootTime.addingTimeInterval(-3_600),
            validFor: now.timeIntervalSince(bootTime) + 7_200
        )
        let currentV2 = try legacy("v2.\(owner).\(UUID().uuidString.lowercased())")
        let preBootV2 = try legacy(
            "v2.\(owner).\(UUID().uuidString.lowercased())",
            createdAt: bootTime.addingTimeInterval(-3_600),
            validFor: now.timeIntervalSince(bootTime) + 7_200
        )
        let expiredV2 = try legacy(
            "v2.\(owner).\(UUID().uuidString.lowercased())",
            createdAt: now.addingTimeInterval(-120),
            validFor: 60
        )
        try child.run()
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        let recycledV2 = try legacy(
            "v2.\(child.processIdentifier).\(UUID().uuidString.lowercased())",
            createdAt: now.addingTimeInterval(-10)
        )

        MobileMirrorEphemeralTLSIdentity.removeStaleKeychainItems(keychain: keychain.reference)

        #expect(keyStatus(currentV1, in: keychain.reference) == errSecSuccess)
        #expect(keyStatus(expiredV1, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(preBootV1, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(currentV2, in: keychain.reference) == errSecSuccess)
        #expect(keyStatus(preBootV2, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(expiredV2, in: keychain.reference) == errSecItemNotFound)
        #expect(keyStatus(recycledV2, in: keychain.reference) == errSecItemNotFound)
        withExtendedLifetime(retained) {}
    }

    @Test("startup sweep treats a process it may not signal as alive")
    func unsignalableOwnerStaysAlive() throws {
        let signalResult = kill(1, 0)
        let signalError = errno
        #expect(signalResult == -1 && signalError == EPERM)
        let keychain = try TemporaryMobileMirrorKeychain()
        let launchdOwned = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: 1
        )

        MobileMirrorEphemeralTLSIdentity.removeStaleKeychainItems(keychain: keychain.reference)

        #expect(keyStatus(launchdOwned.storageKeyTag, in: keychain.reference) == errSecSuccess)
    }

    @Test("startup sweep ignores foreign tags that only share the prefix length")
    func foreignPrefixIsIgnored() throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let currentBoot = try #require(MobileMirrorTLSKeychainOwnership.currentBootSessionIdentifier())
        let foreignPrefix = "dev.cocxy.mobile.tlz."
        #expect(foreignPrefix.count == MobileMirrorTLSKeychainOwnership.keyTagPrefix.count)
        let foreignTag = Data(
            "\(foreignPrefix)v3.\(UUID().uuidString.lowercased()).91003.\(UUID().uuidString.lowercased())"
                .utf8
        )
        _ = try makeKey(tag: foreignTag, in: keychain.reference)

        MobileMirrorEphemeralTLSIdentity.removeStaleKeychainItems(
            keychain: keychain.reference,
            bootSessionIdentifier: currentBoot,
            processIsAlive: { _ in false }
        )

        #expect(keyStatus(foreignTag, in: keychain.reference) == errSecSuccess)
    }

    @Test("temporary keychains never change the user search list and sweep old residue")
    func temporaryKeychainIsolationAndCleanup() throws {
        let userSearchList = TemporaryMobileMirrorKeychain.defaultSearchListPaths()
        let staleFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-mobile-tests-v2.2147483647.\(UUID().uuidString).keychain-db"
        )
        #expect(FileManager.default.createFile(atPath: staleFile.path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: staleFile) }

        var keychain: TemporaryMobileMirrorKeychain? = try TemporaryMobileMirrorKeychain()
        let keychainFile = try #require(keychain?.fileURL)

        #expect(!FileManager.default.fileExists(atPath: staleFile.path))
        #expect(TemporaryMobileMirrorKeychain.defaultSearchListPaths() == userSearchList)
        keychain = nil
        #expect(!FileManager.default.fileExists(atPath: keychainFile.path))
        #expect(TemporaryMobileMirrorKeychain.defaultSearchListPaths() == userSearchList)
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
