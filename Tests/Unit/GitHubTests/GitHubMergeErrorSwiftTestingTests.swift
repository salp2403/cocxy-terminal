// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubMergeErrorSwiftTestingTests.swift - Classification tests for the
// stderr → typed-error mapper used by `GitHubService.mergePullRequest`.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Classifier

@Suite("GitHubMergeError.classify")
struct GitHubMergeErrorClassifySwiftTestingTests {

    @Test("classifies merge conflict stderr")
    func classifiesMergeConflictStderr() {
        let cases = [
            "merge conflict in src/foo.swift",
            "Pull request is not mergeable: dirty",
            "this branch has conflicts that must be resolved",
        ]
        for stderr in cases {
            let error = GitHubMergeError.classify(stderr: stderr, exitCode: 1, pullRequestNumber: 42)
            #expect(error == .mergeConflict, "Failed to classify: \(stderr)")
        }
    }

    @Test("classifies failing required checks")
    func classifiesFailingRequiredChecks() {
        let stderr = "Required status check 'ci/build' is expected"
        let error = GitHubMergeError.classify(stderr: stderr, exitCode: 1, pullRequestNumber: 42)
        switch error {
        case .checksFailing(let captured):
            #expect(captured == stderr)
        default:
            Issue.record("Expected .checksFailing, got \(error)")
        }
    }

    @Test("classifies review required and changes requested distinctly")
    func classifiesReviewStatesDistinctly() {
        let reviewRequired = GitHubMergeError.classify(
            stderr: "At least 1 approving review is required",
            exitCode: 1,
            pullRequestNumber: 42
        )
        let changesRequested = GitHubMergeError.classify(
            stderr: "merge blocked: changes requested by reviewer",
            exitCode: 1,
            pullRequestNumber: 42
        )
        #expect(reviewRequired == .reviewRequired)
        #expect(changesRequested == .changesRequested)
    }

    @Test("classifies behind base branch from gh stderr")
    func classifiesBehindBaseBranchFromGhStderr() {
        let cases = [
            "Pull request branch is behind the base branch",
            "Update branch — out-of-date",
            "Base branch was modified — update your branch",
        ]
        for stderr in cases {
            let error = GitHubMergeError.classify(
                stderr: stderr,
                exitCode: 1,
                pullRequestNumber: 42
            )
            #expect(error == .behindBaseBranch, "Failed for: \(stderr)")
        }
    }

    @Test("classifies insufficient permissions from 403/forbidden text")
    func classifiesInsufficientPermissionsFromForbiddenText() {
        let cases = [
            "HTTP 403: Forbidden",
            "you do not have permission to merge this pull request",
            "write access required to merge",
        ]
        for stderr in cases {
            let error = GitHubMergeError.classify(
                stderr: stderr,
                exitCode: 1,
                pullRequestNumber: 42
            )
            #expect(error == .insufficientPermissions, "Failed for: \(stderr)")
        }
    }

    @Test("classifies branch protection and preserves the raw reason")
    func classifiesBranchProtectionAndPreservesRawReason() {
        let stderr = "Required: protected branch policy 'no-direct-push' applied"
        let error = GitHubMergeError.classify(
            stderr: stderr,
            exitCode: 1,
            pullRequestNumber: 42
        )
        switch error {
        case .branchProtected(let reason):
            #expect(reason.contains("protected branch"))
        default:
            Issue.record("Expected .branchProtected, got \(error)")
        }
    }

    @Test("classifies already merged race")
    func classifiesAlreadyMergedRace() {
        let stderr = "Pull request has already been merged"
        let error = GitHubMergeError.classify(
            stderr: stderr,
            exitCode: 1,
            pullRequestNumber: 42
        )
        #expect(error == .alreadyMerged)
    }

    @Test("classifies closed PR")
    func classifiesClosedPullRequest() {
        let stderr = "Pull request is closed; could not merge a closed PR"
        let error = GitHubMergeError.classify(
            stderr: stderr,
            exitCode: 1,
            pullRequestNumber: 42
        )
        #expect(error == .prClosed)
    }

