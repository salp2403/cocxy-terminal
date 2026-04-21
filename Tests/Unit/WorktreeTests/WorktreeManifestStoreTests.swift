// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeManifestStoreTests.swift - Coverage for the actor that
// serialises disk I/O for a WorktreeManifest.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("WorktreeManifestStore")
struct WorktreeManifestStoreTests {

    // MARK: - Fixture helpers

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-manifest-store", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        return base
    }

    private func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeStore(rootedAt root: URL) -> WorktreeManifestStore {
        WorktreeManifestStore(
            manifestPath: root.appendingPathComponent("manifest.json"),
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app")
        )
    }

    private func makeEntry(
        id: String = "abc123",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: "cocxy/claude/\(id)",
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            createdAt: createdAt,
            agent: "claude",
            tabID: nil
        )
    }

    // MARK: - Load

    @Test("loading from a missing file returns an empty manifest")
    func loadMissingReturnsEmpty() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        let manifest = try await store.load()
        #expect(manifest.entries.isEmpty)
        #expect(manifest.schemaVersion == WorktreeManifest.currentSchemaVersion)
    }

    @Test("saving then loading preserves every entry")
    func saveThenLoadRoundTrips() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        var manifest = try await store.load()
        manifest.upsert(makeEntry(id: "alpha"))
        manifest.upsert(makeEntry(id: "beta"))
        try await store.save(manifest)

        // Invalidate the cache to force a real disk re-read.
        await store.invalidateCache()
        let reloaded = try await store.load()
        #expect(reloaded.entries.count == 2)
        #expect(reloaded.entries.contains { $0.id == "alpha" })
        #expect(reloaded.entries.contains { $0.id == "beta" })
    }

    @Test("save creates parent directories that do not yet exist")
    func saveCreatesParentDirectories() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let nested = root
            .appendingPathComponent("a/b/c", isDirectory: true)
            .appendingPathComponent("manifest.json")
        let store = WorktreeManifestStore(
            manifestPath: nested,
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app")
        )

        let manifest = WorktreeManifest(
            repoHash: WorktreeManifest.hashForRepoPath(
                URL(fileURLWithPath: "/Users/dev/projects/app")
            ),
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app")
        )
        try await store.save(manifest)

        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    // MARK: - Mutation helpers

    @Test("upsert persists a new entry to disk")
    func upsertPersistsEntry() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        try await store.upsert(makeEntry(id: "u1"))
        await store.invalidateCache()
        let reloaded = try await store.load()
        #expect(reloaded.entries.first?.id == "u1")
    }

    @Test("remove persists the removal to disk and returns the entry")
    func removePersistsEntry() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        try await store.upsert(makeEntry(id: "target"))
        let removed = try await store.remove(id: "target")
        #expect(removed?.id == "target")

        await store.invalidateCache()
        let reloaded = try await store.load()
        #expect(reloaded.entries.isEmpty)
    }

    @Test("clearTabBinding keeps the entry but drops its tabID")
    func clearTabBindingPersisted() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        let entry = WorktreeManifest.WorktreeEntry(
            id: "tb",
            branch: "cocxy/claude/tb",
            path: URL(fileURLWithPath: "/tmp/tb"),
            createdAt: Date(),
            agent: "claude",
            tabID: TabID()
        )
        try await store.upsert(entry)
        try await store.clearTabBinding(id: "tb")

        await store.invalidateCache()
        let reloaded = try await store.load()
        let refreshed = reloaded.entry(withID: "tb")
        #expect(refreshed != nil)
        #expect(refreshed?.tabID == nil)
    }

    // MARK: - Error paths

    @Test("reading a corrupt file falls back to an empty manifest")
    func corruptManifestReadsAsEmpty() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let manifestPath = root.appendingPathComponent("manifest.json")
        try "not valid json {{{".write(
            to: manifestPath,
            atomically: true,
            encoding: .utf8
        )
        let store = WorktreeManifestStore(
            manifestPath: manifestPath,
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app")
        )

        let manifest = try await store.load()
        #expect(manifest.entries.isEmpty)
    }

    @Test("saving a manifest with a mismatched repoHash throws")
    func mismatchedRepoHashThrows() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        let wrong = WorktreeManifest(
            repoHash: "not-the-right-hash",
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app")
        )

        await #expect(throws: WorktreeManifestStoreError.self) {
            try await store.save(wrong)
        }
    }

    @Test("loading a manifest with a mismatched repoHash throws")
    func mismatchedRepoHashLoadThrows() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let manifestPath = root.appendingPathComponent("manifest.json")
        // Hand-craft a valid JSON with the wrong repoHash.
        let json = """
        {
          "schemaVersion": 1,
          "repoHash": "not-the-right-hash",
          "originRepoPath": "file:///Users/dev/projects/app",
          "entries": []
        }
        """
        try json.write(to: manifestPath, atomically: true, encoding: .utf8)

        let store = WorktreeManifestStore(
            manifestPath: manifestPath,
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app")
        )

        await #expect(throws: WorktreeManifestStoreError.self) {
            _ = try await store.load()
        }
    }

    // MARK: - Concurrency

    @Test("concurrent upserts serialise through the actor boundary")
    func concurrentUpsertsSerialise() async throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }
        let store = makeStore(rootedAt: root)

        // Fire fifty concurrent upserts with distinct ids. Every one
        // must end up on disk; nothing gets clobbered.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let entry = WorktreeManifest.WorktreeEntry(
                        id: "id-\(index)",
                        branch: "cocxy/claude/id-\(index)",
                        path: URL(fileURLWithPath: "/tmp/id-\(index)"),
                        createdAt: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                        agent: "claude",
                        tabID: nil
                    )
                    try? await store.upsert(entry)
                }
            }
        }

        await store.invalidateCache()
        let reloaded = try await store.load()
        #expect(reloaded.entries.count == 50)
    }
}
