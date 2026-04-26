// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneViewModelPostMergeAftermathSwiftTestingTests.swift
// Coverage for the v0.1.87 post-merge auto-pull integration on the
// GitHub pane surface. Mirrors the CodeReview suite structure so a
// regression on either surface surfaces with identical assertions.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("GitHubPaneViewModel post-merge aftermath")
struct GitHubPaneViewModelPostMergeAftermathSwiftTestingTests {

    // MARK: - Fixtures

    private static func mergedPullRequest(
        number: Int = 42,
        baseRefName: String = "main"
    ) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: "Test PR",
            state: .merged,
            author: GitHubUser(login: "octocat"),
            headRefName: "feature/test",
            baseRefName: baseRefName,
            url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Subset of the pane's full discovery runner: just enough to
    /// populate `pullRequestsWorkingDirectory` so `requestMergePullRequest`
    /// passes its working-directory guard.
    private static func loadedRunner(pullRequestNumber: Int = 42) -> GitHubService.Runner {
        { _, args, _ in
            if args.contains("auth") && args.contains("status") {
                return GitHubCLIResult(
                    stdout: "",
                    stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                    terminationStatus: 0
                )
            }
            if args.contains("repo") && args.contains("view") {
                return GitHubCLIResult(
                    stdout: #"""
                    {
                      "name": "repo",
                      "nameWithOwner": "owner/repo",
                      "owner": {"login": "owner"},
                      "url": "https://github.com/owner/repo"
                    }
                    """#,
                    stderr: "",
                    terminationStatus: 0
                )
            }
            if args.contains("pr") && args.contains("checks") {
                return GitHubCLIResult(stdout: "[]", stderr: "", terminationStatus: 0)
            }
            if args.contains("pr") && args.contains("list") {
                return GitHubCLIResult(
                    stdout: #"""
                    [
                      {"number": \#(pullRequestNumber), "title": "Test PR", "state": "OPEN", "author": {"login": "octocat"}, "headRefName": "feature/test", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/owner/repo/pull/\#(pullRequestNumber)", "updatedAt": "2026-04-23T15:47:21Z"}
                    ]
                    """#,
                    stderr: "",
                    terminationStatus: 0
                )
            }
            if args.contains("issue") && args.contains("list") {
                return GitHubCLIResult(stdout: "[]", stderr: "", terminationStatus: 0)
            }
            return GitHubCLIResult(stdout: "", stderr: "unexpected: \(args.joined(separator: " "))", terminationStatus: 1)
        }
    }

    // MARK: - mergeBannerMessage helper

    @Test("mergeBannerMessage without outcome returns merge head only")
    func bannerNoOutcome() {
        let message = GitHubPaneViewModel.mergeBannerMessage(
            mergedNumber: 42,
            method: .squash,
            outcome: nil
        )
        #expect(message == "Merged PR #42 via Squash & Merge.")
    }

    @Test("mergeBannerMessage appends synced outcome")
    func bannerWithSynced() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 5)
        let message = GitHubPaneViewModel.mergeBannerMessage(
            mergedNumber: 99,
            method: .merge,
            outcome: outcome
        )
        #expect(message.contains("#99"))
        #expect(message.contains("Merge Commit"))
        #expect(message.contains("5 commits pulled"))
    }

    // MARK: - userFacingAftermathErrorMessage

    @Test("typed aftermath error maps via errorDescription")
    func typedAftermathError() {
        let error = GitMergeAftermathError.pullFailed(stderr: "boom", exitCode: 1)
        let message = GitHubPaneViewModel.userFacingAftermathErrorMessage(for: error)
        #expect(message.contains("boom") || message.lowercased().contains("pull"))
    }

    @Test("non-typed error falls back to localizedDescription")
    func untypedAftermathError() {
        struct CustomError: LocalizedError {
            var errorDescription: String? { "weird error" }
        }
        let message = GitHubPaneViewModel.userFacingAftermathErrorMessage(for: CustomError())
        #expect(message == "weird error")
    }

    // MARK: - runPostMergeAftermathIfWired guards

    @Test("runPostMergeAftermathIfWired no-op when handler nil")
    func aftermathNoOpHandlerNil() async throws {
        let viewModel = makeViewModel()
        let banner = viewModel.lastMergeInfoMessage
        viewModel.runPostMergeAftermathIfWired(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.lastMergeInfoMessage == banner)
    }

    @Test("runPostMergeAftermathIfWired no-op when baseBranch is whitespace")
    func aftermathNoOpEmptyBranch() async throws {
        let viewModel = makeViewModel()
        let calls = Box<Int>(0)
        viewModel.postMergeAftermathHandler = { _, _ in
            calls.value += 1
            return .skippedNotInRepo
        }
        viewModel.runPostMergeAftermathIfWired(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            baseBranch: "   ",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(calls.value == 0)
    }

    // MARK: - Aftermath success / failure routing

    @Test("aftermath success folds outcome into lastMergeInfoMessage")
    func aftermathSuccessFolds() async throws {
        let viewModel = makeViewModel()
        let received = Box<(URL, String)?>(nil)
        viewModel.postMergeAftermathHandler = { directory, baseBranch in
            received.value = (directory, baseBranch)
            return .synced(branch: baseBranch, ahead: 0, behind: 4)
        }
        let workingDir = URL(fileURLWithPath: "/tmp/sample-repo", isDirectory: true)

        viewModel.runPostMergeAftermathIfWired(
            workingDirectory: workingDir,
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 99,
            method: .squash
        )

        try await waitForCondition {
            viewModel.lastMergeInfoMessage?.contains("synced") == true
        }
        #expect(received.value?.0 == workingDir)
        #expect(received.value?.1 == "main")
        let info = viewModel.lastMergeInfoMessage ?? ""
        #expect(info.contains("Merged PR #99"))
        #expect(info.contains("4 commits pulled"))
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test("aftermath baseBranch trimmed before invoking handler")
    func aftermathTrimsBaseBranch() async throws {
        let viewModel = makeViewModel()
        let received = Box<String?>(nil)
        viewModel.postMergeAftermathHandler = { _, baseBranch in
            received.value = baseBranch
            return .synced(branch: "main", ahead: 0, behind: 0)
        }
        viewModel.runPostMergeAftermathIfWired(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            baseBranch: "  main  ",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await waitForCondition { received.value != nil }
        #expect(received.value == "main")
    }

    @Test("aftermath benign skip routes to info, never error")
    func aftermathDirtyTreeRoutesToInfo() async throws {
        let viewModel = makeViewModel()
        viewModel.postMergeAftermathHandler = { _, _ in
            .skippedDirtyTree(branch: "main", modifiedCount: 1, untrackedCount: 0)
        }
        viewModel.runPostMergeAftermathIfWired(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await waitForCondition {
            viewModel.lastMergeInfoMessage?.contains("not synced") == true
        }
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test("aftermath thrown error routes to lastErrorMessage")
    func aftermathThrownError() async throws {
        let viewModel = makeViewModel()
        viewModel.postMergeAftermathHandler = { _, _ in
            throw GitMergeAftermathError.fetchFailed(stderr: "fatal: network", exitCode: 128)
        }
        viewModel.runPostMergeAftermathIfWired(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            baseBranch: "main",
            headRefName: "feat/test",
            deleteBranchUsed: false,
            mergedNumber: 42,
            method: .squash
        )
        try await waitForCondition { viewModel.lastErrorMessage != nil }
        #expect(viewModel.lastErrorMessage?.contains("network") == true ||
                viewModel.lastErrorMessage?.lowercased().contains("fetch") == true)
    }

    // MARK: - End-to-end: requestMergePullRequest invokes aftermath

    @Test("requestMergePullRequest success path invokes aftermath with merged baseRefName")
    func requestMergePullRequestInvokesAftermathEndToEnd() async throws {
        let workingDirectory = URL(fileURLWithPath: "/tmp/github-pane-aftermath", isDirectory: true)
        let viewModel = try await makeLoadedViewModel(
            workingDirectory: workingDirectory,
            pullRequestNumber: 42
        )
        viewModel.mergePullRequestHandler = { _, _ in
            Self.mergedPullRequest(number: 42, baseRefName: "develop")
        }

        let received = Box<(URL, String)?>(nil)
        viewModel.postMergeAftermathHandler = { directory, baseBranch in
            received.value = (directory, baseBranch)
            return .synced(branch: baseBranch, ahead: 0, behind: 1)
        }

        viewModel.requestMergePullRequest(
            number: 42,
            method: .squash,
            deleteBranch: true
        )

        try await waitForCondition {
            received.value != nil &&
            viewModel.lastMergeInfoMessage?.contains("synced") == true
        }
        #expect(received.value?.0 == workingDirectory)
        #expect(received.value?.1 == "develop")
        let banner = viewModel.lastMergeInfoMessage ?? ""
        #expect(banner.contains("`develop`"))
    }

    @Test("requestMergePullRequest without aftermath wired still surfaces plain banner")
    func requestMergePullRequestNoAftermathPlainBanner() async throws {
        let viewModel = try await makeLoadedViewModel()
        viewModel.mergePullRequestHandler = { _, _ in Self.mergedPullRequest() }
        // postMergeAftermathHandler intentionally left nil

        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: false)

        try await waitForCondition {
            viewModel.lastMergeInfoMessage?.contains("Merged PR") == true
        }
        let banner = viewModel.lastMergeInfoMessage ?? ""
        #expect(banner == "Merged PR #42 via Squash & Merge.")
    }

    @Test("cleanup close uses tab captured with loaded pull request rows")
    func cleanupCloseUsesLoadedTabID() async throws {
        let loadedTabID = TabID()
        let otherTabID = TabID()
        let visibleTabID = Box<TabID?>(loadedTabID)
        let viewModel = try await makeLoadedViewModel(tabIDProvider: { visibleTabID.value })
        viewModel.mergePullRequestHandler = { _, _ in Self.mergedPullRequest() }
        viewModel.postMergeAftermathHandler = { _, _ in
            .fetchedOnly(currentBranch: "feature/test", baseBranch: "main")
        }
        viewModel.postMergeCleanupAlertHandler = { _ in
            visibleTabID.value = otherTabID
            return .closeWorktree
        }

        let closedTabID = Box<TabID?>(nil)
        viewModel.closeWorktreeTabHandler = { tabID in
            closedTabID.value = tabID
            return true
        }

        viewModel.requestMergePullRequest(
            number: 42,
            method: .squash,
            deleteBranch: true
        )

        try await waitForCondition {
            closedTabID.value != nil &&
            viewModel.lastMergeInfoMessage?.contains("closed") == true
        }
        #expect(closedTabID.value == loadedTabID)
        #expect(closedTabID.value != otherTabID)
    }

    // MARK: - Helpers

    private func makeViewModel() -> GitHubPaneViewModel {
        let service = GitHubService(runner: { _, _, _ in
            GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0)
        })
        return GitHubPaneViewModel(service: service)
    }

    private func makeLoadedViewModel(
        workingDirectory: URL = URL(fileURLWithPath: "/tmp/github-pane-aftermath", isDirectory: true),
        pullRequestNumber: Int = 42,
        tabIDProvider: (() -> TabID?)? = nil
    ) async throws -> GitHubPaneViewModel {
        let service = GitHubService(runner: Self.loadedRunner(pullRequestNumber: pullRequestNumber))
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { workingDirectory }
        viewModel.tabIDProvider = tabIDProvider
        viewModel.refresh()
        try await waitForCondition {
            viewModel.pullRequests.contains(where: { $0.number == pullRequestNumber })
                && viewModel.isLoading == false
        }
        return viewModel
    }
}

// MARK: - Test helpers

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
            Issue.record("Timed out waiting for asynchronous pane aftermath state")
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}
