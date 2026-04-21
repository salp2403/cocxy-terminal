// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeService.swift - Actor that drives `git worktree` operations
// for cocxy-managed worktrees.

import Foundation

// MARK: - Supporting types

/// Status snapshot returned by `WorktreeService.status(for:in:)`.
struct WorktreeStatusSnapshot: Equatable, Sendable {
    /// Manifest entry the status refers to.
    let entry: WorktreeManifest.WorktreeEntry
    /// `true` when `git status --porcelain` reports no pending changes.
    let isClean: Bool
    /// Raw non-empty lines of `git status --porcelain` output. Empty
    /// when the worktree is clean; included verbatim so UI can surface
    /// it to the user before a destructive command.
    let porcelainLines: [String]
}

/// Errors surfaced by `WorktreeService`. Typed so CLI and UI layers can
/// render actionable messages without parsing stderr themselves.
enum WorktreeServiceError: Error, Equatable, Sendable {
    /// `config.worktree.enabled == false`. The user must opt in via
    /// Preferences or `~/.config/cocxy/config.toml`.
    case featureDisabled
    /// No usable `git` binary found on PATH or in the known fallbacks.
    case gitUnavailable
    /// Origin repository does not contain a `.git` directory or linked
    /// worktree pointer — `git worktree add` would refuse to run.
    case notAGitRepository(path: String)
    /// After the configured number of retries, every candidate id
    /// produced a path or branch collision. Extremely unlikely in
    /// practice; kept as an explicit failure path to avoid infinite
    /// loops when the random generator misbehaves.
    case collisionAfterRetries(attempts: Int)
    /// `git` exited with a non-zero status. Carries the full command
    /// so callers can reproduce it manually.
    case gitCommandFailed(command: String, stderr: String, exitCode: Int32)
    /// The worktree id is not tracked in the manifest.
    case worktreeNotFound(id: String)
    /// `git status --porcelain` reported unstaged or untracked changes
    /// and the caller did not pass `force = true`.
    case uncommittedChanges(path: String, statusOutput: String)
    /// Manifest file I/O or schema validation refused the operation.
    case manifestError(WorktreeManifestStoreError)
}

// MARK: - WorktreeService

