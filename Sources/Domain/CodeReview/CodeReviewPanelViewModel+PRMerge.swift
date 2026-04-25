// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModel+PRMerge.swift - Merge integration for the
// in-panel PR merge feature shipped in v0.1.86.
//
// Lives in its own file so the main view model (1042 LOC and growing)
// does not have to absorb another behaviour. The extension owns:
//
//   - attachActivePullRequestNumber(_:) — captures the PR number from
//     the post-create flow or from the auto-detect routine, then kicks
//     off a mergeability refresh
//   - refreshActivePullRequestState() — re-runs both the detection
//     routine and the mergeability fetch; safe to call after every
//     refreshDiffs / git workflow action
//   - requestMergePullRequest(method:deleteBranch:subject:body:) —
//     drives the merge through the injected handler, surfaces success
//     in `lastInfoMessage`, classifies failures into
//     `pullRequestMergeErrorMessage`
//   - clearActivePullRequest() — wipes the PR state when the panel
//     transitions to a session/tab without an associated branch

import Foundation
import os.log

extension CodeReviewPanelViewModel {

    // MARK: - Logger

    /// `os.log` Logger for the merge integration. `dev.cocxy.terminal`
    /// matches every other Cocxy-internal log entry so a single
    /// `log stream --predicate 'subsystem == "dev.cocxy.terminal"'`
    /// surfaces the whole flow.
    private static let mergeLogger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "CodeReviewPRMerge"
    )

    // MARK: - PR association

    /// Captures the PR number returned by the create-PR flow, or by
    /// the auto-detection helper, and triggers a mergeability refresh.
    /// Idempotent: re-attaching the same number is a no-op for the
    /// stored number and re-runs the mergeability fetch (because the
    /// state may have shifted upstream).
    func attachActivePullRequestNumber(_ number: Int) {
        let changed = activePullRequestNumber != number
        if changed {
            activePullRequestNumber = number
            // Reset transient state from the previous PR (if any) so
            // the chip does not flash a stale blocker while the new
            // mergeability fetch is in flight.
            activePullRequestMergeability = nil
            pullRequestMergeErrorMessage = nil
        }
        Task { [weak self] in
            await self?.refreshMergeabilityForActivePR()
        }
    }

    /// Drops every piece of merge-related state. Called from the
    /// session-switch hooks when the new active session has no working
    /// directory or no detection handler is wired.
    func clearActivePullRequest() {
        guard activePullRequestNumber != nil
            || activePullRequestMergeability != nil
            || pullRequestMergeErrorMessage != nil
            || pullRequestMergeInfoMessage != nil
            || isMergingPullRequest else { return }
        activePullRequestNumber = nil
        activePullRequestMergeability = nil
        pullRequestMergeErrorMessage = nil
        pullRequestMergeInfoMessage = nil
        isMergingPullRequest = false
    }

    // MARK: - Refresh

    /// Re-runs the auto-detection helper (if wired) followed by the
    /// mergeability fetch. Safe to call as a side-effect of any flow
    /// that changes the active branch — refreshDiffs, push, create PR.
    /// Network round-trips happen only when handlers are non-nil.
    func refreshActivePullRequestState() {
        guard let detectionHandler = activePullRequestDetectionHandler else {
            // No handler wired (yet). The MainWindowController attaches
            // it on first GitHub pane open; subsequent invocations
            // succeed. Surfacing nothing keeps the panel clean.
            return
        }

        guard let branch = currentBranchForMergeIntegration() else {
            clearActivePullRequest()
            return
        }

        Task { [weak self] in
            do {
                let resolvedNumber = try await detectionHandler(branch)
                await MainActor.run {
                    guard let self else { return }
                    if let resolvedNumber {
                        if self.activePullRequestNumber != resolvedNumber {
                            self.activePullRequestNumber = resolvedNumber
                            self.activePullRequestMergeability = nil
                        }
                        Task { await self.refreshMergeabilityForActivePR() }
                    } else {
                        self.clearActivePullRequest()
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    Self.mergeLogger.debug(
                        """
                        PR detection by branch failed (treated as no PR): \
                        branch=\(branch, privacy: .public) \
                        error=\(String(describing: error), privacy: .private)
                        """
                    )
                    self.clearActivePullRequest()
                }
            }
        }
    }

    /// Re-fetches mergeability for the currently attached PR. No-op
    /// when no PR is attached or when the handler is nil.
    ///
    /// On success the snapshot is stored, but we deliberately do **not**
    /// clear `pullRequestMergeErrorMessage`: the merge flow owns that
    /// channel and a successful mergeability fetch does not invalidate
    /// a recent merge failure. The error is cleared the next time the
    /// user attempts a merge (or by `clearActivePullRequest`).
    func refreshMergeabilityForActivePR() async {
        guard let number = activePullRequestNumber else { return }
        guard let handler = pullRequestMergeabilityHandler else { return }

        do {
            let snapshot = try await handler(number)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.activePullRequestNumber == number else {
                    // Active PR changed while we were in flight —
                    // discard the stale snapshot so the UI does not
                    // momentarily render the wrong PR's mergeability.
                    return
                }
                self.activePullRequestMergeability = snapshot
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.activePullRequestNumber == number else { return }
                Self.mergeLogger.debug(
                    """
                    Mergeability fetch failed: pr=\(number, privacy: .public) \
                    error=\(String(describing: error), privacy: .private)
                    """
                )
                self.pullRequestMergeErrorMessage = Self.userFacingMergeErrorMessage(for: error)
            }
        }
    }

    // MARK: - Merge

    /// Drives a merge of the active PR through the injected handler.
    /// No-op when no PR is attached, no handler is wired, the cached
    /// mergeability blocks the merge, or another merge is already in
    /// flight.
    ///
    /// - Parameters:
    ///   - method: Strategy passed to `gh pr merge`.
    ///   - deleteBranch: Whether to append `--delete-branch`. The view
    ///     layer persists the user's last choice in `UserDefaults` and
    ///     forwards it here.
    ///   - subject: Optional commit subject override (forwarded to
    ///     `gh pr merge --subject`). `nil` keeps the gh default.
    ///   - body: Optional commit body override (`--body`). `nil` keeps
    ///     the gh default.
    func requestMergePullRequest(
        method: GitHubMergeMethod,
        deleteBranch: Bool,
        subject: String? = nil,
        body: String? = nil
    ) {
        guard let number = activePullRequestNumber else {
            pullRequestMergeErrorMessage = "No pull request is attached to this review."
            return
        }
        guard let handler = mergePullRequestHandler else {
            pullRequestMergeErrorMessage = "GitHub integration is not ready yet. Open the GitHub pane once to initialise it."
            return
        }
        guard !isMergingPullRequest else { return }

        let request = GitHubMergeRequest(
            pullRequestNumber: number,
            method: method,
            deleteBranch: deleteBranch,
            subject: subject,
            body: body
        )

        isMergingPullRequest = true
        pullRequestMergeErrorMessage = nil
        pullRequestMergeInfoMessage = nil

        Task { [weak self] in
            do {
                let merged = try await handler(request)
                await MainActor.run {
                    guard let self else { return }
                    guard self.activePullRequestNumber == number else { return }
                    self.isMergingPullRequest = false
                    self.pullRequestMergeInfoMessage = "Merged PR #\(merged.number) via \(method.displayName)."
                    // Refresh mergeability so the chip flips to .merged
                    // and the merge button hides immediately.
                    Task { await self.refreshMergeabilityForActivePR() }
                    // Refresh git status so the workflow panel reflects
                    // the post-merge state (deleted branch, etc.).
                    self.refreshGitStatus()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    guard self.activePullRequestNumber == number else { return }
                    Self.mergeLogger.error(
                        """
                        Merge failed: pr=\(number, privacy: .public) \
                        method=\(method.rawValue, privacy: .public) \
                        error=\(String(describing: error), privacy: .private)
                        """
                    )
                    self.isMergingPullRequest = false
                    self.pullRequestMergeErrorMessage = Self.userFacingMergeErrorMessage(for: error)
                    // Mergeability may have shifted (auto-merge, conflict)
                    // — refresh so the chip and reason update.
                    Task { await self.refreshMergeabilityForActivePR() }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Resolves the branch name to feed `pullRequestNumber(forBranch:)`.
    /// Prefers the explicit `activeBranchProvider` (set by callers and
    /// by tests) so the integration can be exercised without spinning
    /// up a real git workflow; falls back to the cached gitStatus
    /// branch when the provider returns nil.
    private func currentBranchForMergeIntegration() -> String? {
        if let provided = activeBranchProvider?()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !provided.isEmpty {
            return provided
        }
        if let branch = gitStatus?.branch.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty {
            return branch
        }
        return nil
    }

    /// Maps an `Error` into a user-facing string. Recognises
    /// `GitHubMergeError` for typed copy and falls back to
    /// `localizedDescription` so unexpected errors still render
    /// something the user can act on.
    static func userFacingMergeErrorMessage(for error: Error) -> String {
        if let mergeError = error as? GitHubMergeError {
            return mergeError.errorDescription ?? "Pull request could not be merged."
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "Pull request action failed." : description
    }
}
