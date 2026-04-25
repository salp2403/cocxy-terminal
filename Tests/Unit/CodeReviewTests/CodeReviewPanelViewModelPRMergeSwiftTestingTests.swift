// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModelPRMergeSwiftTestingTests.swift - Behaviour
// tests for the v0.1.86 in-panel PR merge integration owned by the
// `+PRMerge.swift` extension.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("CodeReviewPanelViewModel PR merge")
struct CodeReviewPanelViewModelPRMergeSwiftTestingTests {

    // MARK: - Fixtures

    /// Builds a clean `GitHubMergeability` snapshot we can use as a
    /// canned response from the injected handler.
    private static func cleanMergeability(number: Int = 42) -> GitHubMergeability {
        GitHubMergeability(
            pullRequestNumber: number,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: true
        )
    }

    /// Builds a hydrated PR fixture used as the post-merge return value.
    private static func mergedPullRequest(number: Int = 42) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: "Test PR",
            state: .merged,
            author: GitHubUser(login: "octocat"),
            headRefName: "feature/test",
            baseRefName: "main",
            url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - attachActivePullRequestNumber

    @Test("attachActivePullRequestNumber sets number and triggers mergeability refresh")
    func attachActivePullRequestNumberTriggersMergeabilityFetch() async throws {
        let viewModel = makeViewModel()
        let receivedNumber = Box<Int?>(nil)
        viewModel.pullRequestMergeabilityHandler = { number in
            receivedNumber.value = number
            return Self.cleanMergeability(number: number)
        }

        viewModel.attachActivePullRequestNumber(42)

        #expect(viewModel.activePullRequestNumber == 42)
        try await waitForReviewCondition {
            viewModel.activePullRequestMergeability != nil
        }
        #expect(receivedNumber.value == 42)
        #expect(viewModel.activePullRequestMergeability?.canMerge == true)
    }

    @Test("attaching the same number twice keeps the stored value stable")
    func attachingSameNumberTwiceIsIdempotent() {
        let viewModel = makeViewModel()
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }
        viewModel.attachActivePullRequestNumber(42)
        viewModel.activePullRequestMergeability = Self.cleanMergeability()

        viewModel.attachActivePullRequestNumber(42)

