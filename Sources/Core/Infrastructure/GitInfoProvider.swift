// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitInfoProvider.swift - Concrete implementation of GitInfoProviding.

import Foundation
import Combine

// MARK: - Git Info Provider

/// Provides git repository information by reading `.git/HEAD` directly.
///
/// Reads the `.git/HEAD` file to extract the current branch name. This is
/// significantly faster than shelling out to `git rev-parse` (< 1ms vs ~50ms).
///
/// ## Caching
///
/// Branch information is cached per directory with a configurable TTL
/// (default 5 seconds). Cache entries are automatically evicted after
/// the TTL expires. Manual invalidation is available via `invalidateCache()`.
///
/// ## Filesystem Watching
///
/// Uses `DispatchSource.makeFileSystemObjectSource` to watch `.git/HEAD`
/// for changes. When a change is detected, the cache is invalidated and
/// observers are notified with the new branch name.
///
/// ## Performance
///
/// - Target: < 50ms per branch query (gate from PLAN.md).
/// - Actual: < 1ms for cached values, < 5ms for disk reads.
/// - All disk I/O happens on a background queue to avoid blocking main.
///
/// - SeeAlso: `GitInfoProviding` protocol
/// Thread safety: All mutable state is protected by `NSLock`.
/// The `@unchecked Sendable` conformance reflects this manual synchronization.
final class GitInfoProviderImpl: GitInfoProviding, @unchecked Sendable {

    // MARK: - Constants

    /// Prefix that identifies a symbolic ref in `.git/HEAD`.
    private static let refPrefix = "ref: refs/heads/"

    /// Time-to-live for cached branch information, in seconds.
    private let cacheTTLSeconds: TimeInterval

    // MARK: - Cache

    /// A cached branch query result.
    private struct CacheEntry {
        let branch: String?
        let timestamp: Date
    }

    /// Cache of branch lookups keyed by directory path.
    private var cache: [String: CacheEntry] = [:]

    /// Lock protecting cache access from multiple threads.
    private let cacheLock = NSLock()

    // MARK: - Observation

    /// Active file system watchers keyed by directory path.
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    /// Background queue for file I/O operations.
    private let ioQueue = DispatchQueue(
        label: "com.cocxy.gitinfo.io",
        qos: .utility
    )

    // MARK: - Initialization

    /// Creates a GitInfoProvider with the given cache TTL.
    ///
    /// - Parameter cacheTTLSeconds: How long cached branch values are valid.
    ///   Defaults to 5 seconds.
    init(cacheTTLSeconds: TimeInterval = 5.0) {
        self.cacheTTLSeconds = cacheTTLSeconds
    }

    deinit {
        // Cancel all active watchers.
        for (_, source) in watchers {
            source.cancel()
        }
        watchers.removeAll()
    }

    // MARK: - GitInfoProviding Conformance

    /// Returns the current branch name for a directory.
    ///
    /// Reads `.git/HEAD` directly. Returns `nil` for:
    /// - Non-git directories (no `.git/HEAD` file).
    /// - Detached HEAD state (HEAD contains a commit hash, not a ref).
    /// - Malformed or empty `.git/HEAD` files.
    ///
    /// Results are cached for `cacheTTLSeconds`.
    ///
    /// - Parameter directory: Path to a directory (may or may not be a git repo).
    /// - Returns: The branch name (e.g., "main"), or `nil`.
    func currentBranch(at directory: URL) -> String? {
        let directoryPath = directory.path

        // Check cache first.
        if let cached = cachedBranch(for: directoryPath) {
            return cached.branch
        }

        // Read from disk.
        let branch = readBranchFromDisk(at: directory)

        // Store in cache.
        storeCacheEntry(branch: branch, for: directoryPath)

        return branch
    }

    /// Returns whether the directory is a git repository — either a
    /// regular worktree (where `.git` is a directory containing `HEAD`)
    /// or a linked worktree / submodule (where `.git` is a file whose
    /// contents are `gitdir: <path>` pointing at the actual git dir).
    ///
    /// - Parameter directory: Path to check.
    /// - Returns: `true` if the directory's `HEAD` file can be resolved.
    func isGitRepository(at directory: URL) -> Bool {
        resolveHeadURL(at: directory) != nil
    }

