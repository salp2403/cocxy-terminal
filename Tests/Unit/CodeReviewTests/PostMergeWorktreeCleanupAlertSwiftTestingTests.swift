// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PostMergeWorktreeCleanupAlertSwiftTestingTests.swift - Pure-helper
// coverage for the optional 3-button alert added in v0.1.87.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PostMergeWorktreeCleanupAlert")
struct PostMergeWorktreeCleanupAlertSwiftTestingTests {

    // MARK: - shouldOffer

    @Test("shouldOffer is true when delete-branch + matching feature branch + fetchedOnly")
    func shouldOfferCanonical() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "feat/x", baseBranch: "main")
        #expect(PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: outcome
        ))
    }

    @Test("shouldOffer is false when delete-branch was disabled")
    func shouldOfferDeleteBranchFalse() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "feat/x", baseBranch: "main")
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: false,
            headRefName: "feat/x",
            outcome: outcome
        ))
    }

    @Test("shouldOffer is false when the local branch differs from headRefName")
    func shouldOfferBranchMismatch() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "feat/y", baseBranch: "main")
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: outcome
        ))
    }

    @Test("shouldOffer is false when synced (user already on base)")
    func shouldOfferSynced() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 0)
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: outcome
        ))
    }

    @Test("shouldOffer is false on dirty tree")
    func shouldOfferDirtyTree() {
        let outcome = GitMergeAftermathOutcome.skippedDirtyTree(branch: "feat/x", modifiedCount: 1, untrackedCount: 0)
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: outcome
        ))
    }

    @Test("shouldOffer is false on detached HEAD")
    func shouldOfferDetached() {
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: .skippedDetachedHead
        ))
    }

    @Test("shouldOffer is false on workspace vanished")
    func shouldOfferVanished() {
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: .workspaceVanished
        ))
    }

    @Test("shouldOffer is false on non-fast-forward (user has divergent commits)")
    func shouldOfferNonFF() {
        let outcome = GitMergeAftermathOutcome.skippedNonFastForward(branch: "main", ahead: 1, behind: 1)
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "feat/x",
            outcome: outcome
        ))
    }

    @Test("shouldOffer is false when headRefName is whitespace")
    func shouldOfferEmptyHeadRef() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "", baseBranch: "main")
        #expect(!PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "  ",
            outcome: outcome
        ))
    }

    @Test("shouldOffer trims headRefName before comparing")
    func shouldOfferTrimmedHeadRef() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "feat/x", baseBranch: "main")
        #expect(PostMergeWorktreeCleanupAlert.shouldOffer(
            deleteBranchUsed: true,
            headRefName: "  feat/x  ",
            outcome: outcome
        ))
    }

    // MARK: - decode

    @Test("decode maps first button to closeWorktree")
    func decodeFirstButton() {
        #expect(PostMergeWorktreeCleanupAlert.decode(response: .alertFirstButtonReturn) == .closeWorktree)
    }

    @Test("decode maps second button to keep")
    func decodeSecondButton() {
        #expect(PostMergeWorktreeCleanupAlert.decode(response: .alertSecondButtonReturn) == .keep)
    }

    @Test("decode maps third button to cancel")
    func decodeThirdButton() {
        #expect(PostMergeWorktreeCleanupAlert.decode(response: .alertThirdButtonReturn) == .cancel)
    }

    @Test("decode maps unknown response codes to cancel")
    func decodeUnknown() {
        #expect(PostMergeWorktreeCleanupAlert.decode(response: .stop) == .cancel)
        #expect(PostMergeWorktreeCleanupAlert.decode(response: .abort) == .cancel)
    }

    // MARK: - banner copy

    @Test("keep fragment includes the head branch name")
    func keepFragment() {
        #expect(PostMergeWorktreeCleanupAlert.keepBannerFragment(headRefName: "feat/x")
                .contains("`feat/x`"))
    }

    @Test("closed fragment includes the head branch name")
    func closedFragment() {
        #expect(PostMergeWorktreeCleanupAlert.closedBannerFragment(headRefName: "feat/x")
                .contains("`feat/x`"))
    }

    @Test("closeFailed fragment guides the user to manual close")
    func closeFailedFragment() {
        let message = PostMergeWorktreeCleanupAlert.closeFailedBannerFragment(headRefName: "feat/x")
        let lower = message.lowercased()
        #expect(lower.contains("manual"))
        #expect(lower.contains("cmd+w") || lower.contains("close"))
    }

    // MARK: - closePolicyOverride (v0.1.88)

    @Test("closePolicyOverride returns .remove when the tab owns a cocxy worktree")
    func closePolicyOverrideForWorktreeTab() {
        let tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/tmp/wt-feat-x", isDirectory: true),
            worktreeID: "abc123",
            worktreeRoot: URL(fileURLWithPath: "/tmp/wt-feat-x", isDirectory: true),
            worktreeOriginRepo: URL(fileURLWithPath: "/tmp/origin-repo", isDirectory: true),
            worktreeBranch: "feat/x"
        )
        #expect(PostMergeWorktreeCleanupAlert.closePolicyOverride(for: tab) == .remove)
    }

    @Test("closePolicyOverride returns nil when the tab has no worktree id")
    func closePolicyOverrideForPlainTab() {
        let tab = Tab(workingDirectory: URL(fileURLWithPath: "/tmp/plain", isDirectory: true))
        #expect(PostMergeWorktreeCleanupAlert.closePolicyOverride(for: tab) == nil)
    }

    @Test("closePolicyOverride returns nil for nil tab input")
    func closePolicyOverrideForNilTab() {
        #expect(PostMergeWorktreeCleanupAlert.closePolicyOverride(for: nil) == nil)
    }
}
