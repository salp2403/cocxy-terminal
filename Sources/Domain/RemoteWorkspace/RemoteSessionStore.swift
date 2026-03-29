// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteSessionStore.swift - Local persistence for remote tmux session metadata.

import Foundation

// MARK: - Remote Session Record

/// A locally-persisted record of a remote tmux session.
///
/// Tracks session metadata on the client side so Cocxy can offer
/// reconnection to sessions that survived an SSH disconnect without
/// needing to query the remote host first.
struct RemoteSessionRecord: Identifiable, Codable, Equatable, Sendable {

    /// Unique identifier for this record.
    let id: UUID

    /// The remote profile this session belongs to.
    let profileID: UUID

    /// The tmux session name on the remote host.
    let sessionName: String

    /// When this session was first created.
    let createdAt: Date

    /// When this session was last seen active (updated on each health check).
    var lastSeenAt: Date

    /// Human-readable display title for the profile (cached for offline display).
    let profileDisplayTitle: String

    init(
        id: UUID = UUID(),
        profileID: UUID,
        sessionName: String,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date(),
        profileDisplayTitle: String
    ) {
        self.id = id
        self.profileID = profileID
        self.sessionName = sessionName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.profileDisplayTitle = profileDisplayTitle
    }
}

// MARK: - Store Protocol

/// Abstract interface for remote session record persistence.
protocol RemoteSessionStoring: Sendable {
    func loadAll() throws -> [RemoteSessionRecord]
    func save(_ record: RemoteSessionRecord) throws
    func delete(id: UUID) throws
    func findByProfile(_ profileID: UUID) throws -> [RemoteSessionRecord]
    func deleteAllForProfile(_ profileID: UUID) throws
}

// MARK: - Store Errors

/// Errors that can occur during remote session store operations.
enum RemoteSessionStoreError: Error, Equatable {
    case recordNotFound
    case saveFailed(String)
}

// MARK: - Remote Session Store

/// Persists remote tmux session records as individual JSON files.
///
/// ## Storage Layout
///
/// ```
/// ~/.config/cocxy/sessions/
/// ├── 550e8400-e29b-41d4-a716-446655440000.json
/// ├── 6ba7b810-9dad-11d1-80b4-00c04fd430c8.json
/// └── ...
/// ```
///
/// Each file contains a single `RemoteSessionRecord` encoded as JSON.
/// File names use the record UUID, which prevents path traversal.
final class RemoteSessionStore: RemoteSessionStoring {

    // MARK: - Properties

    private let fileSystem: any RemoteProfileFileSystem
    private let basePath: String

    // MARK: - Initialization

    init(
        fileSystem: any RemoteProfileFileSystem = DiskRemoteProfileFileSystem(),
        basePath: String = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.config/cocxy/sessions"
        }()
    ) {
        self.fileSystem = fileSystem
        self.basePath = basePath
    }

    // MARK: - Load All

    /// Loads all session records from the store directory.
    ///
    /// Silently skips corrupt or non-JSON files to ensure resilience.
    func loadAll() throws -> [RemoteSessionRecord] {
        guard fileSystem.fileExists(at: basePath) else { return [] }

        let fileNames: [String]
        do {
            fileNames = try fileSystem.readDirectory(at: basePath)
        } catch {
            return []
        }

        return fileNames
            .filter { $0.hasSuffix(".json") }
            .compactMap { fileName -> RemoteSessionRecord? in
                let filePath = "\(basePath)/\(fileName)"
                guard let content = try? fileSystem.readFile(at: filePath),
                      let data = content.data(using: .utf8),
                      let record = try? JSONDecoder.cocxyDecoder.decode(
                          RemoteSessionRecord.self, from: data
                      )
                else { return nil }
                return record
            }
    }

    // MARK: - Save

    /// Saves a session record to disk, creating the directory if needed.
    func save(_ record: RemoteSessionRecord) throws {
        if !fileSystem.fileExists(at: basePath) {
            try fileSystem.createDirectory(at: basePath)
        }

        let data = try JSONEncoder.cocxyEncoder.encode(record)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RemoteSessionStoreError.saveFailed("Failed to encode record as UTF-8")
        }

        let filePath = "\(basePath)/\(record.id.uuidString).json"
        try fileSystem.writeFile(at: filePath, contents: json)
    }

    // MARK: - Delete

    /// Deletes a session record by its unique identifier.
    func delete(id: UUID) throws {
        let filePath = "\(basePath)/\(id.uuidString).json"
        guard fileSystem.fileExists(at: filePath) else {
            throw RemoteSessionStoreError.recordNotFound
        }
        try fileSystem.deleteFile(at: filePath)
    }

    // MARK: - Query

    /// Finds all session records for a given remote profile.
    func findByProfile(_ profileID: UUID) throws -> [RemoteSessionRecord] {
        let records = try loadAll()
        return records.filter { $0.profileID == profileID }
    }

    /// Deletes all session records for a given remote profile.
    func deleteAllForProfile(_ profileID: UUID) throws {
        let records = try findByProfile(profileID)
        for record in records {
            try? delete(id: record.id)
        }
    }
}

// MARK: - JSON Coding Helpers

private extension JSONEncoder {

    /// Encoder configured for Cocxy session records with ISO 8601 dates.
    static let cocxyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {

    /// Decoder configured for Cocxy session records with ISO 8601 dates.
    static let cocxyDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
