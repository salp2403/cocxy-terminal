// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteProfileStoreTests.swift - Tests for remote profile CRUD store.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock File System

final class MockRemoteProfileFileSystem: RemoteProfileFileSystem, @unchecked Sendable {
    var files: [String: String] = [:]
    var directories: Set<String> = []
    var readDirectoryError: (any Error)?
    var readFileError: (any Error)?
    var writeFileError: (any Error)?
    var deleteFileError: (any Error)?

    func readDirectory(at path: String) throws -> [String] {
        if let error = readDirectoryError { throw error }
        return files.keys
            .filter { $0.hasPrefix(path) && $0 != path }
            .compactMap { fullPath in
                let relativePath = String(fullPath.dropFirst(path.count))
                let trimmed = relativePath.hasPrefix("/")
                    ? String(relativePath.dropFirst())
                    : relativePath
                return trimmed.contains("/") ? nil : trimmed
            }
    }

    func readFile(at path: String) throws -> String {
        if let error = readFileError { throw error }
        guard let content = files[path] else {
            throw RemoteProfileStoreError.profileNotFound
        }
        return content
    }

    func writeFile(at path: String, contents: String) throws {
        if let error = writeFileError { throw error }
        files[path] = contents
    }

    func deleteFile(at path: String) throws {
        if let error = deleteFileError { throw error }
        guard files.removeValue(forKey: path) != nil else {
            throw RemoteProfileStoreError.profileNotFound
        }
    }

    func createDirectory(at path: String) throws {
        directories.insert(path)
    }

    func fileExists(at path: String) -> Bool {
        if files[path] != nil || directories.contains(path) {
            return true
        }
        // Check if any stored file has this path as a prefix (directory check).
        let prefix = path.hasSuffix("/") ? path : "\(path)/"
        return files.keys.contains { $0.hasPrefix(prefix) }
    }
}

// MARK: - Remote Profile Store Tests

@Suite("RemoteProfileStore")
struct RemoteProfileStoreTests {

    private func makeStore(
        fileSystem: MockRemoteProfileFileSystem = MockRemoteProfileFileSystem()
    ) -> RemoteProfileStore {
        RemoteProfileStore(
            fileSystem: fileSystem,
            basePath: "/test/config/cocxy/remotes"
        )
    }

    private func seedProfile(
        in fileSystem: MockRemoteProfileFileSystem,
        profile: RemoteConnectionProfile
    ) throws {
        let data = try JSONEncoder().encode(profile)
        let json = String(data: data, encoding: .utf8)!
        fileSystem.files["/test/config/cocxy/remotes/\(profile.id.uuidString).json"] = json
    }

    // MARK: - Load All

    @Test func loadAllReturnsEmptyWhenNoProfiles() throws {
        let store = makeStore()
        let profiles = try store.loadAll()
        #expect(profiles.isEmpty)
    }

    @Test func loadAllReturnsSavedProfiles() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let profile = RemoteConnectionProfile(name: "dev-server", host: "dev.example.com")
        try seedProfile(in: fileSystem, profile: profile)

        let store = makeStore(fileSystem: fileSystem)
        let profiles = try store.loadAll()

