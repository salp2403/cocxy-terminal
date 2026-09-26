// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorEphemeralTLSIdentity.swift - Session-scoped LAN relay identity.

import Darwin
import Foundation
import Security

enum MobileMirrorTLSIdentityError: Error, Equatable {
    case invalidAddress
    case randomGenerationFailed(OSStatus)
    case keyGenerationFailed
    case publicKeyUnavailable
    case keyIdentifierUnavailable
    case certificateSigningFailed
    case certificateCreationFailed
    case certificateStorageFailed(OSStatus)
    case identityCreationFailed(OSStatus)
    case bootSessionUnavailable
}

final class MobileMirrorEphemeralTLSIdentity: @unchecked Sendable {
    private static let keychainLock = NSLock()
    private static let certificateLabelPrefix = "Cocxy Mobile Pairing "

    let identity: SecIdentity
    let certificate: SecCertificate
    let storageCertificatePublicKeyHash: Data
    let storageKeyTag: Data

    private let keychain: SecKeychain?
    private let lock = NSLock()
    private var removed = false

    private init(
        identity: SecIdentity,
        certificate: SecCertificate,
        keyTag: Data,
        certificatePublicKeyHash: Data,
        keychain: SecKeychain?
    ) {
        self.identity = identity
        self.certificate = certificate
        self.storageCertificatePublicKeyHash = certificatePublicKeyHash
        self.storageKeyTag = keyTag
        self.keychain = keychain
    }

    static func generate(
        bindAddress: String,
        validFor: TimeInterval = MobileMirrorPairingAuthority.sessionTTL + 600,
        now: Date = Date(),
        keychain: SecKeychain? = nil,
        ownerProcessIdentifier: pid_t = getpid(),
        bootSessionIdentifier: String? = MobileMirrorTLSKeychainOwnership.currentBootSessionIdentifier()
    ) throws -> MobileMirrorEphemeralTLSIdentity {
        guard let bootSessionIdentifier,
              let identifier = MobileMirrorTLSKeychainOwnership.storageIdentifier(
            bootSessionIdentifier: bootSessionIdentifier,
            ownerProcessIdentifier: ownerProcessIdentifier,
            identityIdentifier: UUID()
        ) else {
            throw MobileMirrorTLSIdentityError.bootSessionUnavailable
        }
        return try generate(
            bindAddress: bindAddress,
            validFor: validFor,
            now: now,
            keychain: keychain,
            storageIdentifier: identifier
        )
    }

