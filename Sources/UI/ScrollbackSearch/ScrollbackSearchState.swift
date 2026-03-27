// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ScrollbackSearchState.swift - ViewModel for the scrollback search bar.

import Foundation
import Combine

// MARK: - Scrollback Search Bar ViewModel

/// ViewModel that drives the inline scrollback search bar.
///
/// Manages search query, options, result navigation, and display state.
/// Delegates actual search execution to a `ScrollbackSearching` engine.
///
/// ## Navigation
///
/// Results are navigated with next/prev which wrap around at boundaries:
/// - Next from last result -> first result
/// - Prev from first result -> last result
///
/// ## Display
///
/// Provides `resultCountDisplay` formatted as:
/// - "3 of 47 matches" (when results exist)
/// - "No matches" (when query has no matches)
///
/// - SeeAlso: `ScrollbackSearchBarView` (drives this ViewModel)
/// - SeeAlso: `ScrollbackSearching` (search engine protocol)
@MainActor
final class ScrollbackSearchBarViewModel: ObservableObject {

    // MARK: - Published Properties

    /// The current search query text.
    @Published var query: String = ""

    /// Whether the search is case-sensitive.
    @Published var caseSensitive: Bool = false

    /// Whether the query is interpreted as a regular expression.
    @Published var useRegex: Bool = false

    /// Zero-based index of the currently highlighted match.
    private(set) var currentMatchIndex: Int = 0

    /// Total number of matches found.
    private(set) var totalMatches: Int = 0

    /// The current search results.
    private(set) var results: [SearchResult] = []

    // MARK: - Dependencies

    /// The search engine used to execute queries.
    private let searchEngine: ScrollbackSearching

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a search bar ViewModel with the given search engine.
    ///
    /// - Parameter searchEngine: The engine to use for searches.
    ///   Defaults to `ScrollbackSearchEngineImpl()` in production.
    init(searchEngine: ScrollbackSearching? = nil) {
        self.searchEngine = searchEngine ?? ScrollbackSearchEngineImpl()
    }

    // MARK: - Search Execution

    /// Executes a search with the current options against the given lines.
    ///
    /// Resets the match index to 0 on each new search.
    ///
    /// - Parameter lines: The scrollback buffer content to search through.
    func performSearch(in lines: [String]) {
        let options = SearchOptions(
            query: query,
            caseSensitive: caseSensitive,
            useRegex: useRegex
        )

        results = searchEngine.search(options: options, in: lines)
        totalMatches = results.count
        currentMatchIndex = 0
    }

    // MARK: - Navigation

    /// Moves to the next match result. Wraps from last to first.
    func navigateNext() {
        guard totalMatches > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % totalMatches
    }

    /// Moves to the previous match result. Wraps from first to last.
    func navigatePrev() {
        guard totalMatches > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + totalMatches) % totalMatches
    }

    // MARK: - Display

    /// Formatted string showing "X of Y matches" or "No matches".
    var resultCountDisplay: String {
        guard totalMatches > 0 else {
            return "No matches"
        }
        return "\(currentMatchIndex + 1) of \(totalMatches) matches"
    }

    /// The currently highlighted search result, if any.
    var currentResult: SearchResult? {
        guard totalMatches > 0, currentMatchIndex < results.count else {
            return nil
        }
        return results[currentMatchIndex]
    }

    // MARK: - Close / Reset

    /// Resets all search state. Called when the user dismisses the search bar.
    func close() {
        query = ""
        caseSensitive = false
        useRegex = false
        results = []
        totalMatches = 0
        currentMatchIndex = 0
        searchEngine.cancel()
    }
}
