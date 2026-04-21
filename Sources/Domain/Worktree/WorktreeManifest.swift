// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeManifest.swift - Pure data model for the per-repo manifest
// that tracks cocxy-managed git worktrees.

import Foundation

/// Persistent record of every cocxy-managed worktree rooted at a single
/// origin repository.
///
/// `git worktree list` tells us which worktrees git knows about, but it
/// cannot distinguish worktrees the user created manually from those
/// `cocxy worktree add` produced. The manifest fills that gap: it
/// records only entries cocxy created, along with the metadata other
/// worktrees created in a shell would not carry — the owning tab ID,
/// the agent that asked for the worktree, and the creation timestamp.
///
/// One manifest file lives at
/// `<base-path>/<repo-hash>/manifest.json`. `<repo-hash>` is a
/// deterministic digest of the origin repo's absolute path so the same
/// manifest is produced regardless of which worktree (or the origin
/// itself) the command runs from.
///
/// The struct is pure — no I/O, no side effects. `WorktreeManifestStore`
/// wraps reads and writes with an actor boundary and atomic renames.
struct WorktreeManifest: Codable, Sendable, Equatable {

    /// Current on-disk schema. Bump when adding fields that require a
    /// migration and handle the upgrade in
    /// `WorktreeManifestStore.load`.
    static let currentSchemaVersion: Int = 1

    /// Persisted schema version. Tolerated via `decodeIfPresent` so an
    /// older on-disk file can still round-trip through the current
    /// decoder even when this library advances the schema.
    let schemaVersion: Int

    /// Deterministic hash of `originRepoPath`. Used to compute the
    /// manifest's on-disk location and to verify that the file on disk
    /// belongs to the expected origin repo before mutating.
    let repoHash: String

    /// Absolute path of the origin repository this manifest belongs to.
    /// Persisted verbatim so a moved or renamed manifest file reveals
    /// itself to a diagnostic (`repoHash` would no longer agree).
    let originRepoPath: URL

    /// Entries for every cocxy-managed worktree. Sorted by `createdAt`
    /// so human readers see the newest entries last.
    private(set) var entries: [WorktreeEntry]

    // MARK: - Entry

    /// A single cocxy-managed worktree recorded in the manifest.
    struct WorktreeEntry: Codable, Sendable, Equatable, Identifiable {
        /// Short identifier that also appears in the path and branch.
        let id: String

        /// Branch name produced by `WorktreeBranch.expand`.
        var branch: String

        /// Absolute path to the worktree root on disk.
        var path: URL

        /// When the worktree was created.
        let createdAt: Date

        /// Agent that prompted the creation, or `nil` when the user
        /// invoked `cocxy worktree add` manually without an agent
        /// context.
        var agent: String?

        /// Tab that owns this worktree at manifest-write time. May
        /// become `nil` if the tab is closed with `on-close = keep`.
        var tabID: TabID?
    }

    // MARK: - Construction

    init(
        repoHash: String,
        originRepoPath: URL,
        entries: [WorktreeEntry] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.repoHash = repoHash
        self.originRepoPath = originRepoPath
        self.entries = entries
    }

