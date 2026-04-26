// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitMergeAftermathModels.swift - Value types describing the outcome of
// the post-merge sync (`git fetch` + optional `git pull --ff-only`)
// triggered after a successful `gh pr merge` from the in-panel flow.
//
// Lives in its own file (not folded into `GitHubMergeModels.swift`)
// because the aftermath surface is git-side, not gh-side, and grouping
// it with the gh request/response models would blur the contract.
//
// Every outcome is `Sendable + Equatable` so it can travel across the
// actor boundary and be asserted in tests without bridging code. The
// typed `displayMessage` mirrors the pattern used by
// `GitHubMergeError.errorDescription` so the banner UI can surface the
// same copy across surfaces (Code Review panel + GitHub pane).

import Foundation

// MARK: - GitMergeAftermathOutcome

/// Result of a successful aftermath run. Every case is *informational*
/// (the merge itself already succeeded; the aftermath is best-effort
/// sync) so the view layer routes them through the **info** banner
/// channel — never the error channel — per
/// `feedback_info_vs_error_banners`.
///
/// The cases enumerate every reason the sync could legitimately decline
/// to act. Errors that the user should hear about (fetch/pull failed,
/// git binary missing, timeout) flow through `GitMergeAftermathError`
/// instead.
enum GitMergeAftermathOutcome: Equatable, Sendable {

    /// Working tree was clean and on `branch == baseBranch`. We fetched
    /// the base ref and ran `git pull --ff-only`, leaving the local
    /// branch up-to-date with origin.
    ///
    /// - Parameters:
    ///   - branch: The branch the sync ran on (always equal to the PR's
    ///     `baseRefName`).
    ///   - ahead: Number of commits the local branch was *ahead* of
    ///     origin **before** the pull. A non-zero value here is unusual
    ///     post-merge but harmless — the FF pull simply moves origin
    ///     forward to match local.
    ///   - behind: Number of commits the local branch was *behind*
    ///     origin **before** the pull. The pull removes this gap.
    case synced(branch: String, ahead: Int, behind: Int)

    /// Working tree was clean but the user is on a non-base branch
    /// (typically the feature branch that was just merged). We fetched
    /// `baseBranch` so the local copy of the base ref is fresh, but
    /// did **not** check out or pull — switching branches under the
    /// user is too invasive for an automatic flow.
    case fetchedOnly(currentBranch: String, baseBranch: String)

    /// Working tree had uncommitted or untracked changes. The sync
    /// declined to act so the user keeps full control over their work.
    /// Counters are best-effort summaries derived from
    /// `git status --porcelain`.
    case skippedDirtyTree(branch: String?, modifiedCount: Int, untrackedCount: Int)

    /// HEAD is detached (typical after a `git checkout <sha>` or during
    /// rebase). We cannot meaningfully resolve a "current branch" so
    /// the sync stops without side effects.
    case skippedDetachedHead

    /// `directory` is not inside a git working tree. The sync is a
    /// no-op; the merge already succeeded for `gh` reasons unrelated to
    /// the local checkout.
    case skippedNotInRepo

    /// `git pull --ff-only` would not have been a fast-forward (local
    /// branch has diverging commits). We declined to merge automatically
    /// to avoid creating an unexpected merge commit.
    case skippedNonFastForward(branch: String, ahead: Int, behind: Int)

    /// The working directory disappeared between the merge and the
    /// aftermath run (race with the user removing a worktree manually).
    case workspaceVanished

    // MARK: - Display helpers

