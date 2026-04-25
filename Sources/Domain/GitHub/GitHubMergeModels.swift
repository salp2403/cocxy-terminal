// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubMergeModels.swift - Value types describing pull-request merge
// strategies and the pre-merge mergeability snapshot the UI consumes
// before invoking `gh pr merge`.
//
// Lives in its own file (not inside `GitHubModels.swift`) because that
// file already crosses the 600-LOC ceiling — a new model surface earns
// its own home rather than pushing the existing one further. Every
// type below is `Sendable + Equatable + Codable` and decodes with
// `decodeIfPresent` so future `gh` releases that rename or drop a
// field fall back to `.unknown` instead of failing the entire query.

import Foundation

// MARK: - Merge method

/// Strategy passed to `gh pr merge`.
///
/// The raw values match the long-form CLI flags so callers can derive
/// the argument list from the case directly. `Codable` so a request
/// shape persisted across the CLI socket round-trips losslessly.
enum GitHubMergeMethod: String, Codable, Sendable, Equatable, CaseIterable {
    case squash
    case merge
    case rebase

    /// CLI flag fragment for `gh pr merge`. Used by the service when
    /// composing the argument list.
    var ghFlag: String {
        switch self {
        case .squash: return "--squash"
        case .merge: return "--merge"
        case .rebase: return "--rebase"
        }
    }

    /// Label rendered inside the confirmation `NSAlert`. Matches the
    /// wording GitHub web uses for each strategy so the UX stays
    /// recognisable for users coming from the browser.
    var displayName: String {
        switch self {
        case .squash: return "Squash & Merge"
        case .merge: return "Merge Commit"
        case .rebase: return "Rebase & Merge"
        }
    }

    /// Short tooltip / accessibility hint describing what the strategy
    /// does. Avoids assuming the reader has used GitHub before.
    var summary: String {
        switch self {
        case .squash:
            return "Combine all commits into one and merge."
        case .merge:
            return "Create a merge commit preserving full history."
        case .rebase:
            return "Replay each commit on top of the base branch."
        }
    }
}

// MARK: - Conflict status

/// `mergeable` field as returned by `gh pr view --json mergeable`.
///
/// `gh` emits `MERGEABLE`, `CONFLICTING` or `UNKNOWN`. Older releases
/// occasionally return `null`; we collapse that to `.unknown` so the
/// UI does not have to pattern-match on optionality.
enum GitHubMergeableStatus: String, Codable, Sendable, Equatable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unknown
            return
        }
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        self = GitHubMergeableStatus(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .mergeable: return "Mergeable"
        case .conflicting: return "Conflicting"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Branch / merge state status

/// `mergeStateStatus` field from `gh pr view --json mergeStateStatus`.
///
/// This is the high-level state of the PR taking into account branch
/// protection rules, CI status and base-branch divergence. The values
/// are documented at
/// https://docs.github.com/graphql/reference/enums#mergestatestatus
/// — we mirror them verbatim plus an `unknown` fallback.
enum GitHubMergeStateStatus: String, Codable, Sendable, Equatable {
    /// Mergeable and every required status check has passed.
    case clean = "CLEAN"
    /// Mergeable but blocked by branch protection (failed required
    /// checks, missing approvals, or other admin policy).
    case blocked = "BLOCKED"
    /// PR head is behind the base branch and must be updated first.
    case behind = "BEHIND"
    /// Has merge conflicts that must be resolved manually.
    case dirty = "DIRTY"
    /// Mergeable but at least one status check is still in progress.
    case unstable = "UNSTABLE"
    /// Mergeable with non-blocking pre-merge hooks pending.
    case hasHooks = "HAS_HOOKS"
    /// Status could not be determined.
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unknown
            return
        }
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        self = GitHubMergeStateStatus(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .clean: return "Ready to merge"
        case .blocked: return "Blocked"
        case .behind: return "Behind base branch"
        case .dirty: return "Has conflicts"
        case .unstable: return "Checks in progress"
        case .hasHooks: return "Has merge hooks"
        case .unknown: return "Status unknown"
        }
    }

    /// Whether the state alone allows a merge. `clean` and `hasHooks`
    /// are the only states that proceed without admin override; the
    /// final `canMerge` decision still inspects review and check
    /// status before letting the user click the button.
    var allowsMerge: Bool {
        switch self {
        case .clean, .hasHooks:
            return true
        case .blocked, .behind, .dirty, .unstable, .unknown:
            return false
        }
    }
}

