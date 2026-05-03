// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionRanking.swift - Deterministic local ranking for inline completions.

import Foundation

struct CompletionRanking: Sendable {
    func bestSuggestion(
        from suggestions: [InlineCompletion],
        context: CompletionContext
    ) -> InlineCompletion? {
        let caret = context.caretRange.location
        return suggestions
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let lhsScore = score(lhs, caret: caret)
                let rhsScore = score(rhs, caret: caret)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if lhs.text.count != rhs.text.count { return lhs.text.count < rhs.text.count }
                return lhs.text < rhs.text
            }
            .first
    }

    private func score(_ completion: InlineCompletion, caret: Int) -> Int {
        var score = 0
        if completion.replacementRange.location == caret {
            score += 100
        }
        if completion.replacementRange.isCaret {
            score += 25
        }
        if completion.source == .foundationModelsOnDevice {
            score += 10
        }
        return score
    }
}
