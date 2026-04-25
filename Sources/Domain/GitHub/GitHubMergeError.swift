// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubMergeError.swift - Typed failure surface for `gh pr merge`.
//
// `gh pr merge` fails for many distinct reasons (conflicts, branch
// protection, missing approvals, network). Surfacing a generic
// `GitHubCLIError.commandFailed` would force every caller to re-parse
// stderr to render an actionable message. Instead, the service
// classifies the stderr once and emits one of the cases below. The
// view layer maps each case to a banner with concrete guidance.
//
// `GitHubMergeError` deliberately wraps `GitHubCLIError` for the
// transport-level failures (`.notInstalled`, `.timeout`, …) so the
// banner copy stays consistent with every other GitHub action.

import Foundation

// MARK: - GitHubMergeError

/// Typed failure surface for the merge flow.
enum GitHubMergeError: Error, Equatable, Sendable, LocalizedError {

    /// PR has unresolved merge conflicts. The user must resolve them
    /// manually (typically in a browser) before retrying.
    case mergeConflict

    /// One or more required status checks failed. Cocxy never
    /// auto-uses `--admin`; the user must wait for green or override
    /// from the GitHub web UI.
    case checksFailing(stderr: String)

    /// Required reviewer has not approved yet.
    case reviewRequired

    /// Reviewer requested changes that have not been addressed.
    case changesRequested

    /// PR head is behind base. The user must update the branch first.
    case behindBaseBranch

    /// User does not have the `pull_request:write` permission, or the
    /// repository is read-only for this account.
    case insufficientPermissions

    /// Branch protection rule blocks the merge. `reason` carries the
    /// raw policy text so the banner can quote it.
    case branchProtected(reason: String)

    /// PR is already merged (race with another client / CI).
    case alreadyMerged

    /// PR is closed without being merged.
    case prClosed

    /// PR was not found (deleted, never existed, wrong number).
    case pullRequestNotFound(number: Int)

    /// Auto-merge was enabled instead of an immediate merge because
    /// the queue requires it. Not strictly a failure but the UI needs
    /// to surface it differently from a synchronous merge success.
    case autoMergeEnabled

    /// Catch-all for stderr Cocxy did not recognise. Preserves the
    /// original message so the banner can render something useful.
    case notMergeable(reason: String)

    /// Transport-level failure (binary missing, timeout, etc.). Wrap
    /// the existing `GitHubCLIError` so banner copy reuses
    /// `GitHubPaneViewModel.banner(for:)` without duplication.
    case underlyingCLIError(GitHubCLIError)

    var errorDescription: String? {
        switch self {
        case .mergeConflict:
            return "The pull request has merge conflicts. Resolve them in a browser before retrying."
        case .checksFailing(let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Required status checks are failing for this pull request."
            }
            return "Required status checks are failing: \(trimmed)"
        case .reviewRequired:
            return "This pull request requires a reviewer approval before it can be merged."
        case .changesRequested:
            return "A reviewer requested changes. Address them and request another review."
        case .behindBaseBranch:
            return "The pull request branch is behind the base branch. Update the branch and retry."
        case .insufficientPermissions:
            return "You don't have permission to merge this pull request."
        case .branchProtected(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Branch protection rules block this merge."
            }
            return "Branch protection blocks the merge: \(trimmed)"
        case .alreadyMerged:
            return "This pull request is already merged."
        case .prClosed:
            return "This pull request is closed and cannot be merged."
        case .pullRequestNotFound(let number):
            return "Pull request #\(number) was not found."
        case .autoMergeEnabled:
            return "Auto-merge is enabled. The pull request will merge once requirements are met."
        case .notMergeable(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "The pull request cannot be merged at this time."
            }
            return "The pull request cannot be merged: \(trimmed)"
        case .underlyingCLIError(let error):
            switch error {
            case .notInstalled:
                return "Install the GitHub CLI: brew install gh"
            case .notAuthenticated:
                return "Sign in with `gh auth login` before merging."
            case .noRemote:
                return "No GitHub remote detected for this repository."
            case .notAGitRepository:
                return "Open a git repository to merge pull requests."
            case .rateLimited:
                return "GitHub rate limit reached. Try again later."
            case .timeout(let seconds):
                return "GitHub CLI timed out after \(Int(seconds))s. Check your network."
            case .invalidJSON(let reason):
                return "Unexpected gh output: \(reason)"
            case .unsupportedVersion:
                return "Update the GitHub CLI (`gh`). Homebrew users can run: brew upgrade gh"
            case .commandFailed(_, let stderr, _):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "The gh command failed." : trimmed
            }
        }
    }