// MARK: - Status check rollup

/// Single entry of the `statusCheckRollup` array returned by
/// `gh pr view --json statusCheckRollup`.
///
/// Older `gh` releases emitted plain status check runs with `state`;
/// newer ones include workflow runs with `conclusion`. The decoder
/// keeps both shapes optional so an unexpected field never fails the
/// whole query.
struct GitHubStatusCheckRollupEntry: Codable, Sendable, Equatable {
    /// Either a check run state (`SUCCESS`, `FAILURE`, `PENDING`, …) or
    /// a workflow run status. Decoded via the lenient
    /// `GitHubCheckStatus` rules so unknown values fall back without
    /// failing the array.
    let state: String?
    /// Final conclusion when present. May be `null` when the run is
    /// still in flight.
    let conclusion: String?

    private enum CodingKeys: String, CodingKey {
        case state, conclusion, status
    }

    init(state: String?, conclusion: String?) {
        self.state = state
        self.conclusion = conclusion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Accept either `state` (check runs) or `status` (workflow runs)
        // for the in-progress label, mirroring the `gh` quirk.
        if let value = try container.decodeIfPresent(String.self, forKey: .state) {
            self.state = value
        } else {
            self.state = try container.decodeIfPresent(String.self, forKey: .status)
        }
        self.conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
    }

    /// Manual encoder so the synthesised one does not try to emit a
    /// value for the `status` coding key (it has no stored property,
    /// it only exists to honour the older `gh` shape on decode).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(conclusion, forKey: .conclusion)
    }

    /// Whether the entry counts as "passed" for `checksPassed`. We
    /// treat `SUCCESS`, `NEUTRAL` and `SKIPPED` as non-blocking; every
    /// other terminal state blocks the merge.
    var isPassing: Bool {
        let resolvedConclusion = conclusion?.uppercased() ?? state?.uppercased()
        switch resolvedConclusion {
        case "SUCCESS", "NEUTRAL", "SKIPPED":
            return true
        default:
            return false
        }
    }

    /// Whether the entry is still running. Pending/queued/in-progress
    /// runs do not count as passed but also do not block the merge
    /// decision — they collapse into the `.unstable` state.
    var isPending: Bool {
        let resolved = state?.uppercased() ?? conclusion?.uppercased()
        switch resolved {
        case "PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED", "WAITING":
            return true
        default:
            return false
        }
    }
}

// MARK: - Mergeability snapshot

/// Pre-merge snapshot of every dimension that decides whether
/// `gh pr merge` can succeed. The view layer renders a chip from
/// `canMerge` + `reasonIfBlocked` so the user knows ahead of time
/// whether the merge button should even be enabled.
///
/// The struct is `Codable` so it can travel verbatim across the
/// CLI socket boundary; the decoder is tolerant to missing fields
/// (newer `gh` may add `autoMergeRequest` etc. — we ignore them).
struct GitHubMergeability: Sendable, Equatable {

    /// Pull request number this snapshot describes.
    let pullRequestNumber: Int

    /// Conflict status reported by `gh pr view --json mergeable`.
    let conflictStatus: GitHubMergeableStatus

    /// Branch state reported by `gh pr view --json mergeStateStatus`.
    let stateStatus: GitHubMergeStateStatus

    /// Review approval state. Reuses the existing `GitHubReviewDecision`
    /// declared in `GitHubModels.swift` so we never duplicate the enum.
    let reviewDecision: GitHubReviewDecision

    /// True when every status check entry is passing. Derived from the
    /// `statusCheckRollup` array; an empty array also yields `true`
    /// because "no checks configured" is not a blocker.
    let checksPassed: Bool

