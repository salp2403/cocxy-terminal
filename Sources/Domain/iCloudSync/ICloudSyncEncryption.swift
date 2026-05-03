// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncEncryption.swift - Password-based local encryption for synced artifacts.

import CryptoKit
import Foundation
import Security

enum ICloudSyncEncryptionError: Error, Sendable, Equatable {
    case emptyPassword
    case randomGenerationFailed
    case invalidEnvelope
    case unsupportedEnvelope
    case authenticationFailed
}

struct ICloudSyncEncryption: Sendable {
    private static let algorithm = "AES.GCM.HKDF-SHA256"
    private static let envelopeVersion = 1
    private static let saltByteCount = 16
    private static let keyInfo = Data("cocxy-icloud-sync-v1".utf8)

    func seal(_ plaintext: Data, password: String) throws -> Data {
        let salt = try Self.randomData(byteCount: Self.saltByteCount)
        let key = try Self.deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw ICloudSyncEncryptionError.invalidEnvelope
        }

        let envelope = ICloudSyncEncryptedEnvelope(
            version: Self.envelopeVersion,
            algorithm: Self.algorithm,
            salt: salt.base64EncodedString(),
            combined: combined.base64EncodedString()
        )
        return try JSONEncoder().encode(envelope)
    }

    func open(_ encrypted: Data, password: String) throws -> Data {
        let envelope: ICloudSyncEncryptedEnvelope
        do {
            envelope = try JSONDecoder().decode(ICloudSyncEncryptedEnvelope.self, from: encrypted)
        } catch {
            throw ICloudSyncEncryptionError.invalidEnvelope
        }

        guard envelope.version == Self.envelopeVersion,
              envelope.algorithm == Self.algorithm else {
            throw ICloudSyncEncryptionError.unsupportedEnvelope
        }
        guard let salt = Data(base64Encoded: envelope.salt),
              let combined = Data(base64Encoded: envelope.combined) else {
            throw ICloudSyncEncryptionError.invalidEnvelope
        }

        let key = try Self.deriveKey(password: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ICloudSyncEncryptionError.authenticationFailed
        }
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ICloudSyncEncryptionError.emptyPassword
        }

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(trimmed.utf8)),
            salt: salt,
            info: keyInfo,
            outputByteCount: 32
        )
    }

    private static func randomData(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw ICloudSyncEncryptionError.randomGenerationFailed
        }
        return Data(bytes)
    }
}

private struct ICloudSyncEncryptedEnvelope: Codable, Sendable {
    let version: Int
    let algorithm: String
    let salt: String
    let combined: String
}