    // MARK: - Classification

    /// Maps a failed `gh pr merge` invocation into a typed merge error.
    ///
    /// The mapping is intentionally string-based because `gh` does not
    /// expose a stable exit-code surface for the distinct failure
    /// reasons. Lowercased substring matches keep us resilient to
    /// minor copy changes in future `gh` releases. Anything we cannot
    /// classify falls through to `.notMergeable(reason:)` so the user
    /// still sees the raw stderr instead of a generic "merge failed".
    static func classify(stderr: String, exitCode: Int32, pullRequestNumber: Int) -> GitHubMergeError {
        let lower = stderr.lowercased()

        // Auto-merge enabled vs synchronous merge. `gh pr merge` prints
        // "Pull request #N will be automatically merged…" when the
        // queue requires it. Recognise it before treating non-zero
        // exit codes as failures.
        if lower.contains("will be automatically merged") ||
           lower.contains("auto-merge has been enabled") {
            return .autoMergeEnabled
        }

        // Already merged / closed / not found are very common races.
        if lower.contains("already been merged") || lower.contains("already merged") {
            return .alreadyMerged
        }
        if lower.contains("pull request is closed") || lower.contains("could not merge a closed") {
            return .prClosed
        }
        if lower.contains("could not resolve") && lower.contains("pull request") {
            return .pullRequestNotFound(number: pullRequestNumber)
        }
        if lower.contains("not found") && lower.contains("pull request") {
            return .pullRequestNotFound(number: pullRequestNumber)
        }

        // Conflict detection. `gh` prints "this branch has conflicts"
        // or "Pull request is not mergeable: dirty".
        if lower.contains("merge conflict") ||
           lower.contains("not mergeable") && lower.contains("dirty") ||
           lower.contains("has conflicts") {
            return .mergeConflict
        }

        // Behind base. `gh` text varies: "behind", "out of date",
        // "base branch was modified".
        if lower.contains("behind") && lower.contains("base") ||
           lower.contains("out-of-date") ||
           lower.contains("out of date") ||
           lower.contains("base branch was modified") {
            return .behindBaseBranch
        }

        // Branch protection / required checks. Detect explicit
        // "required status check" first so it does not fall through to
        // the generic "protected" detector.
        if lower.contains("required status check") ||
           (lower.contains("status check") && (lower.contains("fail") || lower.contains("expected"))) ||
           lower.contains("required check is expected") {
            return .checksFailing(stderr: stderr)
        }

        // Review state.
        if lower.contains("changes requested") ||
           lower.contains("change request") {
            return .changesRequested
        }
        if (lower.contains("review") && (lower.contains("required") || lower.contains("approval"))) ||
           lower.contains("at least 1 approving review") {
            return .reviewRequired
        }

        // Branch protection / admin override required.
        if lower.contains("protected branch") ||
           lower.contains("branch protection") ||
           lower.contains("admin override") {
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .branchProtected(reason: reason)
        }

        // Permission issues. `gh` returns 403 for write-protected
        // repositories or insufficient OAuth scopes.
        if lower.contains("permission") ||
           lower.contains("forbidden") ||
           lower.contains("403") ||
           lower.contains("write access") {
            return .insufficientPermissions
        }

        // Default: surface the raw stderr so the user still sees
        // actionable text. Fold whitespace so the banner stays tidy.
        let cleaned = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .notMergeable(reason: cleaned.isEmpty ? "exit code \(exitCode)" : cleaned)
    }
}
