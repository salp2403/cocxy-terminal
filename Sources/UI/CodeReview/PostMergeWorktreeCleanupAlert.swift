// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PostMergeWorktreeCleanupAlert.swift - Optional 3-button alert that
// surfaces after an in-panel PR merge succeeds, the user requested
// `--delete-branch`, and the local checkout is still parked on the
// (now-deleted) feature branch.
//
// v0.1.87 ships only the "close the tab" outcome — the worktree
// directory and `.git/worktrees/<id>` entry stay on disk so the user
// can still inspect the remnants if they want. The physical removal
// (`git worktree remove`) is a v0.1.88 follow-up.
//
// The decision logic is split into pure helpers so the test suite can
// exercise every branch without driving an `NSAlert`. The presenter is
// a thin AppKit shim that maps the modal response back to a
// `Resolution` — same architecture as `MergePullRequestActionSheet`.

import AppKit
import Foundation

// MARK: - PostMergeWorktreeCleanupAlert

enum PostMergeWorktreeCleanupAlert {

    // MARK: Resolution

    /// User decision returned by `present(...)`. Mapped from the modal
    /// response through `decode(...)` so tests can validate every
    /// branch without spawning a live alert.
    enum Resolution: Equatable, Sendable {
        /// User asked to close the (worktree-backed) tab. The caller
        /// invokes the programmatic close path
        /// (`MainWindowController.performCloseTab`) so the dismissal
        /// runs without bumping into the close-confirmation sheet.
        case closeWorktree

        /// User wants to keep the worktree open (e.g. to inspect
        /// post-merge diffs locally). The caller appends a confirmation
        /// fragment to the merge banner so the user knows their choice
        /// landed.
        case keep

        /// User cancelled the alert (Esc, Cancel button, programmatic
        /// dismiss). The caller should treat this as a no-op.
        case cancel
    }

    // MARK: - Pure decision helpers

    /// Whether the alert should even be presented for the given merge
    /// context + aftermath outcome. The function is intentionally
    /// conservative: the alert only fires when **all** the following
    /// hold so we never offer cleanup with surprising side effects.
    ///
    /// - `deleteBranchUsed` — the user opted into `--delete-branch`,
    ///   indicating they expect the feature branch to disappear.
    /// - `headRefName` — non-empty PR head branch.
    /// - `outcome.fetchedOnly` — the local checkout is still parked
    ///   on a non-base branch matching `headRefName`. Every other
    ///   outcome variant skips the alert because either the branch
    ///   does not match or the working tree is in a state where
    ///   cleanup would surprise the user (dirty, detached, vanished).
    static func shouldOffer(
        deleteBranchUsed: Bool,
        headRefName: String,
        outcome: GitMergeAftermathOutcome
    ) -> Bool {
        guard deleteBranchUsed else { return false }
        let trimmedHeadRef = headRefName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHeadRef.isEmpty else { return false }

        switch outcome {
        case .fetchedOnly(let currentBranch, _):
            return currentBranch == trimmedHeadRef
        case .synced,
             .skippedDirtyTree,
             .skippedDetachedHead,
             .skippedNotInRepo,
             .skippedNonFastForward,
             .workspaceVanished:
            return false
        }
    }

    /// Maps an `NSAlert.ModalResponse` to a `Resolution`. Anything
    /// outside the documented button range collapses to `.cancel` so
    /// programmatic dismiss / Esc behave predictably.
    static func decode(response: NSApplication.ModalResponse) -> Resolution {
        switch response {
        case .alertFirstButtonReturn:
            return .closeWorktree
        case .alertSecondButtonReturn:
            return .keep
        case .alertThirdButtonReturn:
            return .cancel
        default:
            return .cancel
        }
    }

    // MARK: - Banner copy helpers

    /// Confirmation fragment appended to the merge banner when the
    /// user picked "Keep Worktree". Pure so the banner copy can be
    /// asserted in tests without triggering the alert.
    static func keepBannerFragment(headRefName: String) -> String {
        "Worktree on `\(headRefName)` retained."
    }

    /// Confirmation fragment appended to the merge banner when the
    /// user picked "Close Worktree" and the close succeeded.
    static func closedBannerFragment(headRefName: String) -> String {
        "Worktree on `\(headRefName)` closed."
    }

    /// Fallback fragment if the close handler returned `false` (last
    /// terminal guard, pinned tab, missing handler, etc.). Tells the
    /// user the close did not happen so they can fix it manually.
    static func closeFailedBannerFragment(headRefName: String) -> String {
        "Could not close the worktree tab automatically — close it manually with Cmd+W."
    }

    // MARK: - Presentation

    /// Presents the alert as an application-modal window. Mirrors the
    /// modal style of `MergePullRequestActionSheet` so the two flows
    /// chained back-to-back share a recognisable visual rhythm.
    @MainActor
    static func present(headRefName: String) -> Resolution {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Close worktree for `\(headRefName)`?"
        alert.informativeText = """
        The branch `\(headRefName)` was deleted on origin after the merge. \
        You can close this worktree's tab now or keep it open to inspect the result. \
        Closing the tab does not yet remove the worktree directory on disk.
        """

        // Order: Close → Keep → Cancel. Close is the default (first
        // button) because it matches the most common post-merge
        // intent — the user explicitly asked for `--delete-branch`,
        // so closing the now-orphan tab is the natural follow-up.
        alert.addButton(withTitle: "Close Worktree")
        alert.addButton(withTitle: "Keep Worktree")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"  // Esc → Cancel.

        return decode(response: alert.runModal())
    }
}
