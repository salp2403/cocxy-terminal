// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ScrollbackSearchEngine.swift - Search engine for terminal scrollback buffer.

import Foundation
import Combine

// MARK: - Scrollback Searching Protocol

/// Contract for searching through terminal scrollback buffer content.
///
/// Implementations must support:
/// - Plain text search (case-sensitive and case-insensitive)
/// - Regular expression search
/// - Context extraction around matches
/// - Cancellation support
/// - State publishing via Combine
///
/// - SeeAlso: `ScrollbackSearchEngineImpl` (concrete implementation)
/// - SeeAlso: `SearchOptions` (search configuration)
/// - SeeAlso: `SearchResult` (individual match)
@MainActor protocol ScrollbackSearching: AnyObject {

    /// Performs a synchronous search through the given lines.
    ///
    /// - Parameters:
    ///   - options: Search configuration (query, case sensitivity, regex, max results).
    ///   - lines: The scrollback buffer content as an array of strings.
    /// - Returns: Array of search results, capped at `options.maxResults`.
    func search(options: SearchOptions, in lines: [String]) -> [SearchResult]

    /// Performs an asynchronous search through the given lines.
    ///
    /// Useful for large scrollback buffers to avoid blocking the main thread.
    ///
    /// - Parameters:
    ///   - options: Search configuration.
    ///   - lines: The scrollback buffer content.
    /// - Returns: Array of search results.
    func searchAsync(options: SearchOptions, in lines: [String]) async -> [SearchResult]

    /// The current state of the search engine.
    var state: SearchState { get }

    /// Publisher that emits state changes.
    var statePublisher: AnyPublisher<SearchState, Never> { get }

    /// Cancels any in-progress search and resets state to idle.
    func cancel()
}

// MARK: - Scrollback Search Engine Implementation

/// Concrete implementation of `ScrollbackSearching`.
///
/// Supports plain text search (case-sensitive/insensitive) and regex search
/// via `NSRegularExpression`. Extracts up to 20 characters of context before
/// and after each match.
///
/// ## Performance
///
/// Designed to handle 100K lines in under 500ms. Uses early termination
/// when `maxResults` is reached.
///
/// ## State Management
///
/// State transitions: idle -> searching -> completed/error
/// Cancel resets to idle at any point.
///
/// - SeeAlso: `ScrollbackSearching` protocol
/// - SeeAlso: ADR-008 Section 5.4 (Scrollback Search)
@MainActor
final class ScrollbackSearchEngineImpl: ScrollbackSearching {

    // MARK: - Constants

    /// Number of characters of context to extract before/after a match.
    private nonisolated static let contextCharacterCount = 20

    // MARK: - State

    private let stateSubject = CurrentValueSubject<SearchState, Never>(.idle)

    var state: SearchState {
        stateSubject.value
    }

    var statePublisher: AnyPublisher<SearchState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // MARK: - Search (Synchronous)

    func search(options: SearchOptions, in lines: [String]) -> [SearchResult] {
        // Empty query produces no results.
        guard !options.query.isEmpty else {
            stateSubject.send(.completed(resultCount: 0))
            return []
        }

        stateSubject.send(.searching(progress: 0.0))

        if options.useRegex {
            return searchWithRegex(options: options, in: lines)
        } else {
            return searchWithPlainText(options: options, in: lines)
        }
    }

    // MARK: - Search (Asynchronous)

    /// Performs search on a background thread to avoid blocking the main thread
    /// on large scrollback buffers. State notifications (searching/completed)
    /// are dispatched back to MainActor.
    func searchAsync(options: SearchOptions, in lines: [String]) async -> [SearchResult] {
        guard !options.query.isEmpty else {
            stateSubject.send(.completed(resultCount: 0))
            return []
        }
        stateSubject.send(.searching(progress: 0.0))

        let opts = options
        let linesCopy = lines

        let results: [SearchResult] = await Task.detached(priority: .userInitiated) {
            Self.performSearch(options: opts, in: linesCopy)
        }.value

        stateSubject.send(.completed(resultCount: results.count))
        return results
    }

    // MARK: - Private: Thread-safe Search (no state mutation)

    /// Pure search logic without state side-effects.
    /// Safe to call from any thread.
    private nonisolated static func performSearch(
        options: SearchOptions, in lines: [String]
    ) -> [SearchResult] {
        if options.useRegex {
            return performRegexSearch(options: options, in: lines)
        } else {
            return performPlainTextSearch(options: options, in: lines)
        }
    }

    private nonisolated static func performPlainTextSearch(
        options: SearchOptions, in lines: [String]
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        let comparison: String.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]

