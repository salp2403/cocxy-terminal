// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CreatePullRequestIntegrationSwiftTestingTests.swift - Verifies the
// Code Review `Create PR` flow (Fase 10). The tests stub the handler
// closure injected by the MainWindowController so the view model's
// orchestration can be exercised without any AppKit harness.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("CodeReview Create PR", .serialized)
@MainActor
struct CreatePullRequestIntegrationSwiftTestingTests {

    /// Real tracker impl in an isolated tempdir. The Create PR flow
    /// never pulls a snapshot so an empty store is fine; we use the
    /// real type to avoid mirroring every protocol method in a stub
    /// that would immediately drift out of sync.
    private func makeViewModel() -> CodeReviewPanelViewModel {
        return CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            gitWorkflow: CodeReviewGitWorkflowService()
        )
    }

    // MARK: - Short flush for the background gitActionTask

    /// Waits for the Task scheduled inside `requestCreatePullRequest`
    /// to land its final MainActor update. Ten 20ms ticks is enough
    /// for the typical happy path; tests that need more simply
    /// extend the cap.
    private func flush(maxTicks: Int = 50) async {
        for _ in 0..<maxTicks {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Tests

    @Test("requestCreatePullRequest surfaces an error when no handler is wired")
    func requestCreatePR_requiresHandler() async throws {
        let vm = makeViewModel()
        vm.commitMessageDraft = "fix: something"
        vm.requestCreatePullRequest()
        #expect(vm.lastErrorMessage?.contains("not ready") == true)
    }

    @Test("requestCreatePullRequest rejects empty commit + no title")
    func requestCreatePR_rejectsEmptyTitle() async throws {
        let vm = makeViewModel()
        vm.createPullRequestHandler = { _, _, _, _ in
            URL(string: "https://github.com/u/r/pull/1")!
        }
        vm.commitMessageDraft = ""
        vm.requestCreatePullRequest(title: "   ")
        #expect(vm.lastErrorMessage?.contains("commit message") == true)
    }

    @Test("requestCreatePullRequest calls handler with commit first line as title")
    func requestCreatePR_usesCommitFirstLineAsTitle() async throws {
        let vm = makeViewModel()
        let captured = LockedBox<(String, String?, String?, Bool)?>(nil)
        vm.createPullRequestHandler = { title, body, baseBranch, draft in
            captured.withValue { $0 = (title, body, baseBranch, draft) }
            return URL(string: "https://github.com/u/r/pull/42")!
        }
        vm.commitMessageDraft = "feat(review): add Create PR button\n\nBody line 1\nBody line 2"
        vm.requestCreatePullRequest()
        await flush()

        let snapshot = captured.withValue { $0 }
        try #require(snapshot != nil)
        guard let snapshot else { return }
        #expect(snapshot.0 == "feat(review): add Create PR button")
        #expect(snapshot.1?.contains("Body line 1") == true)
        #expect(snapshot.2 == nil)
        #expect(snapshot.3 == false)
    }

    @Test("requestCreatePullRequest surfaces PR URL in lastInfoMessage on success")
    func requestCreatePR_surfacesURLOnSuccess() async throws {
        let vm = makeViewModel()
        vm.createPullRequestHandler = { _, _, _, _ in
            URL(string: "https://github.com/u/r/pull/99")!
        }
        vm.commitMessageDraft = "fix: test"
        vm.requestCreatePullRequest()
        await flush()

        #expect(vm.lastInfoMessage?.contains("pull/99") == true)
        #expect(vm.lastErrorMessage == nil)
        #expect(vm.isGitActionRunning == false)
    }

    @Test("requestCreatePullRequest surfaces handler error in lastErrorMessage")
    func requestCreatePR_surfacesHandlerError() async throws {
        struct HandlerError: LocalizedError {
            var errorDescription: String? { "Oops" }
        }
        let vm = makeViewModel()
        vm.createPullRequestHandler = { _, _, _, _ in throw HandlerError() }
        vm.commitMessageDraft = "fix: failing pr"
        vm.requestCreatePullRequest()
        await flush()

        #expect(vm.lastErrorMessage?.contains("Oops") == true)
        #expect(vm.lastInfoMessage == nil)
        #expect(vm.isGitActionRunning == false)
    }

    @Test("requestCreatePullRequest honours draft + base branch arguments")
    func requestCreatePR_forwardsDraftAndBase() async throws {
        let vm = makeViewModel()
        let captured = LockedBox<(String, String?, String?, Bool)?>(nil)
        vm.createPullRequestHandler = { title, body, baseBranch, draft in
            captured.withValue { $0 = (title, body, baseBranch, draft) }
            return URL(string: "https://github.com/u/r/pull/7")!
        }
        vm.commitMessageDraft = "feat: draft"
        vm.requestCreatePullRequest(title: "Explicit title", body: "Explicit body", baseBranch: "main", draft: true)
        await flush()

        let snapshot = captured.withValue { $0 }
        try #require(snapshot != nil)
        guard let snapshot else { return }
        #expect(snapshot.0 == "Explicit title")
        #expect(snapshot.1 == "Explicit body")
        #expect(snapshot.2 == "main")
        #expect(snapshot.3 == true)
    }
}