        #expect(profiles.count == 1)
        #expect(profiles.first?.name == "dev-server")
        #expect(profiles.first?.host == "dev.example.com")
    }

    @Test func loadAllIgnoresNonJSONFiles() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        fileSystem.files["/test/config/cocxy/remotes/readme.txt"] = "not json"

        let profile = RemoteConnectionProfile(name: "server", host: "host.com")
        try seedProfile(in: fileSystem, profile: profile)

        let store = makeStore(fileSystem: fileSystem)
        let profiles = try store.loadAll()

        #expect(profiles.count == 1)
    }

    @Test func loadAllSkipsMalformedJSON() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        fileSystem.files["/test/config/cocxy/remotes/broken.json"] = "{ invalid json }"

        let store = makeStore(fileSystem: fileSystem)
        let profiles = try store.loadAll()

        #expect(profiles.isEmpty)
    }

    // MARK: - Save

    @Test func saveCreatesNewProfile() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let store = makeStore(fileSystem: fileSystem)
        let profile = RemoteConnectionProfile(name: "new-server", host: "new.example.com")

        try store.save(profile)

        let path = "/test/config/cocxy/remotes/\(profile.id.uuidString).json"
        #expect(fileSystem.files[path] != nil)

        let decoded = try JSONDecoder().decode(
            RemoteConnectionProfile.self,
            from: fileSystem.files[path]!.data(using: .utf8)!
        )
        #expect(decoded.name == "new-server")
        #expect(decoded.host == "new.example.com")
    }

    @Test func saveOverwritesExistingProfile() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let store = makeStore(fileSystem: fileSystem)

        let id = UUID()
        let original = RemoteConnectionProfile(
            id: id, name: "server", host: "old.example.com"
        )
        try store.save(original)

        let updated = RemoteConnectionProfile(
            id: id, name: "server", host: "new.example.com"
        )
        try store.save(updated)

        let profiles = try store.loadAll()
        let matching = profiles.filter { $0.id == id }
        #expect(matching.count == 1)
        #expect(matching.first?.host == "new.example.com")
    }

    @Test func saveCreatesDirectoryIfNeeded() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let store = makeStore(fileSystem: fileSystem)
        let profile = RemoteConnectionProfile(name: "test", host: "host.com")

        try store.save(profile)

        #expect(fileSystem.directories.contains("/test/config/cocxy/remotes"))
    }

    @Test func saveUsesUUIDAsFilename() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let store = makeStore(fileSystem: fileSystem)
        let profile = RemoteConnectionProfile(name: "My Server", host: "host.com")

        try store.save(profile)

        let path = "/test/config/cocxy/remotes/\(profile.id.uuidString).json"
        #expect(fileSystem.files[path] != nil)
    }

    @Test func saveThrowsOnFileSystemError() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        fileSystem.writeFileError = RemoteProfileStoreError.saveFailed("disk full")
        let store = makeStore(fileSystem: fileSystem)
        let profile = RemoteConnectionProfile(name: "test", host: "host.com")

        #expect(throws: RemoteProfileStoreError.self) {
            try store.save(profile)
        }
    }

    // MARK: - Delete

    @Test func deleteRemovesProfile() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let store = makeStore(fileSystem: fileSystem)
        let profile = RemoteConnectionProfile(name: "to-delete", host: "host.com")
        try store.save(profile)

        try store.delete(id: profile.id)

        let profiles = try store.loadAll()
        #expect(profiles.isEmpty)
    }

    @Test func deleteThrowsWhenProfileNotFound() throws {
        let store = makeStore()

        #expect(throws: RemoteProfileStoreError.self) {
            try store.delete(id: UUID())
        }
    }

    // MARK: - Find

    @Test func findByNameReturnsMatchingProfile() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let profile = RemoteConnectionProfile(name: "production", host: "prod.com")
        try seedProfile(in: fileSystem, profile: profile)

        let store = makeStore(fileSystem: fileSystem)
        let found = try store.findByName("production")

        #expect(found?.host == "prod.com")
    }

    @Test func findByNameReturnsNilWhenNotFound() throws {
        let store = makeStore()
        let found = try store.findByName("nonexistent")
        #expect(found == nil)
    }

    @Test func findByGroupReturnsMatchingProfiles() throws {
        let fileSystem = MockRemoteProfileFileSystem()
        let profile1 = RemoteConnectionProfile(
            name: "prod-web", host: "web.prod.com", group: "production"
        )
        let profile2 = RemoteConnectionProfile(
            name: "prod-db", host: "db.prod.com", group: "production"
        )
        let profile3 = RemoteConnectionProfile(
            name: "staging", host: "staging.com", group: "staging"
        )
        try seedProfile(in: fileSystem, profile: profile1)
        try seedProfile(in: fileSystem, profile: profile2)
        try seedProfile(in: fileSystem, profile: profile3)

        let store = makeStore(fileSystem: fileSystem)
        let found = try store.findByGroup("production")

        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.group == "production" })
    }

    @Test func findByGroupReturnsEmptyWhenNoMatch() throws {
        let store = makeStore()
        let found = try store.findByGroup("nonexistent")
        #expect(found.isEmpty)
    }
}