    /// Stores the identity under `storageIdentifier` after the tag prefix. The
    /// startup sweep attributes identities written by earlier tag formats, so
    /// the format is the caller's choice.
    static func generate(
        bindAddress: String,
        validFor: TimeInterval = MobileMirrorPairingAuthority.sessionTTL + 600,
        now: Date = Date(),
        keychain: SecKeychain? = nil,
        storageIdentifier identifier: String
    ) throws -> MobileMirrorEphemeralTLSIdentity {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        let addressBytes = try ipv4Bytes(bindAddress)
        let keyTag = Data("\(MobileMirrorTLSKeychainOwnership.keyTagPrefix)\(identifier)".utf8)
        let label = "\(certificateLabelPrefix)\(identifier)"
        let privateKey = try makePrivateKey(
            tag: keyTag,
            label: label,
            keychain: keychain
        )
        var shouldDeleteKey = true
        defer {
            if shouldDeleteKey { deleteKey(tag: keyTag, keychain: keychain) }
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyBytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw MobileMirrorTLSIdentityError.publicKeyUnavailable
        }
        guard let keyAttributes = SecKeyCopyAttributes(privateKey) as? [String: Any],
              let certificatePublicKeyHash = keyAttributes[
                  kSecAttrApplicationLabel as String
              ] as? Data else {
            throw MobileMirrorTLSIdentityError.keyIdentifierUnavailable
        }
        let certificateDER = try makeCertificate(
            privateKey: privateKey,
            publicKeyBytes: publicKeyBytes,
            addressBytes: addressBytes,
            validFor: max(60, validFor),
            now: now
        )
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw MobileMirrorTLSIdentityError.certificateCreationFailed
        }
        var certificateAttributes: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label,
        ]
        if let keychain {
            certificateAttributes[kSecUseKeychain as String] = keychain
        }
        let addStatus = SecItemAdd(certificateAttributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MobileMirrorTLSIdentityError.certificateStorageFailed(addStatus)
        }
        var shouldDeleteCertificate = true
        defer {
            if shouldDeleteCertificate {
                let certificateStatus = deleteCertificate(
                    publicKeyHash: certificatePublicKeyHash,
                    keychain: keychain
                )
                if !isAbsentOrRemoved(certificateStatus) {
                    shouldDeleteKey = false
                }
            }
        }

        var identity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(keychain, certificate, &identity)
        guard identityStatus == errSecSuccess, let identity else {
            throw MobileMirrorTLSIdentityError.identityCreationFailed(identityStatus)
        }
        shouldDeleteKey = false
        shouldDeleteCertificate = false
        return MobileMirrorEphemeralTLSIdentity(
            identity: identity,
            certificate: certificate,
            keyTag: keyTag,
            certificatePublicKeyHash: certificatePublicKeyHash,
            keychain: keychain
        )
    }

    func removeFromKeychain() {
        lock.lock()
        guard !removed else {
            lock.unlock()
            return
        }
        lock.unlock()
        Self.keychainLock.lock()
        let certificateStatus = Self.deleteCertificate(
            publicKeyHash: storageCertificatePublicKeyHash,
            keychain: keychain
        )
        let keyStatus = Self.isAbsentOrRemoved(certificateStatus)
            ? Self.deleteKey(tag: storageKeyTag, keychain: keychain)
            : certificateStatus
        Self.keychainLock.unlock()
        let succeeded = [certificateStatus, keyStatus].allSatisfy(Self.isAbsentOrRemoved)
        lock.lock()
        removed = succeeded
        lock.unlock()
    }

    static func removeStaleKeychainItems(
        keychain: SecKeychain? = nil,
        bootSessionIdentifier: String? = MobileMirrorTLSKeychainOwnership.currentBootSessionIdentifier(),
        processIsAlive: (pid_t) -> Bool = processIsAlive
    ) {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        let bootTime = MobileMirrorTLSKeychainOwnership.currentBootTime()
        let now = Date()

        let taggedIdentities: [(tag: Data, certificatePublicKeyHash: Data)] =
            matchingAttributes(for: kSecClassKey, keychain: keychain).compactMap { attributes in
                guard let tag = attributes[kSecAttrApplicationTag as String] as? Data,
                      let value = String(data: tag, encoding: .utf8),
                      let certificatePublicKeyHash = attributes[
                          kSecAttrApplicationLabel as String
                      ] as? Data,
                      let owner = MobileMirrorTLSKeychainOwnership.owner(from: value) else {
                    return nil
                }
                let timeline: MobileMirrorTLSKeychainOwnership.Timeline?
                if case .session = owner {
                    timeline = nil
                } else {
                    timeline = certificateTimeline(
                        publicKeyHash: certificatePublicKeyHash,
                        keychain: keychain
                    )
                }
                guard MobileMirrorTLSKeychainOwnership.shouldRemove(
                    owner: owner,
                    timeline: timeline,
                    currentBootSessionIdentifier: bootSessionIdentifier,
                    bootTime: bootTime,
                    now: now,
                    processIsAlive: processIsAlive,
                    processStartTime: MobileMirrorTLSKeychainOwnership.processStartTime
                ) else {
                    return nil
                }
                return (
                    tag: tag,
                    certificatePublicKeyHash: certificatePublicKeyHash
                )
            }
        for identity in taggedIdentities {
            let certificateStatus = deleteCertificate(
                publicKeyHash: identity.certificatePublicKeyHash,
                keychain: keychain
            )
            if isAbsentOrRemoved(certificateStatus) {
                deleteKey(tag: identity.tag, keychain: keychain)
            }
        }
    }

    deinit {
        removeFromKeychain()
    }

    private static func makePrivateKey(
        tag: Data,
        label: String,
        keychain: SecKeychain?
    ) throws -> SecKey {
        var error: Unmanaged<CFError>?
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrLabel as String: label,
            ],
        ]
        if let keychain {
            attributes[kSecUseKeychain as String] = keychain
        }
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw MobileMirrorTLSIdentityError.keyGenerationFailed
        }
        return key
    }

    private static func matchingAttributes(
        for itemClass: CFString,
        keychain: SecKeychain?
    ) -> [[String: Any]] {
        var result: CFTypeRef?
        var query: [String: Any] = [
            kSecClass as String: itemClass,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return [] }
        if let entries = result as? [[String: Any]] { return entries }
        if let entry = result as? [String: Any] { return [entry] }
        return []
    }

    private static func makeCertificate(
        privateKey: SecKey,
        publicKeyBytes: Data,
        addressBytes: Data,
        validFor: TimeInterval,
        now: Date
    ) throws -> Data {
        var serial = Data(count: 16)
        let randomStatus = serial.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw MobileMirrorTLSIdentityError.randomGenerationFailed(randomStatus)
        }
        serial[serial.startIndex] &= 0x7f
        serial[serial.startIndex] |= 0x01

        let signatureAlgorithm = DER.sequence([
            DER.oid([1, 2, 840, 10045, 4, 3, 2]),
        ])
        let commonName = DER.sequence([
            DER.set([
                DER.sequence([
                    DER.oid([2, 5, 4, 3]),
                    DER.utf8String("Cocxy Local Pairing"),
                ]),
            ]),
        ])
        let validity = DER.sequence([
            DER.utcTime(now.addingTimeInterval(
                -MobileMirrorTLSKeychainOwnership.Timeline.certificateBackdate
            )),
            DER.utcTime(now.addingTimeInterval(validFor)),
        ])
        let publicKeyInfo = DER.sequence([
            DER.sequence([
                DER.oid([1, 2, 840, 10045, 2, 1]),
                DER.oid([1, 2, 840, 10045, 3, 1, 7]),
            ]),
            DER.bitString(publicKeyBytes),
        ])
        let extensions = DER.context(tag: 3, value: DER.sequence([
            DER.extensionValue(
                oid: [2, 5, 29, 19],
                critical: true,
                value: DER.sequence([])
            ),
            DER.extensionValue(
                oid: [2, 5, 29, 15],
                critical: true,
                value: DER.wrap(tag: 0x03, value: Data([0x07, 0x80]))
            ),
            DER.extensionValue(
                oid: [2, 5, 29, 37],
                critical: false,
                value: DER.sequence([DER.oid([1, 3, 6, 1, 5, 5, 7, 3, 1])])
            ),
            DER.extensionValue(
                oid: [2, 5, 29, 17],
                critical: false,
                value: DER.sequence([DER.wrap(tag: 0x87, value: addressBytes)])
            ),
        ]))
        let body = DER.sequence([
            DER.context(tag: 0, value: DER.integer(Data([0x02]))),
            DER.integer(serial),
            signatureAlgorithm,
            commonName,
            validity,
            commonName,
            publicKeyInfo,
            extensions,
        ])
        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            body as CFData,
            &signingError
        ) as Data? else {
            throw MobileMirrorTLSIdentityError.certificateSigningFailed
        }
        return DER.sequence([
            body,
            signatureAlgorithm,
            DER.bitString(signature),
        ])
    }

    private static func ipv4Bytes(_ address: String) throws -> Data {
        var value = in_addr()
        guard inet_pton(AF_INET, address, &value) == 1 else {
            throw MobileMirrorTLSIdentityError.invalidAddress
        }
        return withUnsafeBytes(of: value.s_addr) { Data($0) }
    }

    private static func certificateTimeline(
        publicKeyHash: Data,
        keychain: SecKeychain?
    ) -> MobileMirrorTLSKeychainOwnership.Timeline? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrPublicKeyHash as String: publicKeyHash,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let result,
              CFGetTypeID(result) == SecCertificateGetTypeID() else {
            return nil
        }
        let certificate = unsafeDowncast(result, to: SecCertificate.self)
        guard let notBefore = SecCertificateCopyNotValidBeforeDate(certificate) as Date?,
              let notAfter = SecCertificateCopyNotValidAfterDate(certificate) as Date? else {
            return nil
        }
        return MobileMirrorTLSKeychainOwnership.Timeline(notBefore: notBefore, notAfter: notAfter)
    }

    private static func processIsAlive(_ processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func isAbsentOrRemoved(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound
    }

    @discardableResult
    private static func deleteCertificate(
        publicKeyHash: Data,
        keychain: SecKeychain?
    ) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrPublicKeyHash as String: publicKeyHash,
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        return SecItemDelete(query as CFDictionary)
    }

    @discardableResult
    private static func deleteKey(tag: Data, keychain: SecKeychain?) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        return SecItemDelete(query as CFDictionary)
    }
}

