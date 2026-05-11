// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewModels.swift - Shared value types for the agent code review panel.

import Foundation

// MARK: - Review Round

struct ReviewRound: Identifiable, Sendable, Equatable {
    let id: Int
    let timestamp: Date
    let baseRef: String
    let diffs: [FileDiff]
    let comments: [ReviewComment]
}

// MARK: - Diff Mode

enum DiffMode: String, CaseIterable, Sendable {
    case uncommitted
    case sinceSessionStart
    case vsBranch

    var title: String {
        switch self {
        case .uncommitted: return "Working Tree"
        case .sinceSessionStart: return "Agent Session"
        case .vsBranch: return "Reference"
        }
    }

    func localizedTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .uncommitted:
            return localizer.string(
                "codeReview.diffMode.uncommitted",
                fallback: title
            )
        case .sinceSessionStart:
            return localizer.string(
                "codeReview.diffMode.sinceSessionStart",
                fallback: title
            )
        case .vsBranch:
            return localizer.string(
                "codeReview.diffMode.vsBranch",
                fallback: title
            )
        }
    }
}
