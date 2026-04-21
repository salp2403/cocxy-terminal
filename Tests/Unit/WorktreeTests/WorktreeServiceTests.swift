// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeServiceTests.swift - Integration coverage for the actor that
// wraps `git worktree` operations.
//
// The tests create a real git repository in a unique temporary
// directory per test run so the behaviour exercised is exactly what
// production would see. This keeps the suite hermetic (no shared
// global state) while avoiding the impedance mismatch of a fully
// mocked git wrapper.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("WorktreeService")
struct WorktreeServiceTests {

    // MARK: - Fixture helpers

    /// Returns `nil` when git is not available on this machine. Every
    /// test calls this first and skips the body with `#expect(skip:)`
    /// when the binary is missing, so the suite stays green on CI
    /// runners that do not ship git.
    private func gitAvailable() -> Bool {
        CodeReviewGit.resolveGitExecutableURL() != nil
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-worktree-service", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func removeTempRoot(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Initialises a git repository with a single committed file and
    /// returns the origin repo path. The repository lives under
    /// `<tempRoot>/origin/` so tests can place worktree storage
    /// alongside at `<tempRoot>/worktrees/`.
    private func initOriginRepo(under tempRoot: URL) throws -> URL {
        let origin = tempRoot.appendingPathComponent("origin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: origin,
            withIntermediateDirectories: true
        )
        // Force main as the default branch so base-ref defaults that
        // expect a known branch name keep working on machines that
        // default to master.
        try runGitCommand(
            at: origin,
            arguments: ["init", "-q", "-b", "main"]
        )
        try runGitCommand(
            at: origin,
            arguments: ["config", "user.email", "dev@cocxy.dev"]
        )
        try runGitCommand(
            at: origin,
            arguments: ["config", "user.name", "Test"]
        )
        try "hello\n".write(
            to: origin.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGitCommand(at: origin, arguments: ["add", "README.md"])
        try runGitCommand(at: origin, arguments: ["commit", "-q", "-m", "initial"])
        return origin
    }

    @discardableResult
    private func runGitCommand(
        at directory: URL,
        arguments: [String]
    ) throws -> CodeReviewGitResult {
        guard let git = CodeReviewGit.resolveGitExecutableURL() else {
            throw TestError.gitUnavailable
        }
        return try CodeReviewGit.run(
            workingDirectory: directory,
            arguments: arguments,
            gitExecutableURLOverride: git
        )
    }

    private enum TestError: Error { case gitUnavailable }

    private func makeConfig(
        enabled: Bool = true,
        basePath: String,
        branchTemplate: String = "cocxy/{agent}/{id}",
        baseRef: String = "HEAD",
        idLength: Int = 6
    ) -> WorktreeConfig {
        WorktreeConfig(
            enabled: enabled,
            basePath: basePath,
            branchTemplate: branchTemplate,
            baseRef: baseRef,
            onClose: .keep,
            openInNewTab: true,
            idLength: idLength,
            inheritProjectConfig: true,
            showBadge: true
        )
    }

    private func makeStore(
        originRepoPath: URL,
        basePath: String
    ) -> WorktreeManifestStore {
        WorktreeManifestStore.forRepo(
            basePath: basePath,
            originRepoPath: originRepoPath
        )
    }

    // MARK: - add

    @Test("add creates a real git worktree and a manifest entry")
    func addCreatesRealWorktreeAndManifestEntry() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }

        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot
            .appendingPathComponent("worktrees", isDirectory: true)
            .path

        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        let entry = try await service.add(
            originRepoPath: origin,
            agent: "claude",
            tabID: nil,
            config: config,
            store: store
        )

        // Worktree directory is on disk with a populated README.
        #expect(FileManager.default.fileExists(atPath: entry.path.path))
        let readmePath = entry.path.appendingPathComponent("README.md").path
        #expect(FileManager.default.fileExists(atPath: readmePath))

        // Manifest records the entry.
        let listed = try await service.list(store: store)
        #expect(listed.count == 1)
        #expect(listed.first?.id == entry.id)
        #expect(listed.first?.branch == entry.branch)
        #expect(listed.first?.agent == "claude")

        // git sees the new worktree.
        let gitList = try runGitCommand(
            at: origin,
            arguments: ["worktree", "list", "--porcelain"]
        )
        #expect(gitList.stdout.contains(entry.path.path))
    }