    /// True when at least one status check is still pending. Used so
    /// the UI can distinguish "checks failing" from "checks running".
    let checksPending: Bool

    /// Whether the PR has already been merged. When `true`, the merge
    /// button is hidden entirely (`canMerge` is also `false`).
    let isAlreadyMerged: Bool

    /// Whether the PR is closed (without being merged). Same UI
    /// treatment as `isAlreadyMerged`.
    let isClosed: Bool

    init(
        pullRequestNumber: Int,
        conflictStatus: GitHubMergeableStatus,
        stateStatus: GitHubMergeStateStatus,
        reviewDecision: GitHubReviewDecision,
        checksPassed: Bool,
        checksPending: Bool = false,
        isAlreadyMerged: Bool = false,
        isClosed: Bool = false
    ) {
        self.pullRequestNumber = pullRequestNumber
        self.conflictStatus = conflictStatus
        self.stateStatus = stateStatus
        self.reviewDecision = reviewDecision
        self.checksPassed = checksPassed
        self.checksPending = checksPending
        self.isAlreadyMerged = isAlreadyMerged
        self.isClosed = isClosed
    }

    /// Single source of truth for "should the merge button be
    /// enabled?". Composition keeps every blocking dimension explicit
    /// so future additions only need to extend `reasonIfBlocked`.
    var canMerge: Bool {
        if isAlreadyMerged || isClosed { return false }
        guard conflictStatus == .mergeable else { return false }
        guard stateStatus.allowsMerge else { return false }
        guard checksPassed else { return false }
        // `.none` (no review configured) is fine; explicit
        // `.changesRequested` and `.reviewRequired` block.
        switch reviewDecision {
        case .changesRequested, .reviewRequired:
            return false
        case .approved, .none:
            return true
        }
    }

    /// Human-readable reason composing every failing dimension. The
    /// view renders it as a tooltip on the disabled merge button so
    /// the user can act on the specific blocker without guessing.
    var reasonIfBlocked: String? {
        guard !canMerge else { return nil }

        if isAlreadyMerged { return "Pull request is already merged." }
        if isClosed { return "Pull request is closed." }

        var reasons: [String] = []

        switch conflictStatus {
        case .conflicting:
            reasons.append("merge conflicts")
        case .unknown:
            reasons.append("conflict status unknown")
        case .mergeable:
            break
        }

        switch stateStatus {
        case .behind:
            reasons.append("branch is behind base")
        case .blocked:
            reasons.append("blocked by branch protection")
        case .dirty:
            // `dirty` typically coincides with .conflicting; only add
            // it if we have not already mentioned conflicts.
            if conflictStatus != .conflicting {
                reasons.append("dirty working state")
            }
        case .unstable:
            if checksPending {
                reasons.append("checks in progress")
            }
        case .unknown:
            if conflictStatus != .unknown {
                reasons.append("merge state unknown")
            }
        case .clean, .hasHooks:
            break
        }

        if !checksPassed && !checksPending && conflictStatus != .conflicting {
            reasons.append("failing checks")
        }

        switch reviewDecision {
        case .changesRequested:
            reasons.append("changes requested")
        case .reviewRequired:
            reasons.append("review required")
        case .approved, .none:
            break
        }

        if reasons.isEmpty {
            return "Pull request cannot be merged."
        }
        return "Blocked by: \(reasons.joined(separator: ", "))."
    }

    /// Convenience accessor for the chip color in the toolbar. Kept
    /// here (and not in the view) so the mapping is testable and the
    /// view layer stays free of business logic.
    var chipKind: ChipKind {
        if canMerge { return .ready }
        if isAlreadyMerged { return .merged }
        if isClosed { return .closed }
        if conflictStatus == .conflicting || stateStatus == .dirty { return .conflicting }
        if checksPending || stateStatus == .unstable { return .pending }
        return .blocked
    }

    enum ChipKind: String, Sendable, Equatable {
        case ready
        case pending
        case blocked
        case conflicting
        case merged
        case closed
    }
}