    /// User-facing copy for the info banner. Every case maps to a
    /// concise sentence that explains *exactly* what happened so the
    /// user does not need to inspect git state to confirm.
    var displayMessage: String {
        switch self {
        case .synced(let branch, let ahead, let behind):
            if behind == 0 && ahead == 0 {
                return "`\(branch)` already in sync with origin."
            }
            if behind > 0 && ahead == 0 {
                let plural = behind == 1 ? "commit" : "commits"
                return "`\(branch)` synced with origin (\(behind) \(plural) pulled)."
            }
            if ahead > 0 && behind == 0 {
                return "`\(branch)` is \(ahead) ahead of origin (no pull needed)."
            }
            return "`\(branch)` synced with origin (was \(ahead) ahead, \(behind) behind)."
        case .fetchedOnly(let currentBranch, let baseBranch):
            return "Fetched `\(baseBranch)` from origin (still on `\(currentBranch)`, no pull needed)."
        case .skippedDirtyTree(let branch, let modifiedCount, let untrackedCount):
            let scope = branch.map { "`\($0)`" } ?? "current branch"
            var parts: [String] = []
            if modifiedCount > 0 { parts.append("\(modifiedCount) modified") }
            if untrackedCount > 0 { parts.append("\(untrackedCount) untracked") }
            let summary = parts.isEmpty ? "uncommitted changes" : parts.joined(separator: ", ")
            return "\(scope) not synced: \(summary). Commit or stash to enable auto-pull."
        case .skippedDetachedHead:
            return "Branch not synced: HEAD is detached."
        case .skippedNotInRepo:
            return "Branch not synced: working directory is not a git repository."
        case .skippedNonFastForward(let branch, let ahead, let behind):
            return "`\(branch)` not synced: would not fast-forward (local is \(ahead) ahead, \(behind) behind). Sync manually."
        case .workspaceVanished:
            return "Branch not synced: working directory no longer exists."
        }
    }
}

// MARK: - GitMergeAftermathError

/// Typed failure surface for the aftermath flow. Errors in this enum
/// surface through the **error** banner channel (red) because they
/// indicate something the user should investigate.
///
/// "User declined to act" results (dirty tree, detached HEAD, etc.)
/// belong in `GitMergeAftermathOutcome`, not here — the merge succeeded
/// and the only "failure" is a self-imposed safety guard, which is
/// informational not erroneous.
enum GitMergeAftermathError: Error, Equatable, Sendable, LocalizedError {

    /// No usable `git` binary was found on PATH or in the known
    /// fallback locations. Mirrors `WorktreeServiceError.gitUnavailable`
    /// for consistency.
    case gitUnavailable

    /// `git fetch` exited non-zero. `stderr` is captured verbatim so the
    /// banner can surface the actionable line (e.g. "fatal: unable to
    /// access 'https://github.com/.../': Could not resolve host").
    case fetchFailed(stderr: String, exitCode: Int32)

    /// `git pull --ff-only` exited non-zero for a reason other than
    /// "would not be a fast-forward" (which is folded into
    /// `Outcome.skippedNonFastForward`). Examples: ref deleted upstream,
    /// permission denied, generic network failure mid-pull.
    case pullFailed(stderr: String, exitCode: Int32)

    /// One of the git invocations exceeded its deadline. `operation`
    /// names the verb (`fetch`, `pull`, `status`) so the banner can
    /// distinguish a network-level fetch hang from a slow `pull`.
    case timedOut(operation: String, after: TimeInterval)

    /// `git status --porcelain` returned output that did not match the
    /// expected `XY <path>` shape. Extremely rare; kept as a typed case
    /// so future regressions surface clearly instead of being collapsed
    /// into a generic "fetch failed".
    case invalidPorcelainOutput(raw: String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "Could not auto-pull: git binary not found on PATH."
        case .fetchFailed(let stderr, let exitCode):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Auto-pull failed: `git fetch` exited \(exitCode)."
            }
            return "Auto-pull failed during fetch: \(trimmed)"
        case .pullFailed(let stderr, let exitCode):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Auto-pull failed: `git pull --ff-only` exited \(exitCode)."
            }
            return "Auto-pull failed during pull: \(trimmed)"
        case .timedOut(let operation, let after):
            return "Auto-pull timed out: `git \(operation)` exceeded \(Int(after))s."
        case .invalidPorcelainOutput(let raw):
            let preview = raw.prefix(80)
            return "Auto-pull aborted: unexpected `git status` output (\(preview))."
        }
    }
}
