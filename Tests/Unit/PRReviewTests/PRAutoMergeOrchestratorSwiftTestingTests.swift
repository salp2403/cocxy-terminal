// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRAutoMergeOrchestratorSwiftTestingTests.swift - Safety policy for PR auto-merge.

import Testing
@testable import CocxyTerminal

@Suite("PR auto-merge safety orchestrator")
struct PRAutoMergeOrchestratorSwiftTestingTests {

    @Test("clean approved mergeability merges immediately")
    func cleanApprovedMergeabilityMergesImmediately() {
        let request = GitHubMergeRequest(pullRequestNumber: 42, method: .squash)
        let decision = PRAutoMergeOrchestrator.decision(
            for: mergeability(state: .clean, checksPending: false),
            request: request
        )

        #expect(decision == .mergeNow(request))
    }

    @Test("pending checks with approval enable auto-merge instead of blocking")
    func pendingChecksWithApprovalEnableAutoMerge() {
        let request = GitHubMergeRequest(pullRequestNumber: 42, method: .squash)
        let decision = PRAutoMergeOrchestrator.decision(
            for: mergeability(state: .unstable, checksPending: true),
            request: request
        )

        #expect(decision == .enableAutoMerge(request))
    }

    @Test("review required blocks auto-merge even when checks are pending")
    func reviewRequiredBlocksAutoMerge() {
        let decision = PRAutoMergeOrchestrator.decision(
            for: mergeability(
                state: .unstable,
                reviewDecision: .reviewRequired,
                checksPending: true
            ),
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .merge)
        )

        guard case .blocked(let reason) = decision else {
            Issue.record("Expected blocked decision")
            return
        }
        #expect(reason.contains("review required"))
    }

    @Test("conflicts block auto-merge")
    func conflictsBlockAutoMerge() {
        let decision = PRAutoMergeOrchestrator.decision(
            for: mergeability(
                conflictStatus: .conflicting,
                state: .dirty,
                checksPending: true
            ),
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .rebase)
        )

        guard case .blocked(let reason) = decision else {
            Issue.record("Expected blocked decision")
            return
        }
        #expect(reason.contains("merge conflicts"))
    }

    @Test("mismatched pull request number blocks before any action")
    func mismatchedPullRequestNumberBlocksBeforeAnyAction() {
        let decision = PRAutoMergeOrchestrator.decision(
            for: mergeability(number: 41, state: .clean),
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash)
        )

        guard case .blocked(let reason) = decision else {
            Issue.record("Expected blocked decision")
            return
        }
        #expect(reason.contains("#41"))
        #expect(reason.contains("#42"))
    }

    private func mergeability(
        number: Int = 42,
        conflictStatus: GitHubMergeableStatus = .mergeable,
        state: GitHubMergeStateStatus,
        reviewDecision: GitHubReviewDecision = .approved,
        checksPassed: Bool = true,
        checksPending: Bool = false
    ) -> GitHubMergeability {
        GitHubMergeability(
            pullRequestNumber: number,
            conflictStatus: conflictStatus,
            stateStatus: state,
            reviewDecision: reviewDecision,
            checksPassed: checksPassed,
            checksPending: checksPending
        )
    }
}