// MARK: - Codable for GitHubMergeability

extension GitHubMergeability: Codable {

    private enum CodingKeys: String, CodingKey {
        case pullRequestNumber = "number"
        case conflictStatus = "mergeable"
        case stateStatus = "mergeStateStatus"
        case reviewDecision
        case statusCheckRollup
        case state
        // The keys below are accepted on encode so a snapshot can
        // round-trip without losing the derived fields, but they are
        // never read off `gh` JSON because gh does not emit them.
        case checksPassed
        case checksPending
        case isAlreadyMerged
        case isClosed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.pullRequestNumber = try container.decode(Int.self, forKey: .pullRequestNumber)
        self.conflictStatus = try container.decodeIfPresent(
            GitHubMergeableStatus.self,
            forKey: .conflictStatus
        ) ?? .unknown
        self.stateStatus = try container.decodeIfPresent(
            GitHubMergeStateStatus.self,
            forKey: .stateStatus
        ) ?? .unknown
        self.reviewDecision = try container.decodeIfPresent(
            GitHubReviewDecision.self,
            forKey: .reviewDecision
        ) ?? .none

        // PR `state` is not in our struct shape but we use it to
        // derive `isAlreadyMerged` and `isClosed`. `gh pr view --json
        // state` returns "OPEN" / "CLOSED" / "MERGED".
        let prState = try container.decodeIfPresent(String.self, forKey: .state)?.uppercased()
        self.isAlreadyMerged = prState == "MERGED"
        self.isClosed = prState == "CLOSED"

        // Status check rollup: derive `checksPassed` and `checksPending`
        // from the array of entries. Empty array = passed (no checks
        // configured is not a blocker). Missing key (older `gh`) also
        // collapses to passed because we cannot prove otherwise.
        if let entries = try container.decodeIfPresent(
            [GitHubStatusCheckRollupEntry].self,
            forKey: .statusCheckRollup
        ) {
            self.checksPending = entries.contains(where: { $0.isPending })
            self.checksPassed = entries.allSatisfy { $0.isPassing || $0.isPending }
                && !entries.contains(where: { !$0.isPassing && !$0.isPending })
        } else {
            self.checksPending = false
            self.checksPassed = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pullRequestNumber, forKey: .pullRequestNumber)
        try container.encode(conflictStatus, forKey: .conflictStatus)
        try container.encode(stateStatus, forKey: .stateStatus)
        try container.encode(reviewDecision, forKey: .reviewDecision)
        try container.encode(checksPassed, forKey: .checksPassed)
        try container.encode(checksPending, forKey: .checksPending)
        try container.encode(isAlreadyMerged, forKey: .isAlreadyMerged)
        try container.encode(isClosed, forKey: .isClosed)
    }
}

// MARK: - Merge request

/// Composite payload describing a merge intention. Used by both the
/// CLI socket bridge and the in-process Code Review path so the
/// service signature stays uniform across surfaces.
struct GitHubMergeRequest: Codable, Sendable, Equatable {

    /// Pull request number to merge.
    let pullRequestNumber: Int

    /// Strategy passed to `gh pr merge`.
    let method: GitHubMergeMethod

    /// Whether `--delete-branch` is appended. Persisted in
    /// `UserDefaults` per repo so the user's last choice carries
    /// forward across sessions.
    let deleteBranch: Bool

    /// Optional override for the merge commit subject. Forwarded to
    /// `gh pr merge --subject` when present. `nil` lets `gh` build
    /// the default subject from the PR title.
    let subject: String?

    /// Optional override for the merge commit body. Forwarded to
    /// `gh pr merge --body`. `nil` lets `gh` build the default body
    /// from the PR description.
    let body: String?

    init(
        pullRequestNumber: Int,
        method: GitHubMergeMethod,
        deleteBranch: Bool = true,
        subject: String? = nil,
        body: String? = nil
    ) {
        self.pullRequestNumber = pullRequestNumber
        self.method = method
        self.deleteBranch = deleteBranch
        self.subject = subject
        self.body = body
    }
}