private enum DER {
    static func sequence(_ values: [Data]) -> Data {
        wrap(tag: 0x30, value: values.reduce(into: Data()) { $0.append($1) })
    }

    static func set(_ values: [Data]) -> Data {
        wrap(tag: 0x31, value: values.reduce(into: Data()) { $0.append($1) })
    }

    static func context(tag: UInt8, value: Data) -> Data {
        wrap(tag: 0xa0 | tag, value: value)
    }

    static func integer(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        if bytes.isEmpty { bytes = Data([0]) }
        if bytes.first! & 0x80 != 0 { bytes.insert(0, at: 0) }
        return wrap(tag: 0x02, value: bytes)
    }

    static func oid(_ components: [UInt64]) -> Data {
        precondition(components.count >= 2 && components[0] <= 2 && components[1] < 40)
        var bytes = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            var encoded = [UInt8(component & 0x7f)]
            var remaining = component >> 7
            while remaining > 0 {
                encoded.insert(UInt8(remaining & 0x7f) | 0x80, at: 0)
                remaining >>= 7
            }
            bytes.append(contentsOf: encoded)
        }
        return wrap(tag: 0x06, value: bytes)
    }

    static func utf8String(_ value: String) -> Data {
        wrap(tag: 0x0c, value: Data(value.utf8))
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return wrap(tag: 0x17, value: Data(formatter.string(from: date).utf8))
    }

    static func bitString(_ value: Data) -> Data {
        wrap(tag: 0x03, value: Data([0]) + value)
    }

    static func extensionValue(
        oid components: [UInt64],
        critical: Bool,
        value: Data
    ) -> Data {
        var values = [oid(components)]
        if critical { values.append(wrap(tag: 0x01, value: Data([0xff]))) }
        values.append(wrap(tag: 0x04, value: value))
        return sequence(values)
    }

    static func wrap(tag: UInt8, value: Data) -> Data {
        Data([tag]) + encodedLength(value.count) + value
    }

    private static func encodedLength(_ value: Int) -> Data {
        if value < 0x80 { return Data([UInt8(value)]) }
        var remaining = value
        var bytes: [UInt8] = []
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
