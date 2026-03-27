// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FuzzyMatcher.swift - Fuzzy string matching for Command Palette search.

import Foundation

// MARK: - Fuzzy Match Result

/// The result of a fuzzy match operation.
///
/// Contains the relevance score and the ranges of matched characters
/// in the target string (useful for highlighting in the UI).
struct FuzzyMatchResult: Sendable {
    /// Relevance score from 0 (weakest match) to 100 (exact match).
    let score: Int

    /// The ranges of characters in the target that matched the query.
    ///
    /// Used by the UI to highlight matched characters in bold.
    let matchedRanges: [Range<String.Index>]
}

// MARK: - Fuzzy Matcher

/// Pure-function fuzzy matching engine for the command palette.
///
/// Scoring strategy (ADR-008 Section 3.3):
/// 1. Exact match (case-insensitive): score 100.
/// 2. Prefix match: score 80 + (matched length / target length) * 20.
/// 3. Word boundary match (initials): bonus points for matching at word starts.
/// 4. Subsequence match: base score from matched ratio, with bonuses for
///    consecutive characters and word boundaries.
///
/// The matcher is case-insensitive. An empty query matches everything with score 0.
///
/// - SeeAlso: ADR-008 Section 3.3 (fuzzy search scoring)
enum FuzzyMatcher {

    /// Performs a fuzzy match of `query` against `target`.
    ///
    /// - Parameters:
    ///   - query: The search string entered by the user.
    ///   - target: The command name to match against.
    /// - Returns: A `FuzzyMatchResult` if the query matches, or `nil` if no match.
    static func fuzzyMatch(query: String, target: String) -> FuzzyMatchResult? {
        // Empty query matches everything with score 0.
        if query.isEmpty {
            return FuzzyMatchResult(score: 0, matchedRanges: [])
        }

        // Non-empty query against empty target is no match.
        if target.isEmpty {
            return nil
        }

        let lowerQuery = query.lowercased()
        let lowerTarget = target.lowercased()

        // Exact match (case-insensitive).
        if lowerQuery == lowerTarget {
            let fullRange = target.startIndex..<target.endIndex
            return FuzzyMatchResult(score: 100, matchedRanges: [fullRange])
        }

        // Prefix match.
        if lowerTarget.hasPrefix(lowerQuery) {
            let matchEnd = target.index(target.startIndex, offsetBy: query.count)
            let matchRange = target.startIndex..<matchEnd
            let lengthRatio = Double(query.count) / Double(target.count)
            let score = 80 + Int(lengthRatio * 20.0)
            return FuzzyMatchResult(score: score, matchedRanges: [matchRange])
        }

        // Subsequence match with scoring.
        return subsequenceMatch(query: lowerQuery, target: lowerTarget, originalTarget: target)
    }

    // MARK: - Private

    /// Performs subsequence matching with scoring bonuses for word boundaries
    /// and consecutive characters.
    private static func subsequenceMatch(
        query: String,
        target: String,
        originalTarget: String
    ) -> FuzzyMatchResult? {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var matchedIndices: [String.Index] = []
        var consecutiveCount = 0
        var totalConsecutiveBonus = 0
        var wordBoundaryBonus = 0
        var previousMatchIndex: String.Index?

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                matchedIndices.append(targetIndex)

                // Consecutive bonus: characters matched in a row score higher.
                if let prevIndex = previousMatchIndex,
                   target.index(after: prevIndex) == targetIndex {
                    consecutiveCount += 1
                    totalConsecutiveBonus += consecutiveCount * 3
                } else {
                    consecutiveCount = 0
                }

                // Word boundary bonus: matching at the start of a word scores higher.
                if isWordBoundary(index: targetIndex, in: target) {
                    wordBoundaryBonus += 10
                }

                previousMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }

            targetIndex = target.index(after: targetIndex)
        }

        // If we did not consume the entire query, it is not a match.
        guard queryIndex == query.endIndex else {
            return nil
        }

        // Calculate base score from match ratio.
        let matchRatio = Double(matchedIndices.count) / Double(target.count)
        let baseScore = Int(matchRatio * 50.0)
        let score = min(79, baseScore + totalConsecutiveBonus + wordBoundaryBonus)

        // Build matched ranges from matched indices in the original target.
        let matchedRanges = buildRanges(from: matchedIndices, in: originalTarget)

        return FuzzyMatchResult(score: score, matchedRanges: matchedRanges)
    }

    /// Returns true if the character at `index` is at a word boundary.
    ///
    /// A word boundary is defined as:
    /// - The first character of the string.
    /// - A character preceded by a space, hyphen, or underscore.
    /// - An uppercase letter preceded by a lowercase letter (camelCase boundary).
    private static func isWordBoundary(index: String.Index, in text: String) -> Bool {
        if index == text.startIndex {
            return true
        }
        let previousIndex = text.index(before: index)
        let previousChar = text[previousIndex]
        let currentChar = text[index]

        // Space, hyphen, or underscore boundary.
        if previousChar == " " || previousChar == "-" || previousChar == "_" {
            return true
        }

        // CamelCase boundary.
        if previousChar.isLowercase && currentChar.isUppercase {
            return true
        }

        return false
    }

    /// Converts a list of individual matched indices into contiguous ranges.
    private static func buildRanges(
        from indices: [String.Index],
        in text: String
    ) -> [Range<String.Index>] {
        guard !indices.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var rangeStart = indices[0]
        var rangeEnd = text.index(after: indices[0])

        for i in 1..<indices.count {
            if indices[i] == rangeEnd {
                // Consecutive: extend the current range.
                rangeEnd = text.index(after: indices[i])
            } else {
                // Non-consecutive: close current range, start new one.
                ranges.append(rangeStart..<rangeEnd)
                rangeStart = indices[i]
                rangeEnd = text.index(after: indices[i])
            }
        }
        ranges.append(rangeStart..<rangeEnd)

        return ranges
    }
}