    /// Observes branch changes for a directory.
    ///
    /// Immediately emits the current branch value, then watches `.git/HEAD`
    /// for changes using `DispatchSource`. When the file changes, re-reads
    /// the branch and calls the handler.
    ///
    /// - Parameters:
    ///   - directory: Path to the directory to observe.
    ///   - handler: Closure called with the new branch name (or nil).
    /// - Returns: A cancellable that stops the observation when released.
    func observeBranch(
        at directory: URL,
        handler: @escaping @Sendable (String?) -> Void
    ) -> AnyCancellable {
        let directoryPath = directory.path

        // Emit the current value immediately.
        let currentBranchValue = readBranchFromDisk(at: directory)
        storeCacheEntry(branch: currentBranchValue, for: directoryPath)
        handler(currentBranchValue)

        // Set up file watcher on HEAD. Linked worktrees store their HEAD
        // outside `.git`, so the URL must be resolved via `resolveHeadURL`
        // before opening the fd — watching `<worktree>/.git/HEAD` would
        // silently fail because the path does not exist for linked
        // worktrees (their `.git` is a file, not a directory).
        guard let headURL = resolveHeadURL(at: directory),
              FileManager.default.fileExists(atPath: headURL.path) else {
            // Not a git repo -- nothing to watch.
            return AnyCancellable {}
        }

        let fileDescriptor = open(headURL.path, O_EVTONLY | O_CLOEXEC)
        guard fileDescriptor >= 0 else {
            return AnyCancellable {}
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: ioQueue
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.cacheLock.lock()
            let isCurrentWatcher = self.watchers[directoryPath] === source
            self.cacheLock.unlock()
            guard isCurrentWatcher else { return }

            self.invalidateCache(for: directory)
            let newBranch = self.readBranchFromDisk(at: directory)
            self.storeCacheEntry(branch: newBranch, for: directoryPath)
            handler(newBranch)
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()

        // Store the watcher so we can cancel it later.
        cacheLock.lock()
        let previousWatcher = watchers[directoryPath]
        watchers[directoryPath] = source
        cacheLock.unlock()
        previousWatcher?.cancel()

        return AnyCancellable { [weak self] in
            source.cancel()
            guard let self else { return }
            self.cacheLock.lock()
            if self.watchers[directoryPath] === source {
                self.watchers.removeValue(forKey: directoryPath)
            }
            self.cacheLock.unlock()
        }
    }

    // MARK: - Cache Management

    /// Invalidates the entire cache.
    func invalidateCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    /// Invalidates the cache entry for a specific directory.
    ///
    /// - Parameter directory: The directory whose cache entry to remove.
    func invalidateCache(for directory: URL) {
        let directoryPath = directory.path
        cacheLock.lock()
        cache.removeValue(forKey: directoryPath)
        cacheLock.unlock()
    }

    // MARK: - Private Helpers

    /// Resolves the on-disk `HEAD` file for a given working directory.
    ///
    /// Handles three cases:
    /// 1. **Regular repository** — `.git` is a directory and `HEAD`
    ///    lives at `.git/HEAD`.
    /// 2. **Linked worktree or submodule** — `.git` is a text file whose
    ///    contents begin with `gitdir: <path>`. The real git dir lives
    ///    at `<path>` and HEAD lives at `<path>/HEAD`. `<path>` can be
    ///    absolute (linked worktrees) or relative to the directory
    ///    containing the `.git` file (submodules).
    /// 3. **Not a git repository** — `.git` does not exist at all.
    ///
    /// - Parameter directory: A candidate working directory.
    /// - Returns: URL to the `HEAD` file, or `nil` when neither case 1
    ///   nor case 2 applies.
    private func resolveHeadURL(at directory: URL) -> URL? {
        let dotGitURL = directory.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: dotGitURL.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }

        if isDirectory.boolValue {
            // Case 1: regular `.git/` directory.
            return dotGitURL.appendingPathComponent("HEAD")
        }

        // Case 2: `.git` is a file — follow the `gitdir:` pointer.
        guard let content = try? String(contentsOf: dotGitURL, encoding: .utf8) else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir: "
        guard trimmed.hasPrefix(prefix) else { return nil }

        let rawPath = String(trimmed.dropFirst(prefix.count))
        guard !rawPath.isEmpty else { return nil }

        let gitdirURL: URL
        if rawPath.hasPrefix("/") {
            gitdirURL = URL(fileURLWithPath: rawPath)
        } else {
            // Relative paths are resolved against the directory that
            // contains the `.git` file (i.e., the worktree root).
            gitdirURL = directory
                .appendingPathComponent(rawPath)
                .standardizedFileURL
        }
        return gitdirURL.appendingPathComponent("HEAD")
    }

    /// Reads the branch name from `HEAD` on disk.
    ///
    /// Uses `resolveHeadURL` so regular repositories, linked worktrees,
    /// and submodules all go through the same code path. Returns `nil`
    /// for detached HEAD (content begins with a SHA instead of a ref).
    ///
    /// - Parameter directory: The working directory to query.
    /// - Returns: The branch name, or `nil` if not a git repo or
    ///   detached HEAD or malformed HEAD contents.
    private func readBranchFromDisk(at directory: URL) -> String? {
        guard let headURL = resolveHeadURL(at: directory) else {
            return nil
        }

        guard let headContent = try? String(contentsOf: headURL, encoding: .utf8) else {
            return nil
        }

        let trimmedContent = headContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedContent.hasPrefix(Self.refPrefix) else {
            // Detached HEAD or malformed content.
            return nil
        }

        let branchName = String(trimmedContent.dropFirst(Self.refPrefix.count))
        return branchName.isEmpty ? nil : branchName
    }

    /// Returns a cached branch entry if it exists and has not expired.
    ///
    /// - Parameter directoryPath: The directory path to look up.
    /// - Returns: The cached entry, or `nil` if not cached or expired.
    private func cachedBranch(for directoryPath: String) -> CacheEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let entry = cache[directoryPath] else { return nil }

        let age = Date().timeIntervalSince(entry.timestamp)
        if age > cacheTTLSeconds {
            cache.removeValue(forKey: directoryPath)
            return nil
        }

        return entry
    }

    /// Stores a branch value in the cache.
    ///
    /// - Parameters:
    ///   - branch: The branch name (or nil).
    ///   - directoryPath: The directory path to cache for.
    private func storeCacheEntry(branch: String?, for directoryPath: String) {
        let entry = CacheEntry(branch: branch, timestamp: Date())
        cacheLock.lock()
        cache[directoryPath] = entry
        cacheLock.unlock()
    }
}