    // MARK: - Codable (tolerant of future field additions)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, repoHash, originRepoPath, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? Self.currentSchemaVersion
        self.repoHash = try container.decode(String.self, forKey: .repoHash)
        self.originRepoPath = try container.decode(URL.self, forKey: .originRepoPath)
        self.entries = try container.decodeIfPresent(
            [WorktreeEntry].self,
            forKey: .entries
        ) ?? []
    }

    // MARK: - Mutation helpers (pure; callers persist explicitly)

    /// Inserts an entry or replaces an existing one with the same id.
    /// Entries stay sorted by `createdAt` ascending so the list reads
    /// chronologically.
    mutating func upsert(_ entry: WorktreeEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.createdAt < $1.createdAt }
    }

    /// Removes the entry with the given id. Returns the removed entry
    /// so the caller can, for example, emit a notification.
    @discardableResult
    mutating func remove(id: String) -> WorktreeEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return entries.remove(at: index)
    }

    /// Clears the owning tab on an entry without removing it. Used by
    /// `on-close = keep` when the tab closes but the worktree survives.
    mutating func clearTabBinding(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        entries[index].tabID = nil
    }

    /// Looks up an entry by id.
    func entry(withID id: String) -> WorktreeEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - Drift detection

    /// Computes the difference between what the manifest believes and
    /// what `git worktree list` reports. Used by `cocxy worktree prune`
    /// and by the status view to flag manual changes.
    ///
    /// - Parameter gitWorktreePaths: Absolute paths reported by
    ///   `git worktree list`. Include the main worktree or not — it
    ///   only matters that the set covers every linked worktree.
    /// - Returns: A `WorktreeManifestDrift` with two mutually exclusive
    ///   sets.
    func drift(comparedWith gitWorktreePaths: [URL]) -> WorktreeManifestDrift {
        let gitPathSet = Set(gitWorktreePaths.map { $0.standardizedFileURL })
        let manifestPathSet = Set(entries.map { $0.path.standardizedFileURL })

        let orphanedEntries = entries.filter {
            !gitPathSet.contains($0.path.standardizedFileURL)
        }
        let untrackedPaths = gitPathSet.subtracting(manifestPathSet)

        return WorktreeManifestDrift(
            orphanedManifestIDs: orphanedEntries.map(\.id).sorted(),
            untrackedGitPaths: Array(untrackedPaths).sorted { $0.path < $1.path }
        )
    }

    // MARK: - Repo hash

    /// Deterministic 16-hex-char digest of an origin repo's absolute
    /// path. Stable across runs, case-preserving, and short enough for
    /// path components to stay readable.
    static func hashForRepoPath(_ url: URL) -> String {
        let canonical = url.standardizedFileURL.path
        var hasher = StableFNVHasher()
        hasher.combine(canonical)
        return hasher.digestHexString()
    }
}

// MARK: - WorktreeManifestDrift

/// Two-way diff between a manifest and the current `git worktree list`
/// output. Empty on both sides means the two sources agree.
struct WorktreeManifestDrift: Sendable, Equatable {
    /// IDs whose manifest entry points at a worktree git no longer
    /// tracks. These are safe to prune from the manifest — the worktree
    /// was already removed (either via `git worktree remove` run in a
    /// shell or via direct filesystem deletion).
    let orphanedManifestIDs: [String]

    /// Worktree paths `git` knows about but the manifest does not.
    /// These were created outside of cocxy and must be left untouched;
    /// we only list them so tooling can show the user where the drift
    /// is.
    let untrackedGitPaths: [URL]

    /// `true` when both sides agree exactly.
    var isEmpty: Bool {
        orphanedManifestIDs.isEmpty && untrackedGitPaths.isEmpty
    }
}

// MARK: - StableFNVHasher

/// 64-bit FNV-1a hasher producing a deterministic digest across
/// process restarts. Swift's `Hasher` is seeded per-process so we
/// cannot rely on its output as a persistent filesystem key.
///
/// FNV-1a is explicitly *not* cryptographic. It is used here only to
/// derive a short, stable label for a filesystem directory; collisions
/// are harmless because the origin repo path is also persisted inside
/// the manifest and double-checked on load.
private struct StableFNVHasher {
    private static let offsetBasis: UInt64 = 0xcbf29ce484222325
    private static let prime: UInt64 = 0x100000001b3

    private var state: UInt64 = StableFNVHasher.offsetBasis

    mutating func combine(_ bytes: [UInt8]) {
        for byte in bytes {
            state ^= UInt64(byte)
            state = state &* Self.prime
        }
    }

    mutating func combine(_ string: String) {
        combine(Array(string.utf8))
    }

    func digestHexString() -> String {
        String(format: "%016x", state)
    }
}
