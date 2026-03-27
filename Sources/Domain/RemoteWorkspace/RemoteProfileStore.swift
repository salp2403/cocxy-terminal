// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteProfileStore.swift - CRUD store for remote connection profiles.

import Foundation

// MARK: - File System Protocol

/// Abstraction over filesystem operations for remote profile persistence.
///
/// Allows injecting test doubles that hold files in memory instead of
/// touching the real disk.
protocol RemoteProfileFileSystem: Sendable {

    /// Returns the names of files in the given directory.
    func readDirectory(at path: String) throws -> [String]

    /// Reads the contents of a file as a UTF-8 string.
    func readFile(at path: String) throws -> String

    /// Writes a UTF-8 string to a file, creating it if needed.
    func writeFile(at path: String, contents: String) throws

    /// Deletes a file at the given path.
    func deleteFile(at path: String) throws

    /// Creates a directory (and intermediate directories) at the given path.
    func createDirectory(at path: String) throws

    /// Returns whether a file or directory exists at the given path.
    func fileExists(at path: String) -> Bool
}

// MARK: - Store Protocol

/// Abstract interface for remote profile storage operations.
protocol RemoteProfileStoring: Sendable {
    func loadAll() throws -> [RemoteConnectionProfile]
    func save(_ profile: RemoteConnectionProfile) throws
    func delete(id: UUID) throws
    func findByName(_ name: String) throws -> RemoteConnectionProfile?
    func findByGroup(_ group: String) throws -> [RemoteConnectionProfile]
}

// MARK: - Store Errors

/// Errors that can occur during remote profile store operations.
enum RemoteProfileStoreError: Error, Equatable {
    case profileNotFound
    case saveFailed(String)
    case deleteFailed(String)
    case loadFailed(String)
}

// MARK: - Disk File System

/// Production implementation that reads/writes to the real filesystem.
final class DiskRemoteProfileFileSystem: RemoteProfileFileSystem {

    func readDirectory(at path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func readFile(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func writeFile(at path: String, contents: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func deleteFile(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func createDirectory(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - Remote Profile Store

/// CRUD store for remote connection profiles.
///
/// Persists each profile as an individual JSON file in the base directory.
/// File names are derived from the profile name, sanitized for filesystem
/// safety: lowercased with spaces replaced by hyphens.
///
/// ## Storage Layout
///
/// ```
/// ~/.config/cocxy/remotes/
/// ├── production-web.json
/// ├── staging-db.json
/// └── dev-server.json
/// ```
final class RemoteProfileStore: RemoteProfileStoring {

    // MARK: - Properties

    private let fileSystem: any RemoteProfileFileSystem
    private let basePath: String

    // MARK: - Initialization

    /// Creates a store backed by the given filesystem abstraction.
    ///
    /// - Parameters:
    ///   - fileSystem: The filesystem to read/write profiles.
    ///   - basePath: Directory where profile JSON files are stored.
    init(
        fileSystem: any RemoteProfileFileSystem = DiskRemoteProfileFileSystem(),
        basePath: String = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.config/cocxy/remotes"
        }()
    ) {
        self.fileSystem = fileSystem
        self.basePath = basePath
    }

    // MARK: - CRUD Operations

    /// Loads all valid profiles from the store directory.
    ///
    /// Silently skips non-JSON files and files that fail to decode. This
    /// resilience ensures a single corrupt file does not prevent loading
    /// the rest of the profiles.
    func loadAll() throws -> [RemoteConnectionProfile] {
        guard fileSystem.fileExists(at: basePath) else { return [] }

        let fileNames: [String]
        do {
            fileNames = try fileSystem.readDirectory(at: basePath)
        } catch {
            return []
        }

        return fileNames
            .filter { $0.hasSuffix(".json") }
            .compactMap { fileName -> RemoteConnectionProfile? in
                let filePath = "\(basePath)/\(fileName)"
                guard let content = try? fileSystem.readFile(at: filePath),
                      let data = content.data(using: .utf8),
                      let profile = try? JSONDecoder().decode(
                          RemoteConnectionProfile.self, from: data
                      )
                else { return nil }
                return profile
            }
    }

    /// Saves a profile to disk, creating the directory if needed.
    ///
    /// Uses the profile's UUID as the filename, which eliminates path
    /// traversal by design (UUIDs contain only hex digits and hyphens).
    ///
    /// - Parameter profile: The profile to persist.
    func save(_ profile: RemoteConnectionProfile) throws {
        if !fileSystem.fileExists(at: basePath) {
            try fileSystem.createDirectory(at: basePath)
        }

        let data = try JSONEncoder().encode(profile)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RemoteProfileStoreError.saveFailed("Failed to encode profile as UTF-8")
        }

        let filePath = self.filePath(for: profile)
        try fileSystem.writeFile(at: filePath, contents: json)
    }

    /// Deletes a profile by its unique identifier.
    ///
    /// Builds the file path directly from the UUID, then removes it.
    func delete(id: UUID) throws {
        let filePath = "\(basePath)/\(id.uuidString).json"
        guard fileSystem.fileExists(at: filePath) else {
            throw RemoteProfileStoreError.profileNotFound
        }
        try fileSystem.deleteFile(at: filePath)
    }

    /// Finds a profile by its human-readable name.
    func findByName(_ name: String) throws -> RemoteConnectionProfile? {
        let profiles = try loadAll()
        return profiles.first { $0.name == name }
    }

    /// Finds all profiles belonging to a given group.
    func findByGroup(_ group: String) throws -> [RemoteConnectionProfile] {
        let profiles = try loadAll()
        return profiles.filter { $0.group == group }
    }

    // MARK: - Helpers

    /// Returns the file path for a profile, using the UUID as filename.
    ///
    /// UUIDs contain only hexadecimal digits and hyphens, so they are
    /// inherently safe as filenames and immune to path traversal.
    private func filePath(for profile: RemoteConnectionProfile) -> String {
        "\(basePath)/\(profile.id.uuidString).json"
    }
}
