// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeManifestStore.swift - Actor that serialises reads and writes
// to a single on-disk WorktreeManifest.

import Foundation

/// Errors surfaced by the manifest store. Every failure path surfaces
/// with enough context for the caller to craft a user-facing message.
enum WorktreeManifestStoreError: Error, Equatable, Sendable {
    /// The on-disk file could not be read. `underlying` carries the
    /// errno description; callers typically translate this to
    /// "permission denied" or "file locked".
    case readFailed(path: String, underlying: String)
    /// The on-disk file parsed successfully but advertised a newer
    /// schema than this binary understands. Callers should refuse to
    /// mutate rather than silently drop unknown fields.
    case unsupportedSchema(onDisk: Int, supported: Int)
    /// The manifest on disk belongs to a different origin repo than
    /// the caller expected. Likely a race between two cocxy instances
    /// pointing their `<repo-hash>` at the same directory — refusing
    /// to write protects both manifests.
    case repoHashMismatch(onDisk: String, expected: String)
    /// Writing the file failed. Either the parent directory could not
    /// be created or the atomic rename failed.
    case writeFailed(path: String, underlying: String)
}

/// Serialises access to a single manifest file. Every mutation loads,
/// edits, and atomically rewrites the file so a crash between load and
/// save cannot leave a torn file behind.
///
/// The store is constructed against an absolute `manifestPath` so tests
/// can place the file inside a temporary directory without mocking the
/// filesystem. Production callers pass
/// `<basePath>/<repo-hash>/manifest.json`.
actor WorktreeManifestStore {

    /// Absolute path to the manifest file on disk. Exposed for logs
    /// and tests; never mutated.
    let manifestPath: URL

    /// Origin repo the store operates on. Every load/save checks the
    /// on-disk `repoHash` against this value to catch cross-repo drift.
    private let originRepoPath: URL
    private let repoHash: String

    /// In-memory cache of the last successful load or save. Avoids the
    /// round-trip through disk when the caller performs a read-only
    /// operation immediately after a write.
    private var cached: WorktreeManifest?

    init(
        manifestPath: URL,
        originRepoPath: URL
    ) {
        self.manifestPath = manifestPath
        self.originRepoPath = originRepoPath
        self.repoHash = WorktreeManifest.hashForRepoPath(originRepoPath)
    }

    // MARK: - Convenience constructor

    /// Convenience constructor that derives the manifest path from the
    /// configured base directory. `~` in `basePath` is expanded against
    /// the current user's home directory.
    ///
    /// - Parameters:
    ///   - basePath: Value from `WorktreeConfig.basePath`.
    ///   - originRepoPath: Absolute path to the origin repo.
    static func forRepo(
        basePath: String,
        originRepoPath: URL
    ) -> WorktreeManifestStore {
        let repoHash = WorktreeManifest.hashForRepoPath(originRepoPath)
        let expandedBase = (basePath as NSString).expandingTildeInPath
        let manifestPath = URL(fileURLWithPath: expandedBase, isDirectory: true)
            .appendingPathComponent(repoHash, isDirectory: true)
            .appendingPathComponent("manifest.json")
        return WorktreeManifestStore(
            manifestPath: manifestPath,
            originRepoPath: originRepoPath
        )
    }

    // MARK: - Load / Save

    /// Returns the current manifest, creating an empty one if the file
    /// does not yet exist. A missing file is treated as "the user has
    /// never created a worktree for this repo" — not an error.
    ///
    /// The loaded manifest is cached until the next save or clear.
    func load() throws -> WorktreeManifest {
        if let cached { return cached }

        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            let empty = WorktreeManifest(
                repoHash: repoHash,
                originRepoPath: originRepoPath
            )
            cached = empty
            return empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestPath)
        } catch {
            throw WorktreeManifestStoreError.readFailed(
                path: manifestPath.path,
                underlying: error.localizedDescription
            )
        }

        let manifest: WorktreeManifest
        do {
            manifest = try Self.makeDecoder().decode(WorktreeManifest.self, from: data)
        } catch {
            // A malformed file is treated as "empty manifest" so a
            // cosmetic corruption never blocks the user; the file gets
            // rewritten cleanly on the next save. This matches how
            // session restore tolerates partial JSON.
            let fallback = WorktreeManifest(
                repoHash: repoHash,
                originRepoPath: originRepoPath
            )
            cached = fallback
            return fallback
        }

        guard manifest.schemaVersion <= WorktreeManifest.currentSchemaVersion else {
            throw WorktreeManifestStoreError.unsupportedSchema(
                onDisk: manifest.schemaVersion,
                supported: WorktreeManifest.currentSchemaVersion
            )
        }

        guard manifest.repoHash == repoHash else {
            throw WorktreeManifestStoreError.repoHashMismatch(
                onDisk: manifest.repoHash,
                expected: repoHash
            )
        }

        cached = manifest
        return manifest
    }

    /// Persists a manifest to disk using an atomic tmp-file + rename
    /// sequence so a crash during the write cannot leave a truncated
    /// file behind.
    func save(_ manifest: WorktreeManifest) throws {
        guard manifest.repoHash == repoHash else {
            throw WorktreeManifestStoreError.repoHashMismatch(
                onDisk: manifest.repoHash,
                expected: repoHash
            )
        }

        let parentDir = manifestPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw WorktreeManifestStoreError.writeFailed(
                path: manifestPath.path,
                underlying: error.localizedDescription
            )
        }

        let encoder = Self.makeEncoder()
        let data: Data
        do {
            data = try encoder.encode(manifest)
        } catch {
            throw WorktreeManifestStoreError.writeFailed(
                path: manifestPath.path,
                underlying: error.localizedDescription
            )
        }

        // Atomic write: write to <path>.tmp, rename over the final
        // file. `Data.write(to:options:)` with `.atomic` does the same
        // on Darwin but we keep the dance explicit so the sequence is
        // auditable.
        let tempURL = manifestPath
            .deletingLastPathComponent()
            .appendingPathComponent(manifestPath.lastPathComponent + ".tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: manifestPath.path) {
                _ = try FileManager.default.replaceItemAt(manifestPath, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: manifestPath)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw WorktreeManifestStoreError.writeFailed(
                path: manifestPath.path,
                underlying: error.localizedDescription
            )
        }

        cached = manifest
    }

    // MARK: - Mutation helpers (load → mutate → save)

    /// Upserts an entry and saves atomically.
    func upsert(_ entry: WorktreeManifest.WorktreeEntry) throws {
        var manifest = try load()
        manifest.upsert(entry)
        try save(manifest)
    }

    /// Removes an entry by id and saves atomically. Returns the removed
    /// entry so callers can log or notify.
    @discardableResult
    func remove(id: String) throws -> WorktreeManifest.WorktreeEntry? {
        var manifest = try load()
        let removed = manifest.remove(id: id)
        if removed != nil {
            try save(manifest)
        }
        return removed
    }

    /// Clears the tab binding on an entry and saves atomically. Used
    /// by `on-close = keep` when the tab closes but the worktree
    /// survives.
    func clearTabBinding(id: String) throws {
        var manifest = try load()
        manifest.clearTabBinding(id: id)
        try save(manifest)
    }

    /// Drops the in-memory cache so the next `load()` re-reads the
    /// file. Used by tests and by production code that observes an
    /// external change to the manifest file.
    func invalidateCache() {
        cached = nil
    }

    // MARK: - Encoder / Decoder factories

    /// Encoder used by every `save`. Pretty-printed for human
    /// inspection, keys sorted for stable diffs, and ISO-8601 dates so
    /// the file reads cleanly without a foundation-specific epoch.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decoder paired with `makeEncoder`. The date strategy must match
    /// the encoder exactly or the round-trip silently fails.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
