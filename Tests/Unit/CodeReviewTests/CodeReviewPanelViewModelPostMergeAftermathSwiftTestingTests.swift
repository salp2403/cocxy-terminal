// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModelPostMergeAftermathSwiftTestingTests.swift
// Coverage for the post-merge auto-pull integration shipped in v0.1.87.
// Verifies that the Code Review panel's success path invokes the
// aftermath handler with the correct working directory + base branch,
// folds the typed outcome into the info banner, and routes typed
// errors through the error banner — all under the existing
// `mergePullRequestHandler` contract from v0.1.86.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("CodeReviewPanelViewModel post-merge aftermath")
struct CodeReviewPanelViewModelPostMergeAftermathSwiftTestingTests {

    // MARK: - Fixtures

    private static func mergedPullRequest(
        number: Int = 42,
        baseRefName: String = "main",
        headRefName: String = "feature/test"
    ) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: "Test PR",
            state: .merged,
            author: GitHubUser(login: "octocat"),
            headRefName: headRefName,
            baseRefName: baseRefName,
            url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func cleanMergeability(number: Int = 42) -> GitHubMergeability {
        GitHubMergeability(
            pullRequestNumber: number,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: true
        )
    }

    private static let workingDirectory = URL(fileURLWithPath: "/tmp/cocxy-test-aftermath")

    // MARK: - mergeBannerMessage helper

    @Test("mergeBannerMessage without outcome returns the merge head only")
    func bannerWithoutOutcome() {
        let message = CodeReviewPanelViewModel.mergeBannerMessage(
            mergedNumber: 42,
            method: .squash,
            outcome: nil
        )
        #expect(message == "Merged PR #42 via Squash & Merge.")
    }

