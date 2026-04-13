// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownWordCount.swift - Word, character, and line counting for markdown documents.

import Foundation

// MARK: - Word Count

/// Counts words, characters, and lines in a markdown document's body text.
///
/// Frontmatter is excluded from the count because it is metadata, not content.
/// Code blocks are included because they contribute to the document's substance.
public struct MarkdownWordCount: Equatable, Sendable {

    /// Number of whitespace-delimited words in the body.
    public let words: Int

    /// Number of characters in the body (excluding leading/trailing whitespace).
    public let characters: Int

    /// Number of lines in the body (empty body = 0, non-empty = at least 1).
    public let lines: Int

    /// An empty count with all values at zero.
    public static let zero = MarkdownWordCount(words: 0, characters: 0, lines: 0)

    /// Computes word count statistics from a markdown document's body.
    ///
    /// Uses the body (frontmatter excluded) as the input. Splits on
    /// Unicode whitespace boundaries for accurate word counting across
    /// languages and scripts.
    ///
    /// - Parameter body: The body text of the markdown document (after frontmatter extraction).
    /// - Returns: A `MarkdownWordCount` with word, character, and line counts.
    public static func count(body: String) -> MarkdownWordCount {
        guard !body.isEmpty else { return .zero }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .zero }

        let characters = trimmed.count

        let words = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        let lines = body.components(separatedBy: .newlines).count

        return MarkdownWordCount(words: words, characters: characters, lines: lines)
    }
}
