// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitInfoProviderWorktreeSwiftTestingTests.swift - Verifies that the
// branch/repo detection logic in `GitInfoProviderImpl` handles linked
// git worktrees (where `.git` is a text file containing
// `gitdir: <path>`) in addition to the regular case where `.git` is a
// directory.
//
// Prior to v0.1.81, `readBranchFromDisk` and `isGitRepository` assumed
// `.git` was always a directory, which made linked worktrees look like
// non-git folders. These tests pin the fixed behaviour so a future
// refactor cannot reintroduce the bug silently.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("GitInfoProvider — linked worktrees")
struct GitInfoProviderWorktreeSwiftTestingTests {

    // MARK: - Fixture helpers

    /// Creates an isolated temporary directory for a single test run
    /// and returns a block that the test must call to clean it up.
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-gitinfo-worktree-tests", isDirectory: true)
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

    /// Writes a complete linked-worktree fixture:
    ///   <root>/worktree/.git      → "gitdir: <gitdir>"
    ///   <root>/main/.git/worktrees/wt/HEAD → HEAD contents
    ///
    /// The "gitdir" pointer can be emitted as absolute or relative path
    /// depending on `useAbsolutePath`. Returns the worktree root.
    private func buildLinkedWorktreeFixture(
        root: URL,
        headContents: String,
        useAbsolutePath: Bool
    ) throws -> URL {
        let mainGitDir = root
            .appendingPathComponent("main/.git/worktrees/wt", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mainGitDir,
            withIntermediateDirectories: true
        )
        try headContents.write(
            to: mainGitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeRoot = root.appendingPathComponent("worktree", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeRoot,
            withIntermediateDirectories: true
        )

        let pointer: String
        if useAbsolutePath {
            pointer = "gitdir: \(mainGitDir.path)\n"
        } else {
            // Relative path from worktreeRoot to mainGitDir.
            pointer = "gitdir: ../main/.git/worktrees/wt\n"
        }
        try pointer.write(
            to: worktreeRoot.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        return worktreeRoot
    }

    // MARK: - Linked worktree detection

    @Test("linked worktree with absolute gitdir pointer is a git repository")
    func linkedWorktreeAbsolutePathIsGitRepository() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let worktree = try buildLinkedWorktreeFixture(
            root: tempRoot,
            headContents: "ref: refs/heads/feature-1\n",
            useAbsolutePath: true
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.isGitRepository(at: worktree) == true)
    }

    @Test("linked worktree with relative gitdir pointer is a git repository")
    func linkedWorktreeRelativePathIsGitRepository() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let worktree = try buildLinkedWorktreeFixture(
            root: tempRoot,
            headContents: "ref: refs/heads/feature-1\n",
            useAbsolutePath: false
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.isGitRepository(at: worktree) == true)
    }

    // MARK: - Branch reading

    @Test("linked worktree branch name is read from the pointed HEAD file")
    func linkedWorktreeBranchReadsFromPointedHead() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let worktree = try buildLinkedWorktreeFixture(
            root: tempRoot,
            headContents: "ref: refs/heads/cocxy/claude/abc123\n",
            useAbsolutePath: true
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.currentBranch(at: worktree) == "cocxy/claude/abc123")
    }

    @Test("detached HEAD in a linked worktree returns nil (no branch name)")
    func detachedHeadInLinkedWorktreeReturnsNil() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let worktree = try buildLinkedWorktreeFixture(
            root: tempRoot,
            headContents: "a3f7de01234567890123456789012345678901234\n",
            useAbsolutePath: true
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.currentBranch(at: worktree) == nil)
    }

    @Test("malformed .git file (no gitdir: prefix) returns nil")
    func malformedDotGitFileReturnsNil() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let worktreeRoot = tempRoot.appendingPathComponent("malformed", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeRoot,
            withIntermediateDirectories: true
        )
        try "this is not a gitdir pointer\n".write(
            to: worktreeRoot.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.isGitRepository(at: worktreeRoot) == false)
        #expect(provider.currentBranch(at: worktreeRoot) == nil)
    }

    @Test("empty .git file returns nil (defensive)")
    func emptyDotGitFileReturnsNil() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let worktreeRoot = tempRoot.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeRoot,
            withIntermediateDirectories: true
        )
        try "".write(
            to: worktreeRoot.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.isGitRepository(at: worktreeRoot) == false)
    }

    @Test("directory without .git is not a git repository")
    func directoryWithoutDotGitIsNotRepository() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        let bare = tempRoot.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bare,
            withIntermediateDirectories: true
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.isGitRepository(at: bare) == false)
        #expect(provider.currentBranch(at: bare) == nil)
    }

    // MARK: - Regression: regular (main) worktrees still work

    @Test("regular repository with .git directory still reports its branch")
    func regularRepositoryReadingUnaffected() throws {
        let tempRoot = try makeTempDir()
        defer { removeTempDir(tempRoot) }

        // Build a classic `.git/` directory with a HEAD file.
        let repoRoot = tempRoot.appendingPathComponent("repo", isDirectory: true)
        let gitDir = repoRoot.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(
            at: gitDir,
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/main\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let provider = GitInfoProviderImpl()
        #expect(provider.isGitRepository(at: repoRoot) == true)
        #expect(provider.currentBranch(at: repoRoot) == "main")
    }
}
