// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation

public enum TrustedAuthorRegistryError: Error, Equatable, Sendable {
    case unsafeRegistryFile
    case registryTooLarge(Int)
    case tooManyEntries(Int)
    case invalidEntry(String)
    case duplicateKeyID(String)
}

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
    public static let maximumFileBytes = 4 * 1_024 * 1_024
    public static let maximumEntries = 4_096
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/security/trusted-authors.json")
    }

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
        try Self.validate([entry])
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
        let data = try readRegistryData(from: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([TrustedAuthorEntry].self, from: data)
        try validate(entries)
        return TrustedAuthorRegistry(entries: entries, fileURL: fileURL)
    }

    /// Loads persisted trust without ever promoting malformed data to trusted state.
    public static func loadDefault(
        from fileURL: URL = defaultFileURL
    ) -> TrustedAuthorRegistry {
        (try? load(from: fileURL)) ?? TrustedAuthorRegistry(fileURL: fileURL)
    }

    static func save(_ entries: [TrustedAuthorEntry], to fileURL: URL) throws {
        try validate(entries)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
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

    private static func readRegistryData(from fileURL: URL) throws -> Data {
        let descriptor = fileURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw TrustedAuthorRegistryError.unsafeRegistryFile
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == getuid(),
              metadata.st_mode & 0o022 == 0,
              metadata.st_size >= 0,
              metadata.st_size <= maximumFileBytes else {
            if metadata.st_size > maximumFileBytes {
                throw TrustedAuthorRegistryError.registryTooLarge(maximumFileBytes)
            }
            throw TrustedAuthorRegistryError.unsafeRegistryFile
        }

        var result = Data()
        result.reserveCapacity(min(Int(metadata.st_size), maximumFileBytes))
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= maximumFileBytes - result.count else {
                    throw TrustedAuthorRegistryError.registryTooLarge(maximumFileBytes)
                }
                result.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count == 0 { return result }
            if errno == EINTR { continue }
            throw TrustedAuthorRegistryError.unsafeRegistryFile
        }
    }

    private static func validate(_ entries: [TrustedAuthorEntry]) throws {
        guard entries.count <= maximumEntries else {
            throw TrustedAuthorRegistryError.tooManyEntries(maximumEntries)
        }
        var keyIDs = Set<String>()
        for entry in entries {
            let name = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name.utf8.count <= 512,
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  entry.keyID == entry.publicKey.keyID,
                  entry.publicKey.rawRepresentation.count == 32,
                  entry.publicKey.keyID == SignatureDigest.keyID(
                      for: entry.publicKey.rawRepresentation
                  ) else {
                throw TrustedAuthorRegistryError.invalidEntry(entry.keyID)
            }
            guard keyIDs.insert(entry.keyID).inserted else {
                throw TrustedAuthorRegistryError.duplicateKeyID(entry.keyID)
            }
        }
    }
}
