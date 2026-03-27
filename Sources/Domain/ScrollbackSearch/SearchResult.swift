// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SearchResult.swift - Domain models for scrollback search.

import Foundation

// MARK: - Search Result

/// A single match found in the terminal scrollback buffer.
///
/// Each result identifies the exact position of the match (line + column),
/// the matched text, and optional surrounding context for display.
///
/// - SeeAlso: `ScrollbackSearchEngine` (produces these results)
/// - SeeAlso: `ScrollbackSearchBarViewModel` (consumes these results)
struct SearchResult: Identifiable, Equatable, Sendable {

    /// Unique identifier for this result.
    let id: UUID

    /// Zero-based line number in the scrollback buffer.
    let lineNumber: Int

    /// Zero-based column (character offset) within the line.
    let column: Int

    /// The exact text that matched the query.
    let matchText: String

    /// Up to 20 characters before the match on the same line.
    /// Nil if the match starts at column 0.
    let contextBefore: String?

    /// Up to 20 characters after the match on the same line.
    /// Nil if the match ends at the end of the line.
    let contextAfter: String?
}

// MARK: - Search Options

/// Configuration for a scrollback search operation.
///
/// Immutable value type. Create a new instance to change options.
struct SearchOptions: Equatable, Sendable {

    /// The search query string (plain text or regex pattern).
    let query: String

    /// Whether the search is case-sensitive.
    /// When false, "Hello" matches "hello", "HELLO", etc.
    let caseSensitive: Bool

    /// Whether the query should be interpreted as a regular expression.
    /// When false, the query is treated as a literal string.
    let useRegex: Bool

    /// Maximum number of results to return.
    /// Prevents UI overload on very large scrollback buffers.
    let maxResults: Int

    init(
        query: String,
        caseSensitive: Bool = false,
        useRegex: Bool = false,
        maxResults: Int = 500
    ) {
        self.query = query
        self.caseSensitive = caseSensitive
        self.useRegex = useRegex
        self.maxResults = maxResults
    }
}

// MARK: - Search State

/// Represents the current state of a search operation.
///
/// Published via Combine to enable reactive UI updates.
enum SearchState: Equatable, Sendable {

    /// No search in progress.
    case idle

    /// Search is running. Progress is 0.0 to 1.0.
    case searching(progress: Double)

    /// Search completed successfully with the given number of results.
    case completed(resultCount: Int)

    /// Search failed with the given error message.
    case error(String)
}