    @Test("add refuses when the feature is disabled")
    func addRefusesWhenFeatureDisabled() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }

        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(enabled: false, basePath: storagePath)

        await #expect(throws: WorktreeServiceError.self) {
            try await service.add(
                originRepoPath: origin,
                agent: nil,
                tabID: nil,
                config: config,
                store: store
            )
        }
    }

    @Test("add refuses when origin is not a git repository")
    func addRefusesWhenOriginIsNotGit() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }

        // `tempRoot` itself is an empty directory, not a git repo.
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: tempRoot, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        await #expect(throws: WorktreeServiceError.self) {
            try await service.add(
                originRepoPath: tempRoot,
                agent: nil,
                tabID: nil,
                config: config,
                store: store
            )
        }
    }

    // MARK: - remove

    @Test("remove rejects a dirty worktree without force")
    func removeRejectsDirtyWorktreeWithoutForce() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        let entry = try await service.add(
            originRepoPath: origin,
            agent: "claude",
            tabID: nil,
            config: config,
            store: store
        )

        // Introduce an uncommitted change inside the worktree.
        try "dirty\n".write(
            to: entry.path.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        await #expect(throws: WorktreeServiceError.self) {
            try await service.remove(
                id: entry.id,
                force: false,
                originRepoPath: origin,
                store: store
            )
        }

        // The worktree survives a failed remove.
        #expect(FileManager.default.fileExists(atPath: entry.path.path))
        let afterFail = try await service.list(store: store)
        #expect(afterFail.contains { $0.id == entry.id })
    }

    @Test("remove with force deletes even a dirty worktree")
    func removeWithForceDeletesDirty() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        let entry = try await service.add(
            originRepoPath: origin,
            agent: "claude",
            tabID: nil,
            config: config,
            store: store
        )
        try "dirty\n".write(
            to: entry.path.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        try await service.remove(
            id: entry.id,
            force: true,
            originRepoPath: origin,
            store: store
        )

        #expect(!FileManager.default.fileExists(atPath: entry.path.path))
        let afterRemove = try await service.list(store: store)
        #expect(afterRemove.isEmpty)
    }

    @Test("remove of an unknown id throws worktreeNotFound")
    func removeUnknownThrows() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)

        await #expect(throws: WorktreeServiceError.self) {
            try await service.remove(
                id: "not-real",
                originRepoPath: origin,
                store: store
            )
        }
    }

    // MARK: - prune

    @Test("prune removes manifest entries whose worktree git no longer tracks")
    func prunePullsOrphansFromManifest() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        // Add two worktrees, then simulate an out-of-band removal on
        // one of them (direct git worktree remove in a shell). The
        // prune call should drop only the orphaned entry.
        let first = try await service.add(
            originRepoPath: origin,
            agent: "claude",
            tabID: nil,
            config: config,
            store: store
        )
        let second = try await service.add(
            originRepoPath: origin,
            agent: "codex",
            tabID: nil,
            config: config,
            store: store
        )

        try runGitCommand(
            at: origin,
            arguments: ["worktree", "remove", "--force", first.path.path]
        )

        let pruned = try await service.prune(
            originRepoPath: origin,
            store: store
        )

        #expect(pruned.map(\.id) == [first.id])
        let remaining = try await service.list(store: store)
        #expect(remaining.map(\.id) == [second.id])
    }

    // MARK: - status

    @Test("status returns clean on an untouched worktree")
    func statusCleanWorktree() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        let entry = try await service.add(
            originRepoPath: origin,
            agent: nil,
            tabID: nil,
            config: config,
            store: store
        )

        let snapshot = try await service.status(id: entry.id, store: store)
        #expect(snapshot.isClean)
        #expect(snapshot.porcelainLines.isEmpty)
        #expect(snapshot.entry.id == entry.id)
    }

    @Test("status returns porcelain lines on a dirty worktree")
    func statusDirtyWorktree() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let service = WorktreeService()
        let store = makeStore(originRepoPath: origin, basePath: storagePath)
        let config = makeConfig(basePath: storagePath)

        let entry = try await service.add(
            originRepoPath: origin,
            agent: nil,
            tabID: nil,
            config: config,
            store: store
        )
        try "modified\n".write(
            to: entry.path.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try await service.status(id: entry.id, store: store)
        #expect(!snapshot.isClean)
        #expect(!snapshot.porcelainLines.isEmpty)
        #expect(snapshot.porcelainLines.first?.hasSuffix("README.md") == true)
    }

    // MARK: - Collision handling

    @Test("add retries with longer IDs when the first id collides with a branch")
    func addRetriesOnBranchCollision() async throws {
        guard gitAvailable() else { return }

        let tempRoot = try makeTempRoot()
        defer { removeTempRoot(tempRoot) }
        let origin = try initOriginRepo(under: tempRoot)
        let storagePath = tempRoot.appendingPathComponent("worktrees").path
        let config = makeConfig(basePath: storagePath)

        // Create a branch ahead of time whose name matches the first
        // id the service would generate. Subsequent retries use ids
        // the pre-made branch cannot block, so the operation succeeds.
        let forcedIDs = ["taken1", "uniq22", "uniq33"]
        let cursor = SequenceCursor(values: forcedIDs)
        let service = WorktreeService(
            randomIDProvider: { _ in cursor.next() }
        )
        let store = makeStore(originRepoPath: origin, basePath: storagePath)

        // Pre-create a branch matching the first id's template output.
        let firstBranch = WorktreeBranch.expand(
            template: config.branchTemplate,
            agent: "claude",
            id: forcedIDs[0]
        )
        try runGitCommand(at: origin, arguments: ["branch", firstBranch])

        let entry = try await service.add(
            originRepoPath: origin,
            agent: "claude",
            tabID: nil,
            config: config,
            store: store
        )
        #expect(entry.id != forcedIDs[0])
        #expect(entry.id == forcedIDs[1])
    }
}

/// Thread-safe cursor used by tests that need a deterministic sequence
/// of id values returned from a `@Sendable` callback. Not part of the
/// public API — production code uses `WorktreeID.generate` directly.
private final class SequenceCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var index: Int = 0
    private let values: [String]

    init(values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(index, values.count - 1)
        index = min(index + 1, values.count - 1)
        return values[clamped]
    }
}