    @Test("mergeBannerMessage appends synced outcome to the merge head")
    func bannerWithSyncedOutcome() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 3)
        let message = CodeReviewPanelViewModel.mergeBannerMessage(
            mergedNumber: 42,
            method: .squash,
            outcome: outcome
        )
        #expect(message.hasPrefix("Merged PR #42 via Squash & Merge."))
        #expect(message.contains("3 commits pulled"))
    }

    @Test("mergeBannerMessage appends fetchedOnly outcome with both branches")
    func bannerWithFetchedOnly() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "feat/x", baseBranch: "main")
        let message = CodeReviewPanelViewModel.mergeBannerMessage(
            mergedNumber: 42,
            method: .merge,
            outcome: outcome
        )
        #expect(message.hasPrefix("Merged PR #42 via Merge Commit."))
        #expect(message.contains("`main`"))
        #expect(message.contains("`feat/x`"))
    }

    // MARK: - userFacingAftermathErrorMessage

    @Test("typed aftermath error maps to its localized description")
    func typedErrorMessage() {
        let error = GitMergeAftermathError.fetchFailed(stderr: "fatal: unable", exitCode: 128)
        let message = CodeReviewPanelViewModel.userFacingAftermathErrorMessage(for: error)
        #expect(message.contains("unable") || message.lowercased().contains("fetch"))
    }

    @Test("non-typed error falls back to localizedDescription with default copy")
    func untypedErrorMessage() {
        struct CustomError: LocalizedError {
            var errorDescription: String? { "custom failure" }
        }
        let message = CodeReviewPanelViewModel.userFacingAftermathErrorMessage(for: CustomError())
        #expect(message == "custom failure")
    }

    // MARK: - runPostMergeAftermathIfWired guards

    @Test("runPostMergeAftermathIfWired no-op when handler is nil")
    func aftermathNoOpWhenHandlerNil() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.pullRequestMergeInfoMessage == nil)
        #expect(viewModel.pullRequestMergeErrorMessage == nil)
    }

    @Test("runPostMergeAftermathIfWired no-op when activeTabCwdProvider returns nil")
    func aftermathNoOpWhenWorkingDirectoryNil() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { nil }
        let invocations = Box<Int>(0)
        viewModel.postMergeAftermathHandler = { _, _ in
            invocations.value += 1
            return .skippedNotInRepo
        }
        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(invocations.value == 0)
    }

    @Test("runPostMergeAftermathIfWired no-op when baseBranch is whitespace")
    func aftermathNoOpWhenBaseBranchEmpty() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        let invocations = Box<Int>(0)
        viewModel.postMergeAftermathHandler = { _, _ in
            invocations.value += 1
            return .skippedNotInRepo
        }
        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "   ",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(invocations.value == 0)
    }

    // MARK: - runPostMergeAftermathIfWired success / failure paths

    @Test("aftermath success folds outcome into the info banner")
    func aftermathSuccessFoldsBanner() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }

        let receivedDirectory = Box<URL?>(nil)
        let receivedBaseBranch = Box<String?>(nil)
        viewModel.postMergeAftermathHandler = { directory, baseBranch in
            receivedDirectory.value = directory
            receivedBaseBranch.value = baseBranch
            return .synced(branch: "main", ahead: 0, behind: 2)
        }

        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )

        try await waitForCondition {
            viewModel.pullRequestMergeInfoMessage?.contains("synced") == true
        }
        #expect(receivedDirectory.value == Self.workingDirectory)
        #expect(receivedBaseBranch.value == "main")
        #expect(viewModel.pullRequestMergeInfoMessage?.contains("Merged PR #42") == true)
        #expect(viewModel.pullRequestMergeInfoMessage?.contains("2 commits pulled") == true)
        #expect(viewModel.pullRequestMergeErrorMessage == nil)
    }

    @Test("aftermath baseBranch is trimmed before invoking the handler")
    func aftermathBaseBranchTrimmed() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }

        let receivedBaseBranch = Box<String?>(nil)
        viewModel.postMergeAftermathHandler = { _, baseBranch in
            receivedBaseBranch.value = baseBranch
            return .synced(branch: "main", ahead: 0, behind: 0)
        }

        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "  main  ",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )

        try await waitForCondition { receivedBaseBranch.value != nil }
        #expect(receivedBaseBranch.value == "main")
    }

    @Test("aftermath skipping (dirty tree) lands as info, never error")
    func aftermathDirtyTreeRoutesToInfo() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        viewModel.postMergeAftermathHandler = { _, _ in
            .skippedDirtyTree(branch: "main", modifiedCount: 2, untrackedCount: 1)
        }

        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )

        try await waitForCondition {
            viewModel.pullRequestMergeInfoMessage?.contains("not synced") == true
        }
        #expect(viewModel.pullRequestMergeInfoMessage?.contains("uncommitted") == true ||
                viewModel.pullRequestMergeInfoMessage?.contains("modified") == true)
        #expect(viewModel.pullRequestMergeErrorMessage == nil)
    }

    @Test("aftermath thrown error routes to error banner")
    func aftermathThrownErrorRoutesToErrorBanner() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        viewModel.postMergeAftermathHandler = { _, _ in
            throw GitMergeAftermathError.fetchFailed(stderr: "fatal: network", exitCode: 128)
        }

        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )

        try await waitForCondition {
            viewModel.pullRequestMergeErrorMessage != nil
        }
        let errorMessage = viewModel.pullRequestMergeErrorMessage ?? ""
        #expect(errorMessage.contains("network") || errorMessage.lowercased().contains("fetch"))
    }

    // MARK: - End-to-end requestMergePullRequest with aftermath

    @Test("requestMergePullRequest success path invokes aftermath with merged baseRefName")
    func requestMergePullRequestInvokesAftermath() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        viewModel.activePullRequestNumber = 42
        viewModel.mergePullRequestHandler = { _ in
            Self.mergedPullRequest(number: 42, baseRefName: "develop")
        }
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }

        let receivedBaseBranch = Box<String?>(nil)
        viewModel.postMergeAftermathHandler = { _, baseBranch in
            receivedBaseBranch.value = baseBranch
            return .synced(branch: baseBranch, ahead: 0, behind: 1)
        }

        viewModel.requestMergePullRequest(method: .squash, deleteBranch: true)

        try await waitForCondition {
            viewModel.pullRequestMergeInfoMessage?.contains("synced") == true
        }
        #expect(receivedBaseBranch.value == "develop")
        #expect(viewModel.pullRequestMergeInfoMessage?.contains("`develop`") == true)
    }

    @Test("aftermath uses loaded review working directory after tab switch")
    func aftermathUsesLoadedReviewWorkingDirectoryAfterTabSwitch() async throws {
        let loadedDirectory = URL(fileURLWithPath: "/tmp/review-aftermath-loaded", isDirectory: true)
        let laterDirectory = URL(fileURLWithPath: "/tmp/review-aftermath-later", isDirectory: true)
        let activeDirectory = Box<URL?>(loadedDirectory)
        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in [] }
        )
        viewModel.activeTabCwdProvider = { activeDirectory.value }

        viewModel.refreshDiffs()
        try await waitForCondition {
            viewModel.activeWorkingDirectory == loadedDirectory &&
            viewModel.isLoading == false
        }

        activeDirectory.value = laterDirectory
        let receivedDirectory = Box<URL?>(nil)
        viewModel.postMergeAftermathHandler = { directory, baseBranch in
            receivedDirectory.value = directory
            return .synced(branch: baseBranch, ahead: 0, behind: 1)
        }

        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feature/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )

        try await waitForCondition { receivedDirectory.value != nil }
        #expect(receivedDirectory.value == loadedDirectory)
        #expect(receivedDirectory.value != laterDirectory)
    }

    @Test("requestMergePullRequest without aftermath wired still surfaces merge banner")
    func requestMergePullRequestNoAftermathStillBanner() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        viewModel.activePullRequestNumber = 42
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }
        // postMergeAftermathHandler intentionally left nil

        viewModel.requestMergePullRequest(method: .squash, deleteBranch: false)

        try await waitForCondition {
            viewModel.pullRequestMergeInfoMessage?.contains("Merged PR") == true
        }
        // The banner shows the merge head only — no aftermath append.
        let message = viewModel.pullRequestMergeInfoMessage ?? ""
        #expect(message == "Merged PR #42 via Squash & Merge.")
    }

    @Test("cleanup close uses tab captured before alert resolves")
    func cleanupCloseUsesCapturedTabID() async throws {
        let viewModel = makeViewModel()
        viewModel.activeTabCwdProvider = { Self.workingDirectory }
        let mergeTabID = TabID()
        let laterTabID = TabID()
        let activeTabID = Box<TabID?>(mergeTabID)
        viewModel.activeTabIDProvider = { activeTabID.value }
        viewModel.postMergeAftermathHandler = { _, _ in
            .fetchedOnly(currentBranch: "feature/test", baseBranch: "main")
        }
        viewModel.postMergeCleanupAlertHandler = { _ in
            activeTabID.value = laterTabID
            return .closeWorktree
        }

        let closedTabID = Box<TabID?>(nil)
        viewModel.closeWorktreeTabHandler = { tabID in
            closedTabID.value = tabID
            return true
        }

        viewModel.runPostMergeAftermathIfWired(
            baseBranch: "main",
            headRefName: "feature/test",
            deleteBranchUsed: true,
            mergedNumber: 42,
            method: .squash
        )

        try await waitForCondition {
            closedTabID.value != nil &&
            viewModel.pullRequestMergeInfoMessage?.contains("closed") == true
        }
        #expect(closedTabID.value == mergeTabID)
        #expect(closedTabID.value != laterTabID)
    }

    // MARK: - Helpers

    private func makeViewModel() -> CodeReviewPanelViewModel {
        CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil
        )
    }
}

// MARK: - Test helpers

/// Local mirror of the harness used by the v0.1.86 PR merge suite.
/// Kept private so each suite remains independent and the helpers do
/// not leak across files.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@MainActor
private func waitForCondition(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while condition() == false {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Timed out waiting for asynchronous aftermath state")
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}
