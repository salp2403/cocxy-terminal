// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneViewModelMergeSwiftTestingTests.swift - Behaviour tests
// for the v0.1.86 PR row context-menu merge flow exposed by
// GitHubPaneViewModel.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("GitHubPaneViewModel.merge")
struct GitHubPaneViewModelMergeSwiftTestingTests {

    // MARK: - Fixtures

    /// Builds an open PR fixture used as the row the user right-clicks.
    private static func openPullRequest(
        number: Int = 42,
        isDraft: Bool = false
    ) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: "Test PR",
            state: .open,
            author: GitHubUser(login: "octocat"),
            headRefName: "feature/test",
            baseRefName: "main",
            isDraft: isDraft,
            url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

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

    /// Tiny stub runner so we can construct a real GitHubService
    /// without touching the network. The merge tests exercise the
    /// view model's behaviour, not the service.
    private static let neverInvokedRunner: GitHubService.Runner = { _, _, _ in
        return GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0)
    }

    // MARK: - canOfferMerge

    @Test("canOfferMerge is true for an open PR with a wired handler")
    func canOfferMergeIsTrueForOpenPRWithHandler() {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        #expect(viewModel.canOfferMerge(for: Self.openPullRequest()))
    }

    @Test("canOfferMerge is false for a draft PR")
    func canOfferMergeIsFalseForDraftPR() {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        #expect(!viewModel.canOfferMerge(for: Self.openPullRequest(isDraft: true)))
    }

    @Test("canOfferMerge is false for a merged PR")
    func canOfferMergeIsFalseForMergedPR() {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        #expect(!viewModel.canOfferMerge(for: Self.mergedPullRequest()))
    }

    @Test("canOfferMerge is false without a handler")
    func canOfferMergeIsFalseWithoutHandler() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canOfferMerge(for: Self.openPullRequest()))
    }

    @Test("canOfferMerge respects [github].merge-enabled flag")
    func canOfferMergeRespectsFeatureFlag() {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        viewModel.configProvider = {
            GitHubConfig(mergeEnabled: false)
        }
        #expect(!viewModel.canOfferMerge(for: Self.openPullRequest()))
    }

    // MARK: - requestMergePullRequest success

    @Test("requestMergePullRequest sets merge info banner on success")
    func requestMergePullRequestSetsMergeInfoBannerOnSuccess() async throws {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest(number: 42) }

        viewModel.requestMergePullRequest(
            number: 42,
            method: .squash,
            deleteBranch: true
        )

        try await waitForGitHubPaneCondition {
            viewModel.lastMergeInfoMessage != nil
        }
        let info = viewModel.lastMergeInfoMessage ?? ""
        #expect(info.contains("#42"))
        #expect(info.contains("Squash"))
        #expect(viewModel.pullRequestsBeingMerged.contains(42) == false)
    }

    @Test("requestMergePullRequest forwards parameters to the handler")
    func requestMergePullRequestForwardsParameters() async throws {
        let viewModel = makeViewModel()
        let captured = Box<GitHubMergeRequest?>(nil)
        viewModel.mergePullRequestHandler = { request in
            captured.value = request
            return Self.mergedPullRequest(number: request.pullRequestNumber)
        }

        viewModel.requestMergePullRequest(
            number: 7,
            method: .rebase,
            deleteBranch: false,
            subject: "Custom",
            body: "Body"
        )

        try await waitForGitHubPaneCondition { captured.value != nil }
        let request = try #require(captured.value)
        #expect(request.pullRequestNumber == 7)
        #expect(request.method == .rebase)
        #expect(request.deleteBranch == false)
        #expect(request.subject == "Custom")
        #expect(request.body == "Body")
    }

    @Test("requestMergePullRequest tracks isMerging during flight")
    func requestMergePullRequestTracksIsMerging() async throws {
        let viewModel = makeViewModel()
        let started = Box<Bool>(false)
        let release = Box<Bool>(false)
        viewModel.mergePullRequestHandler = { _ in
            started.value = true
            // Spin until the test releases — keeps the merge "in flight"
            // long enough for the assertion below to read isMerging.
            while !release.value {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            return Self.mergedPullRequest()
        }

        viewModel.requestMergePullRequest(
            number: 42,
            method: .squash,
            deleteBranch: true
        )

        try await waitForGitHubPaneCondition { started.value }
        #expect(viewModel.isMerging(42))
        #expect(viewModel.pullRequestsBeingMerged.contains(42))

        release.value = true
        try await waitForGitHubPaneCondition { !viewModel.isMerging(42) }
    }

    @Test("requestMergePullRequest deduplicates concurrent merges of the same PR")
    func requestMergePullRequestDeduplicatesConcurrentMerges() async throws {
        let viewModel = makeViewModel()
        let invocationCount = Box<Int>(0)
        let release = Box<Bool>(false)
        viewModel.mergePullRequestHandler = { _ in
            invocationCount.value += 1
            while !release.value {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            return Self.mergedPullRequest()
        }

        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: true)
        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: true)
        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: true)

        try await waitForGitHubPaneCondition { invocationCount.value > 0 }
        // First call wins; second/third are deduped while #42 lives in
        // the in-flight set.
        #expect(invocationCount.value == 1)

        release.value = true
        try await waitForGitHubPaneCondition { !viewModel.isMerging(42) }
    }

    // MARK: - requestMergePullRequest errors

    @Test("requestMergePullRequest sets error banner on merge conflict")
    func requestMergePullRequestSetsErrorBannerOnConflict() async throws {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in
            throw GitHubMergeError.mergeConflict
        }

        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: true)

        try await waitForGitHubPaneCondition {
            viewModel.lastErrorMessage != nil
        }
        let message = viewModel.lastErrorMessage ?? ""
        #expect(message.lowercased().contains("conflict"))
        #expect(viewModel.pullRequestsBeingMerged.contains(42) == false)
    }

    @Test("requestMergePullRequest with merge feature disabled sets error banner immediately")
    func requestMergePullRequestRespectsFeatureFlag() {
        let viewModel = makeViewModel()
        viewModel.mergePullRequestHandler = { _ in Self.mergedPullRequest() }
        viewModel.configProvider = { GitHubConfig(mergeEnabled: false) }

        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: true)

        let message = viewModel.lastErrorMessage ?? ""
        #expect(message.contains("merge-enabled") || message.lowercased().contains("disabled"))
        #expect(viewModel.pullRequestsBeingMerged.isEmpty)
    }

    @Test("requestMergePullRequest without handler sets actionable error")
    func requestMergePullRequestWithoutHandlerSetsError() {
        let viewModel = makeViewModel()
        viewModel.requestMergePullRequest(number: 42, method: .squash, deleteBranch: true)
        let message = viewModel.lastErrorMessage ?? ""
        #expect(message.lowercased().contains("github") || message.lowercased().contains("not ready"))
    }

    // MARK: - userFacingMergeErrorMessage

    @Test("userFacingMergeErrorMessage maps GitHubMergeError")
    func userFacingMergeErrorMessageMapsGitHubMergeError() {
        let message = GitHubPaneViewModel.userFacingMergeErrorMessage(for: GitHubMergeError.mergeConflict)
        #expect(message.lowercased().contains("conflict"))
    }

    @Test("userFacingMergeErrorMessage routes GitHubCLIError through banner mapper")
    func userFacingMergeErrorMessageRoutesGitHubCLIError() {
        let message = GitHubPaneViewModel.userFacingMergeErrorMessage(for: GitHubCLIError.notInstalled)
        #expect(message.lowercased().contains("install"))
    }

    @Test("userFacingMergeErrorMessage falls back to localizedDescription for foreign errors")
    func userFacingMergeErrorMessageFallsBackToLocalizedDescription() {
        let error = NSError(
            domain: "test",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Custom message"]
        )
        let message = GitHubPaneViewModel.userFacingMergeErrorMessage(for: error)
        #expect(message == "Custom message")
    }

    // MARK: - Helpers

    private func makeViewModel() -> GitHubPaneViewModel {
        let service = GitHubService(runner: Self.neverInvokedRunner)
        return GitHubPaneViewModel(service: service)
    }
}

// MARK: - Test helpers

/// Mutable reference box so handler closures can communicate values
/// back to the test body without `inout` gymnastics.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Polls a condition with a short interval up to a generous deadline.
/// Mirrors `waitForReviewCondition` from the CodeReview integration
/// suite so the two flows can be audited side-by-side.
@MainActor
private func waitForGitHubPaneCondition(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while condition() == false {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Timed out waiting for asynchronous pane state update")
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}
