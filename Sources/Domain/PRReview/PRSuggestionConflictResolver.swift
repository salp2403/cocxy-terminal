// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRSuggestionConflictResolver.swift - Actionable summaries for suggestion conflicts.

import Foundation

struct PRSuggestionConflictResolution: Identifiable, Equatable, Sendable {
    let id: UUID
    let filePath: String
    let lineDescription: String
    let reason: String
    let action: String
    let actualTextSnippet: String?
}

enum PRSuggestionConflictResolver {
    static func resolutions(
        for conflicts: [PRSuggestionConflict],
        using localizer: AppLocalizer
    ) -> [PRSuggestionConflictResolution] {
        conflicts.map { conflict in
            PRSuggestionConflictResolution(
                id: conflict.suggestion.id,
                filePath: conflict.suggestion.filePath,
                lineDescription: localizedLineDescription(
                    conflict.suggestion.lineRange,
                    using: localizer
                ),
                reason: localizedReason(conflict.reason, using: localizer),
                action: localizedAction(conflict.reason, using: localizer),
                actualTextSnippet: snippet(from: conflict.actualText)
            )
        }
    }

    static func localizedSummary(
        for conflicts: [PRSuggestionConflict],
        using localizer: AppLocalizer
    ) -> String {
        let resolutions = resolutions(for: conflicts, using: localizer)
        guard let first = resolutions.first else {
            return localizer.string(
                "codeReview.suggestions.conflict.none",
                fallback: "No suggestion conflicts."
            )
        }

        if resolutions.count == 1 {
            return String(
                format: localizer.string(
                    "codeReview.suggestions.conflict.summary.one",
                    fallback: "Suggestions could not be applied: %@ %@ has %@. %@"
                ),
                locale: localizer.locale,
                first.filePath,
                first.lineDescription,
                first.reason,
                first.action
            )
        }

        return String(
            format: localizer.string(
                "codeReview.suggestions.conflict.summary.many",
                fallback: "Suggestions could not be applied: %d conflicts. First: %@ %@ has %@. %@"
            ),
            locale: localizer.locale,
            resolutions.count,
            first.filePath,
            first.lineDescription,
            first.reason,
            first.action
        )
    }

    private static func localizedLineDescription(
        _ range: ClosedRange<Int>,
        using localizer: AppLocalizer
    ) -> String {
        if range.lowerBound == range.upperBound {
            return String(
                format: localizer.string(
                    "codeReview.suggestions.conflict.line",
                    fallback: "line %d"
                ),
                locale: localizer.locale,
                range.lowerBound
            )
        }

        return String(
            format: localizer.string(
                "codeReview.suggestions.conflict.lines",
                fallback: "lines %d-%d"
            ),
            locale: localizer.locale,
            range.lowerBound,
            range.upperBound
        )
    }

    private static func localizedReason(
        _ reason: PRSuggestionConflictReason,
        using localizer: AppLocalizer
    ) -> String {
        switch reason {
        case .outOfBounds:
            return localizer.string(
                "codeReview.suggestions.conflict.reason.outOfBounds",
                fallback: "an out-of-bounds range"
            )
        case .overlappingRanges:
            return localizer.string(
                "codeReview.suggestions.conflict.reason.overlappingRanges",
                fallback: "overlapping ranges"
            )
        case .staleOriginal:
            return localizer.string(
                "codeReview.suggestions.conflict.reason.staleOriginal",
                fallback: "changed original text"
            )
        }
    }

    private static func localizedAction(
        _ reason: PRSuggestionConflictReason,
        using localizer: AppLocalizer
    ) -> String {
        switch reason {
        case .outOfBounds:
            return localizer.string(
                "codeReview.suggestions.conflict.action.outOfBounds",
                fallback: "Re-anchor the comment to an existing line before applying."
            )
        case .overlappingRanges:
            return localizer.string(
                "codeReview.suggestions.conflict.action.overlappingRanges",
                fallback: "Keep one overlapping suggestion and remove the other draft."
            )
        case .staleOriginal:
            return localizer.string(
                "codeReview.suggestions.conflict.action.staleOriginal",
                fallback: "Refresh the diff or update the suggestion to match the current file."
            )
        }
    }

    private static func snippet(from actualText: String?) -> String? {
        guard let actualText else { return nil }
        let singleLine = actualText
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return nil }
        if singleLine.count <= 120 { return singleLine }
        return "\(singleLine.prefix(117))..."
    }
}
