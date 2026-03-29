// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteSessionStoreTests.swift - Tests for remote tmux session record persistence.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - In-Memory File System

/// File system mock that stores files in memory for isolated testing.
private final class InMemoryProfileFileSystem: RemoteProfileFileSystem, @unchecked Sendable {
    var files: [String: String] = [:]
    var directories: Set<String> = []

    func readDirectory(at path: String) throws -> [String] {
        files.keys
            .filter { $0.hasPrefix(path + "/") }
            .map { String($0.dropFirst(path.count + 1)) }
            .filter { !$0.contains("/") }
    }

    func readFile(at path: String) throws -> String {
        guard let content = files[path] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        return content
    }

    func writeFile(at path: String, contents: String) throws {
        files[path] = contents
    }

    func deleteFile(at path: String) throws {
        guard files.removeValue(forKey: path) != nil else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
    }

    func createDirectory(at path: String) throws {
        directories.insert(path)
    }

    func fileExists(at path: String) -> Bool {
        files.keys.contains(path) || directories.contains(path)
    }
}

// MARK: - Remote Session Store Tests

@Suite("RemoteSessionStore")
struct RemoteSessionStoreTests {

    private func makeStore() -> (RemoteSessionStore, InMemoryProfileFileSystem) {
        let fs = InMemoryProfileFileSystem()
        let basePath = "/tmp/test-sessions"
        fs.directories.insert(basePath)
        let store = RemoteSessionStore(fileSystem: fs, basePath: basePath)
        return (store, fs)
    }

    private func makeRecord(
        profileID: UUID = UUID(),
        sessionName: String = "cocxy-dev"
    ) -> RemoteSessionRecord {
        RemoteSessionRecord(
            profileID: profileID,
            sessionName: sessionName,
            profileDisplayTitle: "root@server.com"
        )
    }

    // MARK: - Save & Load

    @Test func saveAndLoadRecord() throws {
        let (store, _) = makeStore()
        let record = makeRecord()

        try store.save(record)
        let loaded = try store.loadAll()

        #expect(loaded.count == 1)
        #expect(loaded[0].id == record.id)
        #expect(loaded[0].sessionName == "cocxy-dev")
        #expect(loaded[0].profileDisplayTitle == "root@server.com")
    }

    @Test func saveMultipleRecords() throws {
        let (store, _) = makeStore()
        let record1 = makeRecord(sessionName: "cocxy-dev")
        let record2 = makeRecord(sessionName: "cocxy-staging")

        try store.save(record1)
        try store.save(record2)
        let loaded = try store.loadAll()

        #expect(loaded.count == 2)
    }

    @Test func loadAllReturnsEmptyWhenNoDirectory() throws {
        let fs = InMemoryProfileFileSystem()
        let store = RemoteSessionStore(fileSystem: fs, basePath: "/nonexistent")

        let loaded = try store.loadAll()

        #expect(loaded.isEmpty)
    }

    // MARK: - Delete

    @Test func deleteRecord() throws {
        let (store, _) = makeStore()
        let record = makeRecord()

        try store.save(record)
        try store.delete(id: record.id)
        let loaded = try store.loadAll()

        #expect(loaded.isEmpty)
    }

    @Test func deleteNonexistentThrows() throws {
        let (store, _) = makeStore()

        #expect(throws: RemoteSessionStoreError.self) {
            try store.delete(id: UUID())
        }
    }

    // MARK: - Query

    @Test func findByProfile() throws {
        let (store, _) = makeStore()
        let profileID = UUID()
        let otherProfileID = UUID()

        try store.save(makeRecord(profileID: profileID, sessionName: "cocxy-dev"))
        try store.save(makeRecord(profileID: profileID, sessionName: "cocxy-staging"))
        try store.save(makeRecord(profileID: otherProfileID, sessionName: "cocxy-other"))

        let results = try store.findByProfile(profileID)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.profileID == profileID })
    }

    @Test func findByProfileReturnsEmptyWhenNoMatches() throws {
        let (store, _) = makeStore()

        let results = try store.findByProfile(UUID())

        #expect(results.isEmpty)
    }

    @Test func deleteAllForProfile() throws {
        let (store, _) = makeStore()
        let profileID = UUID()
        let otherProfileID = UUID()

        try store.save(makeRecord(profileID: profileID, sessionName: "cocxy-dev"))
        try store.save(makeRecord(profileID: profileID, sessionName: "cocxy-staging"))
        try store.save(makeRecord(profileID: otherProfileID, sessionName: "cocxy-keep"))

        try store.deleteAllForProfile(profileID)
        let allRecords = try store.loadAll()

        #expect(allRecords.count == 1)
        #expect(allRecords[0].profileID == otherProfileID)
    }

    // MARK: - Date Encoding

    @Test func datesRoundTripCorrectly() throws {
        let (store, _) = makeStore()
        let now = Date()
        let record = RemoteSessionRecord(
            profileID: UUID(),
            sessionName: "cocxy-test",
            createdAt: now,
            lastSeenAt: now,
            profileDisplayTitle: "test@host"
        )

        try store.save(record)
        let loaded = try store.loadAll()

        #expect(loaded.count == 1)
        // ISO 8601 rounds to seconds.
        let timeDifference = abs(loaded[0].createdAt.timeIntervalSince(now))
        #expect(timeDifference < 1.0)
    }

    // MARK: - Resilience

    @Test func loadAllSkipsCorruptFiles() throws {
        let (store, fs) = makeStore()
        let basePath = "/tmp/test-sessions"

        // Save a valid record.
        let record = makeRecord()
        try store.save(record)

        // Write a corrupt file.
        fs.files["\(basePath)/corrupt.json"] = "not valid json {"

        let loaded = try store.loadAll()

        #expect(loaded.count == 1)
        #expect(loaded[0].id == record.id)
    }

    @Test func loadAllIgnoresNonJsonFiles() throws {
        let (store, fs) = makeStore()
        let basePath = "/tmp/test-sessions"

        let record = makeRecord()
        try store.save(record)

        fs.files["\(basePath)/readme.txt"] = "this is not a json file"

        let loaded = try store.loadAll()

        #expect(loaded.count == 1)
    }

    // MARK: - Directory Creation

    @Test func saveCreatesDirectoryIfNeeded() throws {
        let fs = InMemoryProfileFileSystem()
        let basePath = "/tmp/auto-created"
        let store = RemoteSessionStore(fileSystem: fs, basePath: basePath)

        let record = makeRecord()
        try store.save(record)

        #expect(fs.directories.contains(basePath))
        #expect(try store.loadAll().count == 1)
    }
}