        #expect(viewModel.activePullRequestNumber == 42)
        // Re-attaching the same number does not blank the cached
        // snapshot; only the in-flight refresh updates it.
        #expect(viewModel.activePullRequestMergeability != nil)
    }

    @Test("attaching a different number resets transient state")
    func attachingDifferentNumberResetsTransientState() {
        let viewModel = makeViewModel()
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }
        viewModel.attachActivePullRequestNumber(42)
        viewModel.activePullRequestMergeability = Self.cleanMergeability(number: 42)
        viewModel.pullRequestMergeErrorMessage = "previous"

        viewModel.attachActivePullRequestNumber(99)

        #expect(viewModel.activePullRequestNumber == 99)
        #expect(viewModel.activePullRequestMergeability == nil)
        #expect(viewModel.pullRequestMergeErrorMessage == nil)
    }

    // MARK: - clearActivePullRequest

    @Test("clearActivePullRequest wipes every merge field")
    func clearActivePullRequestWipesEveryField() {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.activePullRequestMergeability = Self.cleanMergeability()
        viewModel.pullRequestMergeErrorMessage = "boom"
        viewModel.pullRequestMergeInfoMessage = "merged"
        viewModel.isMergingPullRequest = true

        viewModel.clearActivePullRequest()

        #expect(viewModel.activePullRequestNumber == nil)
        #expect(viewModel.activePullRequestMergeability == nil)
        #expect(viewModel.pullRequestMergeErrorMessage == nil)
        #expect(viewModel.pullRequestMergeInfoMessage == nil)
        #expect(viewModel.isMergingPullRequest == false)
    }

    // MARK: - requestMergePullRequest guards

    @Test("requestMergePullRequest without active PR sets actionable error")
    func requestMergePullRequestWithoutActivePRSetsError() {
        let viewModel = makeViewModel()
        viewModel.requestMergePullRequest(method: .squash, deleteBranch: true)
        #expect(viewModel.pullRequestMergeErrorMessage?.contains("No pull request") == true)
        #expect(viewModel.isMergingPullRequest == false)
    }

    @Test("requestMergePullRequest without handler sets actionable error")
    func requestMergePullRequestWithoutHandlerSetsError() {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.requestMergePullRequest(method: .squash, deleteBranch: true)
        let message = viewModel.pullRequestMergeErrorMessage ?? ""
        #expect(message.contains("GitHub pane") || message.contains("not ready"))
        #expect(viewModel.isMergingPullRequest == false)
    }

    // MARK: - requestMergePullRequest success and error

    @Test("requestMergePullRequest sets merge info message on success")
    func requestMergePullRequestSetsInfoMessageOnSuccess() async throws {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }

        viewModel.requestMergePullRequest(method: .squash, deleteBranch: true)

        try await waitForReviewCondition {
            viewModel.pullRequestMergeInfoMessage != nil
        }
        let info = viewModel.pullRequestMergeInfoMessage ?? ""
        #expect(info.contains("#42"))
        #expect(info.contains("Squash"))
        #expect(viewModel.isMergingPullRequest == false)
        #expect(viewModel.pullRequestMergeErrorMessage == nil)
    }

    @Test("requestMergePullRequest classifies merge conflict and surfaces actionable copy")
    func requestMergePullRequestClassifiesMergeConflict() async throws {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.mergePullRequestHandler = { _ in
            throw GitHubMergeError.mergeConflict
        }
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }

        viewModel.requestMergePullRequest(method: .squash, deleteBranch: false)

        try await waitForReviewCondition {
            viewModel.pullRequestMergeErrorMessage != nil
        }
        let message = viewModel.pullRequestMergeErrorMessage ?? ""
        #expect(message.lowercased().contains("conflict"))
        #expect(viewModel.isMergingPullRequest == false)
    }

    @Test("requestMergePullRequest forwards method, deleteBranch, subject and body to handler")
    func requestMergePullRequestForwardsRequestParameters() async throws {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        let captured = Box<GitHubMergeRequest?>(nil)
        viewModel.mergePullRequestHandler = { request in
            captured.value = request
            return Self.mergedPullRequest()
        }
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability() }

        viewModel.requestMergePullRequest(
            method: .rebase,
            deleteBranch: false,
            subject: "Custom subject",
            body: "Custom body"
        )

        try await waitForReviewCondition { captured.value != nil }
        let request = try #require(captured.value)
        #expect(request.pullRequestNumber == 42)
        #expect(request.method == .rebase)
        #expect(request.deleteBranch == false)
        #expect(request.subject == "Custom subject")
        #expect(request.body == "Custom body")
    }

    // MARK: - refreshActivePullRequestState

    @Test("refreshActivePullRequestState detects PR from current branch")
    func refreshActivePullRequestStateDetectsPRFromBranch() async throws {
        let viewModel = makeViewModel()
        let captured = Box<String?>(nil)
        viewModel.activeBranchProvider = { "feature/in-flight" }
        viewModel.activePullRequestDetectionHandler = { branch in
            captured.value = branch
            return 99
        }
        viewModel.pullRequestMergeabilityHandler = { _ in Self.cleanMergeability(number: 99) }

        viewModel.refreshActivePullRequestState()

        try await waitForReviewCondition {
            viewModel.activePullRequestNumber == 99
        }
        #expect(captured.value == "feature/in-flight")
        try await waitForReviewCondition {
            viewModel.activePullRequestMergeability != nil
        }
    }

    @Test("refreshActivePullRequestState clears state when branch has no PR")
    func refreshActivePullRequestStateClearsStateWhenNoPR() async throws {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.activePullRequestMergeability = Self.cleanMergeability()
        viewModel.activeBranchProvider = { "feature/no-pr" }
        viewModel.activePullRequestDetectionHandler = { _ in nil }

        viewModel.refreshActivePullRequestState()

        try await waitForReviewCondition {
            viewModel.activePullRequestNumber == nil
        }
        #expect(viewModel.activePullRequestMergeability == nil)
    }

    @Test("refreshActivePullRequestState is a no-op without a detection handler")
    func refreshActivePullRequestStateIsNoOpWithoutHandler() {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.activeBranchProvider = { "feature/has-pr" }
        // No detection handler wired.
        viewModel.refreshActivePullRequestState()
        // State preserved; nothing was attempted.
        #expect(viewModel.activePullRequestNumber == 42)
    }

    @Test("refreshActivePullRequestState clears state when branch is unavailable")
    func refreshActivePullRequestStateClearsStateWithoutBranch() {
        let viewModel = makeViewModel()
        viewModel.activePullRequestNumber = 42
        viewModel.activePullRequestDetectionHandler = { _ in 99 }
        // No branch provider, no gitStatus → cannot resolve branch.
        viewModel.refreshActivePullRequestState()
        #expect(viewModel.activePullRequestNumber == nil)
    }

    // MARK: - userFacingMergeErrorMessage

    // MARK: - Regression: Create PR captures number

    @Test("requestCreatePullRequest captures the PR number on success")
    func requestCreatePullRequestCapturesPullRequestNumberOnSuccess() async throws {
        let viewModel = makeViewModel()
        // The createPullRequestHandler returns the PR URL the existing
        // contract emits; the side-effect added in v0.1.86 should pull
        // the number out of that URL and attach it for merge use.
        viewModel.createPullRequestHandler = { _, _, _, _ in
            URL(string: "https://github.com/owner/repo/pull/123")!
        }
        let mergeabilityCalled = Box<Int?>(nil)
        viewModel.pullRequestMergeabilityHandler = { number in
            mergeabilityCalled.value = number
            return Self.cleanMergeability(number: number)
        }
        viewModel.commitMessageDraft = "Add feature X"

        viewModel.requestCreatePullRequest()

        try await waitForReviewCondition {
            viewModel.activePullRequestNumber == 123
        }
        // The mergeability handler is also invoked so the chip lights
        // up immediately after the PR is created.
        try await waitForReviewCondition {
            mergeabilityCalled.value == 123
        }
        #expect(viewModel.activePullRequestNumber == 123)
        #expect(viewModel.activePullRequestMergeability != nil)
    }

    @Test("requestCreatePullRequest failure does not capture a PR number")
    func requestCreatePullRequestFailureDoesNotCapturePullRequestNumber() async throws {
        let viewModel = makeViewModel()
        struct StubError: Error {}
        viewModel.createPullRequestHandler = { _, _, _, _ in
            throw StubError()
        }
        viewModel.commitMessageDraft = "Add feature X"

        viewModel.requestCreatePullRequest()

        try await waitForReviewCondition {
            viewModel.lastErrorMessage != nil
        }
        #expect(viewModel.activePullRequestNumber == nil)
    }

    // MARK: - userFacingMergeErrorMessage

    @Test("userFacingMergeErrorMessage maps GitHubMergeError cases")
    func userFacingMergeErrorMessageMapsTypedErrors() {
        let conflict = CodeReviewPanelViewModel.userFacingMergeErrorMessage(
            for: GitHubMergeError.mergeConflict
        )
        #expect(conflict.lowercased().contains("conflict"))

        let unknown = CodeReviewPanelViewModel.userFacingMergeErrorMessage(
            for: NSError(
                domain: "test",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Custom error"]
            )
        )
        #expect(unknown == "Custom error")

        let empty = CodeReviewPanelViewModel.userFacingMergeErrorMessage(
            for: NSError(
                domain: "test",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: ""]
            )
        )
        #expect(!empty.isEmpty)
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

/// Mutable reference box so closures captured by the view model can
/// communicate values back to the test body without `inout` gymnastics.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Mirrors `waitForReviewCondition` from the integration suite. Polls
/// the condition with a short interval up to a generous deadline so
/// async tasks driven by `Task { … }` have time to deliver their side
/// effects without us hard-coding sleep durations.
@MainActor
private func waitForReviewCondition(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while condition() == false {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Timed out waiting for asynchronous review state update")
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}
