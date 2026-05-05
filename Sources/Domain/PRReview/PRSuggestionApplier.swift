// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRSuggestionApplier.swift - Applies local PR review suggestions safely.

import Foundation

struct PRSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let filePath: String
    let lineRange: ClosedRange<Int>
    let replacementText: String
    let expectedOriginalText: String?

    init(
        id: UUID = UUID(),
        filePath: String,
        lineRange: ClosedRange<Int>,
        replacementText: String,
        expectedOriginalText: String? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.lineRange = lineRange
        self.replacementText = replacementText
        self.expectedOriginalText = expectedOriginalText
    }
}

enum PRSuggestionConflictReason: String, Equatable, Sendable {
    case outOfBounds
    case overlappingRanges
    case staleOriginal
}

struct PRSuggestionConflict: Equatable, Sendable {
    let suggestion: PRSuggestion
    let reason: PRSuggestionConflictReason
    let actualText: String?
}

struct PRSuggestionApplyReport: Equatable, Sendable {
    let originalContent: String
    let updatedContent: String
    let appliedSuggestions: [PRSuggestion]
    let conflicts: [PRSuggestionConflict]

    var hasConflicts: Bool {
        !conflicts.isEmpty
    }
}

enum PRSuggestionApplier {
    static func apply(_ suggestions: [PRSuggestion], to originalContent: String) -> PRSuggestionApplyReport {
        guard !suggestions.isEmpty else {
            return PRSuggestionApplyReport(
                originalContent: originalContent,
                updatedContent: originalContent,
                appliedSuggestions: [],
                conflicts: []
            )
        }

        var conflicts = structuralConflicts(in: suggestions, originalContent: originalContent)
        let (originalLines, trailingNewline) = editableLines(from: originalContent)

        if conflicts.isEmpty {
            conflicts = staleOriginalConflicts(
                in: suggestions,
                originalLines: originalLines
            )
        }

        guard conflicts.isEmpty else {
            return PRSuggestionApplyReport(
                originalContent: originalContent,
                updatedContent: originalContent,
                appliedSuggestions: [],
                conflicts: conflicts
            )
        }

        var lines = originalLines
        let descending = suggestions.sorted {
            if $0.lineRange.lowerBound != $1.lineRange.lowerBound {
                return $0.lineRange.lowerBound > $1.lineRange.lowerBound
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        for suggestion in descending {
            let lower = suggestion.lineRange.lowerBound - 1
            let upper = suggestion.lineRange.upperBound - 1
            lines.replaceSubrange(lower...upper, with: editableLines(from: suggestion.replacementText).lines)
        }

        return PRSuggestionApplyReport(
            originalContent: originalContent,
            updatedContent: join(lines: lines, trailingNewline: trailingNewline),
            appliedSuggestions: suggestions.sorted(by: suggestionSort),
            conflicts: []
        )
    }

    private static func structuralConflicts(
        in suggestions: [PRSuggestion],
        originalContent: String
    ) -> [PRSuggestionConflict] {
        let lineCount = editableLines(from: originalContent).lines.count
        var conflicts: [PRSuggestionConflict] = []

        for suggestion in suggestions where !isValid(suggestion.lineRange, lineCount: lineCount) {
            conflicts.append(PRSuggestionConflict(
                suggestion: suggestion,
                reason: .outOfBounds,
                actualText: nil
            ))
        }

        let validSuggestions = suggestions.filter { isValid($0.lineRange, lineCount: lineCount) }
            .sorted(by: suggestionSort)
        var previous: PRSuggestion?
        for suggestion in validSuggestions {
            if let prior = previous,
               suggestion.filePath == prior.filePath,
               suggestion.lineRange.lowerBound <= prior.lineRange.upperBound {
                conflicts.append(PRSuggestionConflict(
                    suggestion: suggestion,
                    reason: .overlappingRanges,
                    actualText: nil
                ))
            }
            previous = suggestion
        }

        return conflicts
    }

    private static func staleOriginalConflicts(
        in suggestions: [PRSuggestion],
        originalLines: [String]
    ) -> [PRSuggestionConflict] {
        suggestions.compactMap { suggestion in
            guard let expectedOriginalText = suggestion.expectedOriginalText else { return nil }

            let lower = suggestion.lineRange.lowerBound - 1
            let upper = suggestion.lineRange.upperBound - 1
            let actualLines = Array(originalLines[lower...upper])
            let expectedLines = editableLines(from: expectedOriginalText).lines
            guard actualLines != expectedLines else { return nil }

            return PRSuggestionConflict(
                suggestion: suggestion,
                reason: .staleOriginal,
                actualText: actualLines.joined(separator: "\n")
            )
        }
    }

    private static func isValid(_ range: ClosedRange<Int>, lineCount: Int) -> Bool {
        range.lowerBound >= 1
            && range.upperBound >= range.lowerBound
            && range.upperBound <= lineCount
    }

    private static func editableLines(from content: String) -> (lines: [String], trailingNewline: Bool) {
        let trailingNewline = content.hasSuffix("\n")
        var lines = content.components(separatedBy: "\n")
        if trailingNewline {
            lines.removeLast()
        }
        return (lines, trailingNewline)
    }

    private static func join(lines: [String], trailingNewline: Bool) -> String {
        lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }

    private static func suggestionSort(_ lhs: PRSuggestion, _ rhs: PRSuggestion) -> Bool {
        if lhs.filePath != rhs.filePath {
            return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
        }
        if lhs.lineRange.lowerBound != rhs.lineRange.lowerBound {
            return lhs.lineRange.lowerBound < rhs.lineRange.lowerBound
        }
        if lhs.lineRange.upperBound != rhs.lineRange.upperBound {
            return lhs.lineRange.upperBound < rhs.lineRange.upperBound
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