/// Actor that owns all `git worktree` side effects for a user session.
///
/// Every public method is `async` so the caller never blocks the main
/// thread on a git invocation that can take seconds on a large repo.
/// The actor boundary also serialises concurrent requests — two
/// simultaneous `add` calls for the same origin repo never race past
/// each other when generating unique IDs, choosing branch names, or
/// persisting the manifest.
///
/// The service does **not** own a manifest store. Each operation
/// receives the store that matches its origin repository so one service
/// instance can be reused across multiple repos without re-instantiation.
/// `WorktreeManifestStore.forRepo(basePath:originRepoPath:)` is the
/// canonical way to construct the matching store.
///
/// Git discovery is delegated to `CodeReviewGit.resolveGitExecutableURL`
/// so there is a single source of truth for the binary path across the
/// code review workflow and the worktree workflow.
actor WorktreeService {

    /// Maximum number of id generations attempted before `add(...)`
    /// throws `collisionAfterRetries`.
    static let maximumCollisionRetries: Int = 3

    // MARK: Dependencies (injectable for tests)

    private let gitExecutableURLProvider: @Sendable () -> URL?
    private let clock: @Sendable () -> Date
    private let randomIDProvider: @Sendable (Int) -> String
    private let isGitRepository: @Sendable (URL) -> Bool

    init(
        gitExecutableURLProvider: @escaping @Sendable () -> URL? = {
            CodeReviewGit.resolveGitExecutableURL()
        },
        clock: @escaping @Sendable () -> Date = { Date() },
        randomIDProvider: @escaping @Sendable (Int) -> String = { length in
            WorktreeID.generate(length: length)
        },
        isGitRepository: (@Sendable (URL) -> Bool)? = nil
    ) {
        self.gitExecutableURLProvider = gitExecutableURLProvider
        self.clock = clock
        self.randomIDProvider = randomIDProvider
        if let isGitRepository {
            self.isGitRepository = isGitRepository
        } else {
            // Default to a freshly constructed provider per call so tests
            // that swap the filesystem contents between operations get
            // accurate answers without cache pollution.
            self.isGitRepository = { url in
                GitInfoProviderImpl().isGitRepository(at: url)
            }
        }
    }

    // MARK: - add

    /// Creates a new cocxy-managed worktree for `originRepoPath`.
    ///
    /// - Parameters:
    ///   - originRepoPath: Absolute path of the repo the worktree is
    ///     branched from.
    ///   - agent: Optional agent name used to expand the `{agent}`
    ///     placeholder in the branch template.
    ///   - tabID: Optional owning tab. The manifest records the binding
    ///     so later operations can resolve the tab from the worktree id
    ///     (and vice versa).
    ///   - config: Snapshot of the effective worktree config for this
    ///     operation — caller is responsible for applying per-project
    ///     overrides before calling.
    ///   - store: Manifest store matching `originRepoPath`. The service
    ///     takes no ownership; callers may cache a store per repo.
    /// - Returns: The freshly persisted manifest entry.
    /// - Throws: `WorktreeServiceError` for every foreseeable failure
    ///   and a rollback-aware `manifestError` if the manifest write
    ///   fails after the git worktree was created.
    @discardableResult
    func add(
        originRepoPath: URL,
        agent: String?,
        tabID: TabID?,
        config: WorktreeConfig,
        store: WorktreeManifestStore
    ) async throws -> WorktreeManifest.WorktreeEntry {
        guard config.enabled else { throw WorktreeServiceError.featureDisabled }
        guard gitExecutableURLProvider() != nil else {
            throw WorktreeServiceError.gitUnavailable
        }
        guard isGitRepository(originRepoPath) else {
            throw WorktreeServiceError.notAGitRepository(path: originRepoPath.path)
        }

        let candidate = try allocateUniqueCandidate(
            originRepoPath: originRepoPath,
            agent: agent,
            config: config
        )

        // Create the parent directory before `git worktree add` because
        // git expects the target path to not exist, but the parent
        // directories do.
        try FileManager.default.createDirectory(
            at: candidate.path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let addArguments = [
            "worktree", "add",
            "-b", candidate.branch,
            candidate.path.path,
            config.baseRef
        ]
        let result = try runGit(at: originRepoPath, arguments: addArguments)
        guard result.terminationStatus == 0 else {
            throw WorktreeServiceError.gitCommandFailed(
                command: "git " + addArguments.joined(separator: " "),
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }

        let entry = WorktreeManifest.WorktreeEntry(
            id: candidate.id,
            branch: candidate.branch,
            path: candidate.path,
            createdAt: clock(),
            agent: agent,
            tabID: tabID
        )

        do {
            try await store.upsert(entry)
        } catch let error as WorktreeManifestStoreError {
            // Rollback the git worktree so a failed manifest write does
            // not leave a phantom directory behind.
            _ = try? runGit(
                at: originRepoPath,
                arguments: ["worktree", "remove", "--force", candidate.path.path]
            )
            throw WorktreeServiceError.manifestError(error)
        }
        return entry
    }

    // MARK: - remove

    /// Removes a worktree identified by `id` in the given origin repo.
    ///
    /// - Parameter force: When `false` (default), the call fails with
    ///   `uncommittedChanges` if `git status --porcelain` reports any
    ///   modification. Set `force = true` to mirror
    ///   `git worktree remove --force`.
    ///
    /// Returns the removed entry so callers can log or emit
    /// notifications. Throws `worktreeNotFound` when the id is absent
    /// from the manifest.
    @discardableResult
    func remove(
        id: String,
        force: Bool = false,
        originRepoPath: URL,
        store: WorktreeManifestStore
    ) async throws -> WorktreeManifest.WorktreeEntry {
        let manifest = try await loadManifest(store)
        guard let entry = manifest.entry(withID: id) else {
            throw WorktreeServiceError.worktreeNotFound(id: id)
        }

        if !force {
            let statusResult = try runGit(
                at: entry.path,
                arguments: ["status", "--porcelain"]
            )
            // A missing worktree path produces a non-zero exit; we fall
            // through so the caller can still clean up the manifest
            // below. A zero exit with non-empty output means the
            // worktree exists and has dirty state — block.
            if statusResult.terminationStatus == 0 {
                let trimmed = statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    throw WorktreeServiceError.uncommittedChanges(
                        path: entry.path.path,
                        statusOutput: statusResult.stdout
                    )
                }
            }
        }

        var removeArguments = ["worktree", "remove"]
        if force { removeArguments.append("--force") }
        removeArguments.append(entry.path.path)

        let removeResult = try runGit(at: originRepoPath, arguments: removeArguments)
        // A non-zero exit may mean the worktree already vanished. Only
        // abort when the failure is something other than "path is not
        // a working tree" — otherwise drop the manifest entry so the
        // user can re-run the command cleanly.
        if removeResult.terminationStatus != 0 {
            let stderrLower = removeResult.stderr.lowercased()
            let isAlreadyGone = stderrLower.contains("not a working tree")
                || stderrLower.contains("does not exist")
            if !isAlreadyGone {
                throw WorktreeServiceError.gitCommandFailed(
                    command: "git " + removeArguments.joined(separator: " "),
                    stderr: removeResult.stderr,
                    exitCode: removeResult.terminationStatus
                )
            }
        }

        do {
            _ = try await store.remove(id: id)
        } catch let error as WorktreeManifestStoreError {
            throw WorktreeServiceError.manifestError(error)
        }
        return entry
    }

    // MARK: - list

    /// Returns every entry currently tracked in the manifest. The
    /// caller is expected to also invoke `prune` if drift against git
    /// must be reconciled first.
    func list(store: WorktreeManifestStore) async throws -> [WorktreeManifest.WorktreeEntry] {
        let manifest = try await loadManifest(store)
        return manifest.entries
    }

    // MARK: - prune

    /// Reconciles the manifest with `git worktree list` by removing
    /// orphaned entries (entries whose path is no longer known to git).
    ///
    /// Does not touch worktrees that git knows about but the manifest
    /// does not — those were created outside cocxy and are not the
    /// service's to clean up.
    ///
    /// Returns the list of entries that were pruned.
    @discardableResult
    func prune(
        originRepoPath: URL,
        store: WorktreeManifestStore
    ) async throws -> [WorktreeManifest.WorktreeEntry] {
        var manifest = try await loadManifest(store)
        let gitPaths = try listGitWorktreePaths(at: originRepoPath)
        let drift = manifest.drift(comparedWith: gitPaths)

        var pruned: [WorktreeManifest.WorktreeEntry] = []
        for orphanID in drift.orphanedManifestIDs {
            if let removed = manifest.remove(id: orphanID) {
                pruned.append(removed)
            }
        }
        if !pruned.isEmpty {
            do {
                try await store.save(manifest)
            } catch let error as WorktreeManifestStoreError {
                throw WorktreeServiceError.manifestError(error)
            }
        }
        return pruned
    }

    // MARK: - status

    /// Runs `git status --porcelain` inside the worktree pointed to by
    /// `id` and returns a snapshot the CLI/UI can render.
    func status(
        id: String,
        store: WorktreeManifestStore
    ) async throws -> WorktreeStatusSnapshot {
        let manifest = try await loadManifest(store)
        guard let entry = manifest.entry(withID: id) else {
            throw WorktreeServiceError.worktreeNotFound(id: id)
        }
        let result = try runGit(at: entry.path, arguments: ["status", "--porcelain"])
        let lines: [String]
        if result.terminationStatus == 0 {
            lines = result.stdout
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        } else {
            lines = []
        }
        return WorktreeStatusSnapshot(
            entry: entry,
            isClean: lines.isEmpty,
            porcelainLines: lines
        )
    }

    // MARK: - Private helpers

    /// Picks a unique `(id, branch, path)` triple, retrying up to
    /// `maximumCollisionRetries` times if any component collides.
    /// Increases `idLength` by one on each retry to reduce the retry
    /// probability even further.
    private func allocateUniqueCandidate(
        originRepoPath: URL,
        agent: String?,
        config: WorktreeConfig
    ) throws -> (id: String, branch: String, path: URL) {
        let repoHash = WorktreeManifest.hashForRepoPath(originRepoPath)
        let expandedBase = (config.basePath as NSString).expandingTildeInPath
        let storageRoot = URL(fileURLWithPath: expandedBase, isDirectory: true)
            .appendingPathComponent(repoHash, isDirectory: true)
        let now = clock()

        for attempt in 0..<Self.maximumCollisionRetries {
            let length = min(config.idLength + attempt, WorktreeConfig.maxIDLength)
            let candidateID = randomIDProvider(length)
            let candidatePath = storageRoot
                .appendingPathComponent(candidateID, isDirectory: true)
            let candidateBranch = WorktreeBranch.expand(
                template: config.branchTemplate,
                agent: agent,
                id: candidateID,
                date: now
            )

            if FileManager.default.fileExists(atPath: candidatePath.path) {
                continue
            }
            if try branchExists(candidateBranch, at: originRepoPath) {
                continue
            }
            return (candidateID, candidateBranch, candidatePath)
        }

        throw WorktreeServiceError.collisionAfterRetries(
            attempts: Self.maximumCollisionRetries
        )
    }

    private func branchExists(
        _ branch: String,
        at originRepoPath: URL
    ) throws -> Bool {
        let result = try runGit(
            at: originRepoPath,
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"]
        )
        // show-ref --verify --quiet exits 0 when the ref exists and
        // 1 when it does not; any other code indicates an unexpected
        // failure and is surfaced to the caller.
        switch result.terminationStatus {
        case 0: return true
        case 1: return false
        default:
            throw WorktreeServiceError.gitCommandFailed(
                command: "git show-ref --verify --quiet refs/heads/\(branch)",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
    }

    private func listGitWorktreePaths(at originRepoPath: URL) throws -> [URL] {
        let result = try runGit(
            at: originRepoPath,
            arguments: ["worktree", "list", "--porcelain"]
        )
        guard result.terminationStatus == 0 else {
            throw WorktreeServiceError.gitCommandFailed(
                command: "git worktree list --porcelain",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        var paths: [URL] = []
        for line in result.stdout.split(separator: "\n") {
            let prefix = "worktree "
            if line.hasPrefix(prefix) {
                let raw = String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty {
                    paths.append(URL(fileURLWithPath: raw))
                }
            }
        }
        return paths
    }

    private func loadManifest(
        _ store: WorktreeManifestStore
    ) async throws -> WorktreeManifest {
        do {
            return try await store.load()
        } catch let error as WorktreeManifestStoreError {
            throw WorktreeServiceError.manifestError(error)
        }
    }

    /// Thin wrapper around `CodeReviewGit.run` that feeds in the
    /// resolved git binary and translates low-level errors into
    /// `gitCommandFailed` / `gitUnavailable`. Keeping this method the
    /// single entry point to git lets the test-only override sit on a
    /// single call site.
    private func runGit(
        at workingDirectory: URL,
        arguments: [String]
    ) throws -> CodeReviewGitResult {
        guard let gitURL = gitExecutableURLProvider() else {
            throw WorktreeServiceError.gitUnavailable
        }
        do {
            return try CodeReviewGit.run(
                workingDirectory: workingDirectory,
                arguments: arguments,
                gitExecutableURLOverride: gitURL
            )
        } catch {
            throw WorktreeServiceError.gitCommandFailed(
                command: "git " + arguments.joined(separator: " "),
                stderr: "\(error)",
                exitCode: -1
            )
        }
    }
}
