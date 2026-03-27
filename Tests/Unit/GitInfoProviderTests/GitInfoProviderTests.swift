// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitInfoProviderTests.swift - Tests for GitInfoProvider implementation.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Git Info Provider Tests

/// Tests for `GitInfoProviderImpl` covering branch detection, caching,
/// non-git directories and the observe/publish mechanism.
///
/// These tests use temporary directories to simulate git repositories
/// without requiring a real git installation for most cases.
final class GitInfoProviderTests: XCTestCase {

    private var provider: GitInfoProviderImpl!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        provider = GitInfoProviderImpl()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitInfoProviderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        provider = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a fake .git/HEAD file to simulate a git repository.
    private func createFakeGitRepo(
        branch: String = "main",
        at directory: URL? = nil
    ) {
        let dir = directory ?? tempDirectory!
        let gitDir = dir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(
            at: gitDir,
            withIntermediateDirectories: true
        )
        let headContent = "ref: refs/heads/\(branch)\n"
        try? headContent.write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Creates a detached HEAD state in a fake .git directory.
    private func createDetachedHead(
        commitHash: String = "a1b2c3d4e5f6",
        at directory: URL? = nil
    ) {
        let dir = directory ?? tempDirectory!
        let gitDir = dir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(
            at: gitDir,
            withIntermediateDirectories: true
        )
        let headContent = "\(commitHash)\n"
        try? headContent.write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - isGitRepository

    func testIsGitRepositoryReturnsTrueForGitDirectory() {
        createFakeGitRepo()

        let result = provider.isGitRepository(at: tempDirectory)

        XCTAssertTrue(result, "Directory with .git/HEAD should be detected as git repo")
    }

    func testIsGitRepositoryReturnsFalseForNonGitDirectory() {
        // tempDirectory has no .git folder
        let result = provider.isGitRepository(at: tempDirectory)

        XCTAssertFalse(result, "Directory without .git should not be detected as git repo")
    }

    func testIsGitRepositoryReturnsFalseForNonExistentDirectory() {
        let nonExistent = URL(fileURLWithPath: "/nonexistent/path/that/does/not/exist")

        let result = provider.isGitRepository(at: nonExistent)

        XCTAssertFalse(result, "Non-existent directory should not be detected as git repo")
    }

    // MARK: - currentBranch

    func testCurrentBranchReturnsCorrectBranch() {
        createFakeGitRepo(branch: "main")

        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertEqual(branch, "main")
    }

    func testCurrentBranchReturnsFeatureBranch() {
        createFakeGitRepo(branch: "feature/T-018-git-info")

        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertEqual(branch, "feature/T-018-git-info")
    }

    func testCurrentBranchReturnsNilForNonGitDirectory() {
        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertNil(branch, "Non-git directory should return nil branch")
    }

    func testCurrentBranchReturnsNilForDetachedHead() {
        createDetachedHead(commitHash: "a1b2c3d4e5f6789012345678901234567890abcd")

        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertNil(branch, "Detached HEAD should return nil branch")
    }

    func testCurrentBranchReturnsNilForNonExistentDirectory() {
        let nonExistent = URL(fileURLWithPath: "/nonexistent/dir")

        let branch = provider.currentBranch(at: nonExistent)

        XCTAssertNil(branch)
    }

    // MARK: - Cache Behavior

    func testCurrentBranchUsesCachedValue() {
        createFakeGitRepo(branch: "cached-branch")

        // First call populates cache.
        let firstResult = provider.currentBranch(at: tempDirectory)
        XCTAssertEqual(firstResult, "cached-branch")

        // Delete the .git/HEAD to prove cache is used.
        let headPath = tempDirectory.appendingPathComponent(".git/HEAD")
        try? FileManager.default.removeItem(at: headPath)

        // Should still return cached value (TTL not expired).
        let secondResult = provider.currentBranch(at: tempDirectory)
        XCTAssertEqual(secondResult, "cached-branch",
                       "Should return cached value before TTL expires")
    }

    func testInvalidateCacheClearsAll() {
        createFakeGitRepo(branch: "old-branch")

        // Populate cache.
        _ = provider.currentBranch(at: tempDirectory)

        // Invalidate.
        provider.invalidateCache()

        // Delete .git so the re-read fails.
        try? FileManager.default.removeItem(
            at: tempDirectory.appendingPathComponent(".git")
        )

        let result = provider.currentBranch(at: tempDirectory)
        XCTAssertNil(result, "After cache invalidation and removal, should return nil")
    }

    func testInvalidateCacheForDirectoryClearsSpecificEntry() {
        // Create two repos.
        let dir2 = tempDirectory.appendingPathComponent("subdir")
        try? FileManager.default.createDirectory(
            at: dir2,
            withIntermediateDirectories: true
        )
        createFakeGitRepo(branch: "branch-a", at: tempDirectory)
        createFakeGitRepo(branch: "branch-b", at: dir2)

        // Populate cache for both.
        _ = provider.currentBranch(at: tempDirectory)
        _ = provider.currentBranch(at: dir2)

        // Invalidate only dir2.
        provider.invalidateCache(for: dir2)

        // Remove dir2's .git.
        try? FileManager.default.removeItem(
            at: dir2.appendingPathComponent(".git")
        )

        // tempDirectory should still be cached.
        let resultA = provider.currentBranch(at: tempDirectory)
        XCTAssertEqual(resultA, "branch-a", "Cache for tempDirectory should not be invalidated")

        // dir2 should re-read (and fail since we removed .git).
        let resultB = provider.currentBranch(at: dir2)
        XCTAssertNil(resultB, "After invalidation, dir2 should re-read from disk")
    }

    // MARK: - observeBranch

    func testObserveBranchEmitsInitialValue() {
        createFakeGitRepo(branch: "observe-branch")

        let branchExpectation = expectation(description: "Should emit initial branch value")

        final class BranchHolder: @unchecked Sendable {
            var value: String?
        }
        let holder = BranchHolder()

        let cancellable = provider.observeBranch(at: tempDirectory) { branch in
            holder.value = branch
            branchExpectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(holder.value, "observe-branch")
        cancellable.cancel()
    }

    func testObserveBranchEmitsNilForNonGitDirectory() {
        let nilExpectation = expectation(description: "Should emit nil for non-git dir")

        final class NilTracker: @unchecked Sendable {
            var receivedNil = false
        }
        let tracker = NilTracker()

        let cancellable = provider.observeBranch(at: tempDirectory) { branch in
            if branch == nil {
                tracker.receivedNil = true
                nilExpectation.fulfill()
            }
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertTrue(tracker.receivedNil)
        cancellable.cancel()
    }

    func testObserveBranchCancellationStopsObservation() {
        createFakeGitRepo(branch: "cancel-test")

        // Use a class-based counter to satisfy Sendable requirements.
        final class CallCounter: @unchecked Sendable {
            var count = 0
        }
        let counter = CallCounter()

        let cancellable = provider.observeBranch(at: tempDirectory) { _ in
            counter.count += 1
        }

        // Give a moment for initial callback.
        let waitExpectation = expectation(description: "Wait for callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            waitExpectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        let countAfterCancel = counter.count
        cancellable.cancel()

        // After cancel, no more callbacks should fire.
        let postCancelExpectation = expectation(description: "Wait after cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            postCancelExpectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        XCTAssertEqual(counter.count, countAfterCancel,
                       "No more callbacks should fire after cancellation")
    }

    // MARK: - Edge Cases

    func testCurrentBranchHandlesMalformedGitHead() {
        let gitDir = tempDirectory.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(
            at: gitDir,
            withIntermediateDirectories: true
        )
        // Malformed content -- not a ref and not a valid hash.
        try? "garbage content\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertNil(branch, "Malformed .git/HEAD should return nil")
    }

    func testCurrentBranchHandlesEmptyGitHead() {
        let gitDir = tempDirectory.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(
            at: gitDir,
            withIntermediateDirectories: true
        )
        try? "".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertNil(branch, "Empty .git/HEAD should return nil")
    }

    func testCurrentBranchHandlesBranchWithSlashes() {
        createFakeGitRepo(branch: "feature/deep/nested/branch")

        let branch = provider.currentBranch(at: tempDirectory)

        XCTAssertEqual(branch, "feature/deep/nested/branch")
    }
}