        for (lineIndex, line) in lines.enumerated() {
            if results.count >= options.maxResults { break }
            var cursor = line.startIndex
            while cursor < line.endIndex {
                guard let range = line.range(
                    of: options.query, options: comparison,
                    range: cursor..<line.endIndex
                ) else { break }

                let column = line.distance(from: line.startIndex, to: range.lowerBound)
                let (before, after) = extractContextStatic(from: line, matchRange: range)
                results.append(SearchResult(
                    id: UUID(), lineNumber: lineIndex, column: column,
                    matchText: String(line[range]),
                    contextBefore: before, contextAfter: after
                ))
                if results.count >= options.maxResults { break }
                cursor = range.upperBound
            }
        }
        return results
    }

    private nonisolated static func performRegexSearch(
        options: SearchOptions, in lines: [String]
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(
            pattern: options.query, options: regexOptions
        ) else { return [] }

        for (lineIndex, line) in lines.enumerated() {
            if results.count >= options.maxResults { break }
            let nsRange = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: nsRange)
            for match in matches {
                guard let range = Range(match.range, in: line) else { continue }
                let column = line.distance(from: line.startIndex, to: range.lowerBound)
                let (before, after) = extractContextStatic(from: line, matchRange: range)
                results.append(SearchResult(
                    id: UUID(), lineNumber: lineIndex, column: column,
                    matchText: String(line[range]),
                    contextBefore: before, contextAfter: after
                ))
                if results.count >= options.maxResults { break }
            }
        }
        return results
    }

    private nonisolated static func extractContextStatic(
        from line: String,
        matchRange: Range<String.Index>
    ) -> (before: String?, after: String?) {
        let contextSize = contextCharacterCount
        let beforeText: String?
        if matchRange.lowerBound > line.startIndex {
            let start = line.index(
                matchRange.lowerBound, offsetBy: -contextSize,
                limitedBy: line.startIndex
            ) ?? line.startIndex
            let s = String(line[start..<matchRange.lowerBound])
            beforeText = s.isEmpty ? nil : s
        } else {
            beforeText = nil
        }
        let afterText: String?
        if matchRange.upperBound < line.endIndex {
            let end = line.index(
                matchRange.upperBound, offsetBy: contextSize,
                limitedBy: line.endIndex
            ) ?? line.endIndex
            let s = String(line[matchRange.upperBound..<end])
            afterText = s.isEmpty ? nil : s
        } else {
            afterText = nil
        }
        return (beforeText, afterText)
    }

    // MARK: - Cancel

    func cancel() {
        stateSubject.send(.idle)
    }

    // MARK: - Private: Plain Text Search

    private func searchWithPlainText(
        options: SearchOptions,
        in lines: [String]
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        let comparisonOptions: String.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]
        let totalLines = lines.count

        for (lineIndex, line) in lines.enumerated() {
            if results.count >= options.maxResults { break }

            var searchStartIndex = line.startIndex
            while searchStartIndex < line.endIndex {
                guard let range = line.range(
                    of: options.query,
                    options: comparisonOptions,
                    range: searchStartIndex..<line.endIndex
                ) else {
                    break
                }

                let column = line.distance(from: line.startIndex, to: range.lowerBound)
                let matchText = String(line[range])
                let context = extractContext(
                    from: line,
                    matchRange: range
                )

                let result = SearchResult(
                    id: UUID(),
                    lineNumber: lineIndex,
                    column: column,
                    matchText: matchText,
                    contextBefore: context.before,
                    contextAfter: context.after
                )
                results.append(result)

                if results.count >= options.maxResults { break }

                // Move past this match to find next one on same line.
                searchStartIndex = range.upperBound
            }

            // Report progress periodically (every 10K lines).
            if lineIndex > 0, lineIndex % 10_000 == 0 {
                let progress = Double(lineIndex) / Double(totalLines)
                stateSubject.send(.searching(progress: progress))
            }
        }

        stateSubject.send(.completed(resultCount: results.count))
        return results
    }

    // MARK: - Private: Regex Search

    private func searchWithRegex(
        options: SearchOptions,
        in lines: [String]
    ) -> [SearchResult] {
        var regexOptions: NSRegularExpression.Options = []
        if !options.caseSensitive {
            regexOptions.insert(.caseInsensitive)
        }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: options.query, options: regexOptions)
        } catch {
            stateSubject.send(.error("Invalid regex: \(error.localizedDescription)"))
            return []
        }

        var results: [SearchResult] = []
        let totalLines = lines.count

        for (lineIndex, line) in lines.enumerated() {
            if results.count >= options.maxResults { break }

            let nsRange = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: nsRange)

            for match in matches {
                if results.count >= options.maxResults { break }

                guard let swiftRange = Range(match.range, in: line) else { continue }

                let column = line.distance(from: line.startIndex, to: swiftRange.lowerBound)
                let matchText = String(line[swiftRange])
                let context = extractContext(from: line, matchRange: swiftRange)

                let result = SearchResult(
                    id: UUID(),
                    lineNumber: lineIndex,
                    column: column,
                    matchText: matchText,
                    contextBefore: context.before,
                    contextAfter: context.after
                )
                results.append(result)
            }

            // Report progress periodically.
            if lineIndex > 0, lineIndex % 10_000 == 0 {
                let progress = Double(lineIndex) / Double(totalLines)
                stateSubject.send(.searching(progress: progress))
            }
        }

        stateSubject.send(.completed(resultCount: results.count))
        return results
    }

    // MARK: - Private: Context Extraction

    /// Extracts up to 20 characters of context before and after a match.
    ///
    /// Returns nil for before-context if the match starts at column 0,
    /// and nil for after-context if the match ends at the end of the line.
    private func extractContext(
        from line: String,
        matchRange: Range<String.Index>
    ) -> (before: String?, after: String?) {
        let contextSize = Self.contextCharacterCount

        // Before context
        let beforeText: String?
        if matchRange.lowerBound > line.startIndex {
            let beforeStart = line.index(
                matchRange.lowerBound,
                offsetBy: -contextSize,
                limitedBy: line.startIndex
            ) ?? line.startIndex
            let beforeString = String(line[beforeStart..<matchRange.lowerBound])
            beforeText = beforeString.isEmpty ? nil : beforeString
        } else {
            beforeText = nil
        }

        // After context
        let afterText: String?
        if matchRange.upperBound < line.endIndex {
            let afterEnd = line.index(
                matchRange.upperBound,
                offsetBy: contextSize,
                limitedBy: line.endIndex
            ) ?? line.endIndex
            let afterString = String(line[matchRange.upperBound..<afterEnd])
            afterText = afterString.isEmpty ? nil : afterString
        } else {
            afterText = nil
        }

        return (before: beforeText, after: afterText)
    }
}
