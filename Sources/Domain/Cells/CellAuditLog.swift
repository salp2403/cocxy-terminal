// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellAuditLog.swift - Encrypted local audit log for Cocxy Cells.

import CryptoKit
import Foundation

#if canImport(Security)
import Security
#endif

enum CellAuditLogError: Error, Equatable, Sendable {
    case corruptStore
    case invalidKeyLength(Int)
    case randomKeyGenerationFailed
}

protocol CellAuditKeyProviding: Sendable {
    func keyData() throws -> Data
}

protocol CellAuditLogging: Sendable {
    func append(_ event: CellAuditEvent) throws
}

struct StaticCellAuditKeyProvider: CellAuditKeyProviding {
    let keyDataValue: Data

    init(keyData: Data) {
        keyDataValue = keyData
    }

    func keyData() throws -> Data {
        guard keyDataValue.count == 32 else {
            throw CellAuditLogError.invalidKeyLength(keyDataValue.count)
        }
        return keyDataValue
    }
}

struct CellFileAuditKeyProvider: CellAuditKeyProviding {
    let keyURL: URL
    let fileManager: FileManager

    init(
        keyURL: URL = CellAuditLog.defaultAuditKeyURL(),
        fileManager: FileManager = .default
    ) {
        self.keyURL = keyURL
        self.fileManager = fileManager
    }

    func keyData() throws -> Data {
        if fileManager.fileExists(atPath: keyURL.path) {
            let data = try Data(contentsOf: keyURL)
            guard data.count == 32 else {
                throw CellAuditLogError.invalidKeyLength(data.count)
            }
            return data
        }

        try fileManager.createDirectory(
            at: keyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CellAuditLogError.randomKeyGenerationFailed
        }
        #else
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        #endif
        let data = Data(bytes)
        try data.write(to: keyURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: keyURL.path
        )
        return data
    }
}

struct CellAuditLog: Sendable {
    let auditURL: URL
    let keyProvider: any CellAuditKeyProviding
    let fileManager: FileManager

    private struct Envelope: Codable {
        let version: Int
        let combined: Data
    }

    private struct StoredEvents: Codable {
        let version: Int
        let events: [CellAuditEvent]
    }

    init(
        auditURL: URL = Self.defaultAuditURL(),
        keyProvider: any CellAuditKeyProviding = CellFileAuditKeyProvider(),
        fileManager: FileManager = .default
    ) {
        self.auditURL = auditURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    static func defaultAuditURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/cells-audit.enc")
    }

    static func defaultAuditKeyURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/cells-audit.key")
    }

    func append(_ event: CellAuditEvent) throws {
        var events = try loadEvents()
        events.append(event)
        try save(events)
    }

    func loadEvents() throws -> [CellAuditEvent] {
        guard fileManager.fileExists(atPath: auditURL.path) else { return [] }

        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: auditURL))
            let key = SymmetricKey(data: try keyProvider.keyData())
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.combined)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            let stored = try JSONDecoder().decode(StoredEvents.self, from: plaintext)
            return stored.events
        } catch {
            throw CellAuditLogError.corruptStore
        }
    }

    private func save(_ events: [CellAuditEvent]) throws {
        try fileManager.createDirectory(
            at: auditURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stored = StoredEvents(version: 1, events: events)
        let plaintext = try JSONEncoder().encode(stored)
        let key = SymmetricKey(data: try keyProvider.keyData())
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw CellAuditLogError.corruptStore
        }
        let envelope = Envelope(
            version: 1,
            combined: combined
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: auditURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: auditURL.path
        )
    }
}

extension CellAuditLog: CellAuditLogging {}