    @Test("classifies pull request not found")
    func classifiesPullRequestNotFound() {
        let stderr = "Could not resolve pull request: not found"
        let error = GitHubMergeError.classify(
            stderr: stderr,
            exitCode: 1,
            pullRequestNumber: 999
        )
        #expect(error == .pullRequestNotFound(number: 999))
    }

    @Test("classifies auto-merge enabled (gh exits 0 but prints message)")
    func classifiesAutoMergeEnabled() {
        let stderr = "Pull request #42 will be automatically merged once requirements are met"
        let error = GitHubMergeError.classify(
            stderr: stderr,
            exitCode: 0,
            pullRequestNumber: 42
        )
        #expect(error == .autoMergeEnabled)
    }

    @Test("falls back to .notMergeable preserving raw stderr for unrecognised text")
    func fallsBackToNotMergeablePreservingRawStderr() {
        let stderr = "completely novel failure mode 99% certain you have not seen before"
        let error = GitHubMergeError.classify(
            stderr: stderr,
            exitCode: 7,
            pullRequestNumber: 42
        )
        switch error {
        case .notMergeable(let reason):
            #expect(reason == stderr)
        default:
            Issue.record("Expected .notMergeable, got \(error)")
        }
    }

    @Test("falls back uses exit-code text when stderr is empty")
    func fallsBackUsesExitCodeTextWhenStderrIsEmpty() {
        let error = GitHubMergeError.classify(stderr: "", exitCode: 5, pullRequestNumber: 42)
        switch error {
        case .notMergeable(let reason):
            #expect(reason.contains("5"))
        default:
            Issue.record("Expected .notMergeable, got \(error)")
        }
    }
}

// MARK: - errorDescription

@Suite("GitHubMergeError.errorDescription")
struct GitHubMergeErrorDescriptionSwiftTestingTests {

    @Test("each case yields a non-empty user-facing message")
    func eachCaseYieldsNonEmptyUserFacingMessage() {
        let cases: [GitHubMergeError] = [
            .mergeConflict,
            .checksFailing(stderr: "ci failed"),
            .checksFailing(stderr: ""),
            .reviewRequired,
            .changesRequested,
            .behindBaseBranch,
            .insufficientPermissions,
            .branchProtected(reason: "policy"),
            .branchProtected(reason: ""),
            .alreadyMerged,
            .prClosed,
            .pullRequestNotFound(number: 9001),
            .autoMergeEnabled,
            .notMergeable(reason: "weird"),
            .notMergeable(reason: ""),
            .underlyingCLIError(.notInstalled),
            .underlyingCLIError(.notAuthenticated(stderr: "")),
            .underlyingCLIError(.timeout(seconds: 10)),
            .underlyingCLIError(.invalidJSON(reason: "bad")),
            .underlyingCLIError(.unsupportedVersion(stderr: "")),
            .underlyingCLIError(.commandFailed(command: "gh", stderr: "boom", exitCode: 1)),
        ]
        for error in cases {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty, "Empty description for \(error)")
        }
    }

    @Test("notMergeable with empty reason yields a generic friendly message")
    func notMergeableWithEmptyReasonYieldsGenericFriendlyMessage() {
        let error = GitHubMergeError.notMergeable(reason: "")
        let description = error.errorDescription ?? ""
        #expect(description.lowercased().contains("cannot be merged"))
    }

    @Test("pullRequestNotFound interpolates the number into the message")
    func pullRequestNotFoundInterpolatesTheNumberIntoTheMessage() {
        let error = GitHubMergeError.pullRequestNotFound(number: 1234)
        let description = error.errorDescription ?? ""
        #expect(description.contains("#1234"))
    }

    @Test("underlyingCLIError preserves transport-level guidance")
    func underlyingCLIErrorPreservesTransportLevelGuidance() {
        let error = GitHubMergeError.underlyingCLIError(.notInstalled)
        let description = error.errorDescription ?? ""
        #expect(description.lowercased().contains("install"))
    }
}
