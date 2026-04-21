// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeManifestTests.swift - Coverage for WorktreeManifest pure
// data operations (upsert / remove / lookup / drift / Codable).

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("WorktreeManifest")
struct WorktreeManifestTests {

    // MARK: - Fixtures

    private static func makeEntry(
        id: String = "abc123",
        branch: String = "cocxy/claude/abc123",
        path: String = "/tmp/worktree-storage/hash/abc123",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        agent: String? = "claude",
        tabID: TabID? = nil
    ) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: branch,
            path: URL(fileURLWithPath: path),
            createdAt: createdAt,
            agent: agent,
            tabID: tabID
        )
    }

    private static func makeManifest(
        entries: [WorktreeManifest.WorktreeEntry] = []
    ) -> WorktreeManifest {
        WorktreeManifest(
            repoHash: "deadbeef",
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app"),
            entries: entries
        )
    }

    // MARK: - Construction

    @Test("empty manifest has no entries and the current schema version")
    func emptyManifestProperties() {
        let manifest = Self.makeManifest()
        #expect(manifest.entries.isEmpty)
        #expect(manifest.schemaVersion == WorktreeManifest.currentSchemaVersion)
    }

    // MARK: - Upsert

    @Test("upsert inserts a new entry")
    func upsertInserts() {
        var manifest = Self.makeManifest()
        manifest.upsert(Self.makeEntry())
        #expect(manifest.entries.count == 1)
        #expect(manifest.entries.first?.id == "abc123")
    }

    @Test("upsert replaces an entry with the same id")
    func upsertReplaces() {
        var manifest = Self.makeManifest()
        manifest.upsert(Self.makeEntry(branch: "old-branch"))
        manifest.upsert(Self.makeEntry(branch: "new-branch"))
        #expect(manifest.entries.count == 1)
        #expect(manifest.entries.first?.branch == "new-branch")
    }

    @Test("upsert keeps entries sorted by createdAt ascending")
    func upsertKeepsSortedOrder() {
        var manifest = Self.makeManifest()
        let newer = Self.makeEntry(
            id: "newer",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let older = Self.makeEntry(
            id: "older",
            createdAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        manifest.upsert(newer)
        manifest.upsert(older)
        #expect(manifest.entries.map(\.id) == ["older", "newer"])
    }

    // MARK: - Remove

    @Test("remove returns the removed entry")
    func removeReturnsEntry() {
        var manifest = Self.makeManifest(entries: [Self.makeEntry()])
        let removed = manifest.remove(id: "abc123")
        #expect(removed?.id == "abc123")
        #expect(manifest.entries.isEmpty)
    }

    @Test("remove returns nil for unknown ids")
    func removeUnknownReturnsNil() {
        var manifest = Self.makeManifest(entries: [Self.makeEntry()])
        let removed = manifest.remove(id: "does-not-exist")
        #expect(removed == nil)
        #expect(manifest.entries.count == 1)
    }

    // MARK: - Tab binding

    @Test("clearTabBinding drops the tabID without removing the entry")
    func clearTabBindingKeepsEntry() {
        let bound = Self.makeEntry(tabID: TabID())
        var manifest = Self.makeManifest(entries: [bound])
        manifest.clearTabBinding(id: bound.id)

        let refreshed = manifest.entry(withID: bound.id)
        #expect(refreshed != nil)
        #expect(refreshed?.tabID == nil)
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip preserves every field")
    func codableRoundTrip() throws {
        let entry = Self.makeEntry(
            tabID: TabID()
        )
        let original = Self.makeManifest(entries: [entry])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorktreeManifest.self, from: data)

        #expect(decoded == original)
        #expect(decoded.entries.first?.tabID == entry.tabID)
    }

    @Test("decoding a legacy JSON without schemaVersion falls back to current version")
    func legacyJSONWithoutSchemaVersion() throws {
        let json = """
        {
          "repoHash": "deadbeef",
          "originRepoPath": "file:///Users/dev/projects/app",
          "entries": []
        }
        """
        let decoded = try JSONDecoder().decode(
            WorktreeManifest.self,
            from: Data(json.utf8)
        )
        #expect(decoded.schemaVersion == WorktreeManifest.currentSchemaVersion)
        #expect(decoded.entries.isEmpty)
    }

    // MARK: - Hash

    @Test("hashForRepoPath is deterministic for the same input")
    func hashIsDeterministic() {
        let url = URL(fileURLWithPath: "/Users/dev/projects/app")
        let a = WorktreeManifest.hashForRepoPath(url)
        let b = WorktreeManifest.hashForRepoPath(url)
        #expect(a == b)
    }

    @Test("hashForRepoPath differs for different input paths")
    func hashIsDistinctPerPath() {
        let a = WorktreeManifest.hashForRepoPath(URL(fileURLWithPath: "/a"))
        let b = WorktreeManifest.hashForRepoPath(URL(fileURLWithPath: "/b"))
        #expect(a != b)
    }

    @Test("hashForRepoPath returns a 16-char lowercase hex string")
    func hashShapeIsStable() {
        let hash = WorktreeManifest.hashForRepoPath(
            URL(fileURLWithPath: "/Users/dev/projects/app")
        )
        #expect(hash.count == 16)
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hash.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
}

@Suite("WorktreeManifest — drift detection")
struct WorktreeManifestDriftTests {

    private static func makeEntry(
        id: String,
        path: String
    ) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: "cocxy/claude/\(id)",
            path: URL(fileURLWithPath: path),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            agent: "claude",
            tabID: nil
        )
    }

    private static func makeManifest(
        entries: [WorktreeManifest.WorktreeEntry]
    ) -> WorktreeManifest {
        WorktreeManifest(
            repoHash: "deadbeef",
            originRepoPath: URL(fileURLWithPath: "/Users/dev/projects/app"),
            entries: entries
        )
    }

    @Test("drift is empty when manifest and git paths agree")
    func emptyDriftOnPerfectSync() {
        let a = Self.makeEntry(id: "a", path: "/wt/a")
        let b = Self.makeEntry(id: "b", path: "/wt/b")
        let manifest = Self.makeManifest(entries: [a, b])

        let drift = manifest.drift(comparedWith: [
            URL(fileURLWithPath: "/wt/a"),
            URL(fileURLWithPath: "/wt/b")
        ])

        #expect(drift.isEmpty)
        #expect(drift.orphanedManifestIDs.isEmpty)
        #expect(drift.untrackedGitPaths.isEmpty)
    }

    @Test("orphaned manifest entries surface as orphanedManifestIDs")
    func detectsOrphans() {
        let removed = Self.makeEntry(id: "a", path: "/wt/a")
        let alive = Self.makeEntry(id: "b", path: "/wt/b")
        let manifest = Self.makeManifest(entries: [removed, alive])

        let drift = manifest.drift(comparedWith: [
            URL(fileURLWithPath: "/wt/b")
            // /wt/a has been removed from git but still in manifest.
        ])

        #expect(drift.orphanedManifestIDs == ["a"])
        #expect(drift.untrackedGitPaths.isEmpty)
    }

    @Test("worktrees created outside cocxy surface as untrackedGitPaths")
    func detectsUntrackedGit() {
        let known = Self.makeEntry(id: "a", path: "/wt/a")
        let manifest = Self.makeManifest(entries: [known])

        let drift = manifest.drift(comparedWith: [
            URL(fileURLWithPath: "/wt/a"),
            URL(fileURLWithPath: "/elsewhere/manual")
        ])

        #expect(drift.orphanedManifestIDs.isEmpty)
        #expect(drift.untrackedGitPaths.count == 1)
        #expect(drift.untrackedGitPaths.first?.path == "/elsewhere/manual")
    }

    @Test("empty manifest with a populated git list reports every git path as untracked")
    func emptyManifestAllUntracked() {
        let manifest = Self.makeManifest(entries: [])
        let drift = manifest.drift(comparedWith: [
            URL(fileURLWithPath: "/wt/a"),
            URL(fileURLWithPath: "/wt/b")
        ])

        #expect(drift.orphanedManifestIDs.isEmpty)
        #expect(drift.untrackedGitPaths.count == 2)
    }

    @Test("populated manifest with an empty git list reports every entry as orphan")
    func populatedManifestNoGitAllOrphans() {
        let entries = ["a", "b", "c"].map {
            Self.makeEntry(id: $0, path: "/wt/\($0)")
        }
        let manifest = Self.makeManifest(entries: entries)
        let drift = manifest.drift(comparedWith: [])

        #expect(drift.orphanedManifestIDs == ["a", "b", "c"])
    }
}
