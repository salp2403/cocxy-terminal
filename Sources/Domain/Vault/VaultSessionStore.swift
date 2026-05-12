// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionStore.swift - Encrypted local vault persistence.

import CryptoKit
import Foundation
import Security

public protocol VaultKeyProviding {
    func keyData() throws -> Data
}

public protocol VaultSessionStoring {
    func loadSessions() throws -> [VaultSession]
    func saveSessions(_ sessions: [VaultSession]) throws
    func upsert(_ session: VaultSession) throws
    func pruneSessions(olderThan cutoff: Date) throws -> [VaultSession]
    func clear() throws
}

public struct StaticVaultKeyProvider: VaultKeyProviding {
    public let keyDataValue: Data

    public init(keyData: Data) {
        keyDataValue = keyData
    }

    public func keyData() throws -> Data {
        guard keyDataValue.count == 32 else {
            throw VaultError.invalidKeyLength(keyDataValue.count)
        }
        return keyDataValue
    }
}

public struct VaultFileKeyProvider: VaultKeyProviding {
    public let keyURL: URL
    public let fileManager: FileManager

    public init(
        keyURL: URL = VaultSessionStore.defaultKeyURL(),
        fileManager: FileManager = .default
    ) {
        self.keyURL = keyURL
        self.fileManager = fileManager
    }

    public func keyData() throws -> Data {
        if fileManager.fileExists(atPath: keyURL.path) {
            let data = try Data(contentsOf: keyURL)
            guard data.count == 32 else {
                throw VaultError.invalidKeyLength(data.count)
            }
            return data
        }

        try fileManager.createDirectory(
            at: keyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let data = Data(bytes)
        try data.write(to: keyURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: keyURL.path)
        return data
    }
}

public struct VaultSessionStore: VaultSessionStoring {
    public let storageURL: URL
    public let keyProvider: any VaultKeyProviding
    public let fileManager: FileManager

    private struct Envelope: Codable {
        let version: Int
        let nonce: Data
        let ciphertext: Data
        let tag: Data
    }

    public init(
        storageURL: URL = Self.defaultStorageURL(),
        keyProvider: any VaultKeyProviding = VaultFileKeyProvider(),
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    public static func defaultStore() -> VaultSessionStore {
        VaultSessionStore()
    }

    public static func defaultStorageURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/vault-sessions.enc")
    }

    public static func defaultKeyURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/vault.key")
    }

    public func loadSessions() throws -> [VaultSession] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: storageURL))
            let key = SymmetricKey(data: try keyProvider.keyData())
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode([VaultSession].self, from: plaintext)
                .sorted { $0.lastSeenAt > $1.lastSeenAt }
        } catch is VaultError {
            throw VaultError.corruptStore
        } catch {
            throw VaultError.corruptStore
        }
    }

    public func saveSessions(_ sessions: [VaultSession]) throws {
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plaintext = try JSONEncoder().encode(sessions.sorted { $0.lastSeenAt > $1.lastSeenAt })
        let key = SymmetricKey(data: try keyProvider.keyData())
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        let envelope = Envelope(
            version: 1,
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: storageURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: storageURL.path)
    }

    public func upsert(_ session: VaultSession) throws {
        var sessions = try loadSessions().filter { $0.id != session.id }
        sessions.append(session)
        try saveSessions(sessions)
    }

    public func pruneSessions(olderThan cutoff: Date) throws -> [VaultSession] {
        let sessions = try loadSessions().filter { $0.lastSeenAt >= cutoff }
        try saveSessions(sessions)
        return sessions
    }

    public func clear() throws {
        try saveSessions([])
    }
}
