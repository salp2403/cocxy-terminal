// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct TrustedAuthorEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { keyID }
    public let keyID: String
    public let displayName: String
    public let publicKey: SignaturePublicKey
    public let trustedAt: Date

    public init(
        keyID: String,
        displayName: String,
        publicKey: SignaturePublicKey,
        trustedAt: Date = Date()
    ) {
        self.keyID = keyID
        self.displayName = displayName
        self.publicKey = publicKey
        self.trustedAt = trustedAt
    }
}

public struct TrustedAuthorRegistry: Sendable {
    public private(set) var entries: [TrustedAuthorEntry]
    public let fileURL: URL?

    public init(entries: [TrustedAuthorEntry] = [], fileURL: URL? = nil) {
        self.entries = entries.sorted { $0.displayName < $1.displayName }
        self.fileURL = fileURL
    }

    @discardableResult
    public mutating func trust(
        displayName: String,
        publicKey: SignaturePublicKey,
        trustedAt: Date = Date()
    ) throws -> TrustedAuthorEntry {
        let entry = TrustedAuthorEntry(
            keyID: publicKey.keyID,
            displayName: displayName,
            publicKey: publicKey,
            trustedAt: trustedAt
        )
        entries.removeAll { $0.keyID == publicKey.keyID }
        entries.append(entry)
        entries.sort { $0.displayName < $1.displayName }
        return entry
    }

    public mutating func remove(keyID: String) {
        entries.removeAll { $0.keyID == keyID }
    }

    public func publicKey(for keyID: String) -> SignaturePublicKey? {
        entries.first { $0.keyID == keyID }?.publicKey
    }

    public func save() throws {
        guard let fileURL else { return }
        try Self.save(entries, to: fileURL)
    }

    public static func load(from fileURL: URL) throws -> TrustedAuthorRegistry {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TrustedAuthorRegistry(fileURL: fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([TrustedAuthorEntry].self, from: data)
        return TrustedAuthorRegistry(entries: entries, fileURL: fileURL)
    }

    static func save(_ entries: [TrustedAuthorEntry], to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
