// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRAutoMergeOrchestrator.swift - Local safety policy for PR auto-merge.

import Foundation

enum PRAutoMergeDecision: Equatable, Sendable {
    case mergeNow(GitHubMergeRequest)
    case enableAutoMerge(GitHubMergeRequest)
    case blocked(reason: String)
}

struct PRAutoMergeOrchestrator: Sendable {
    static func decision(
        for mergeability: GitHubMergeability,
        request: GitHubMergeRequest
    ) -> PRAutoMergeDecision {
        guard mergeability.pullRequestNumber == request.pullRequestNumber else {
            return .blocked(
                reason: "Mergeability snapshot is for #\(mergeability.pullRequestNumber), but request is for #\(request.pullRequestNumber)."
            )
        }

        if mergeability.canMerge {
            return .mergeNow(request)
        }

        guard mergeability.conflictStatus == .mergeable else {
            return .blocked(reason: mergeability.reasonIfBlocked ?? "Pull request has merge conflicts.")
        }

        guard !mergeability.isAlreadyMerged, !mergeability.isClosed else {
            return .blocked(reason: mergeability.reasonIfBlocked ?? "Pull request is not open.")
        }

        switch mergeability.reviewDecision {
        case .changesRequested, .reviewRequired:
            return .blocked(reason: mergeability.reasonIfBlocked ?? "Pull request review is not approved.")
        case .approved, .none:
            break
        }

        guard mergeability.checksPassed || mergeability.checksPending else {
            return .blocked(reason: mergeability.reasonIfBlocked ?? "Required checks are failing.")
        }

        guard mergeability.stateStatus == .unstable, mergeability.checksPending else {
            return .blocked(reason: mergeability.reasonIfBlocked ?? "Pull request cannot be auto-merged safely.")
        }

        return .enableAutoMerge(request)
    }
}
