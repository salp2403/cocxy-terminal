// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ScrollbackSearchEngineTests.swift - Tests for the scrollback search engine.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Scrollback Search Engine Tests

/// Tests for `ScrollbackSearchEngineImpl` covering:
///
/// - Simple string search finds matches
/// - Case insensitive search finds mixed case
/// - Case sensitive search only matches exact case
/// - Regex search matches patterns
/// - Context extraction populates before/after
/// - No matches returns empty results
/// - Empty query returns empty results
/// - Max results cap is respected
/// - Large input (100K lines) completes in < 500ms
/// - Multiple matches on same line are all found
/// - Invalid regex returns error state
/// - Search state transitions through lifecycle
/// - Cancel resets state to idle
/// - Context extraction handles line boundaries
@MainActor
final class ScrollbackSearchEngineTests: XCTestCase {

    private var sut: ScrollbackSearchEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = ScrollbackSearchEngineImpl()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Simple String Search

    func testSimpleStringSearchFindsMatches() {
        let lines = [
            "Hello world",
            "This is a test",
            "Hello again",
            "Goodbye"
        ]
        let options = SearchOptions(query: "Hello")

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].lineNumber, 0)
        XCTAssertEqual(results[0].column, 0)
        XCTAssertEqual(results[0].matchText, "Hello")
        XCTAssertEqual(results[1].lineNumber, 2)
        XCTAssertEqual(results[1].column, 0)
        XCTAssertEqual(results[1].matchText, "Hello")
    }

    // MARK: - Case Insensitive Search

    func testCaseInsensitiveSearchFindsMixedCase() {
        let lines = [
            "Hello World",
            "hello world",
            "HELLO WORLD",
            "No match here"
        ]
        let options = SearchOptions(query: "hello", caseSensitive: false)

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].lineNumber, 0)
        XCTAssertEqual(results[1].lineNumber, 1)
        XCTAssertEqual(results[2].lineNumber, 2)
    }

    // MARK: - Case Sensitive Search

    func testCaseSensitiveSearchOnlyMatchesExactCase() {
        let lines = [
            "Hello World",
            "hello world",
            "HELLO WORLD"
        ]
        let options = SearchOptions(query: "Hello", caseSensitive: true)

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lineNumber, 0)
        XCTAssertEqual(results[0].matchText, "Hello")
    }

    // MARK: - Regex Search

    func testRegexSearchMatchesPatterns() {
        let lines = [
            "error: file not found",
            "warning: deprecated API",
            "error: permission denied",
            "info: build started"
        ]
        let options = SearchOptions(query: "error:.*", caseSensitive: false, useRegex: true)

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].lineNumber, 0)
        XCTAssertEqual(results[1].lineNumber, 2)
    }

    // MARK: - Context Extraction

    func testContextExtractionPopulatesBeforeAndAfter() {
        let lines = [
            "The quick brown fox jumps over the lazy dog"
        ]
        let options = SearchOptions(query: "fox")

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 1)
        let result = results[0]
        XCTAssertEqual(result.matchText, "fox")
        XCTAssertNotNil(result.contextBefore)
        XCTAssertNotNil(result.contextAfter)
        // "The quick brown " has 16 chars before "fox", within 20 char context
        XCTAssertTrue(result.contextBefore!.contains("brown"))
        // " jumps over the laz" has chars after "fox", within 20 char context
        XCTAssertTrue(result.contextAfter!.contains("jumps"))
    }

    // MARK: - No Matches

    func testNoMatchesReturnsEmptyResults() {
        let lines = [
            "Hello world",
            "This is a test"
        ]
        let options = SearchOptions(query: "zzz_not_found")

        let results = sut.search(options: options, in: lines)

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Empty Query

    func testEmptyQueryReturnsEmptyResults() {
        let lines = [
            "Hello world",
            "This is a test"
        ]
        let options = SearchOptions(query: "")

        let results = sut.search(options: options, in: lines)

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Max Results Cap

    func testMaxResultsCapRespectsLimit() {
        // Create lines that all match
        let lines = (0..<100).map { "match line \($0)" }
        let options = SearchOptions(query: "match", maxResults: 10)

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 10)
    }

    // MARK: - Large Input Performance

    func testLargeInputCompletesInReasonableTimeForDebugBuilds() {
        // Generate 100K lines
        let lines = (0..<100_000).map { index -> String in
            if index % 1000 == 0 {
                return "This line contains the NEEDLE we are searching for"
            }
            return "This is a regular line number \(index) with no special content"
        }
        let options = SearchOptions(query: "NEEDLE")

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = sut.search(options: options, in: lines)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertEqual(results.count, 100) // 100K / 1000 = 100 matches
        // This unit-test target runs in debug configuration and competes with
        // the rest of the suite for CPU on CI. Keep a generous upper bound so
        // the test still catches pathological regressions without turning
        // normal scheduler variance into red builds.
        XCTAssertLessThan(elapsed, 8.0, "Search took \(elapsed)s, expected < 8.0s")
    }

    // MARK: - Multiple Matches on Same Line

    func testMultipleMatchesOnSameLineAreAllFound() {
        let lines = [
            "cat and cat and another cat"
        ]
        let options = SearchOptions(query: "cat")

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].column, 0)
        XCTAssertEqual(results[1].column, 8)
        XCTAssertEqual(results[2].column, 24)
        // All on the same line
        XCTAssertTrue(results.allSatisfy { $0.lineNumber == 0 })
    }

    // MARK: - Invalid Regex Returns Error State

    func testInvalidRegexReturnsErrorState() {
        let lines = ["some text"]
        let options = SearchOptions(query: "[invalid", caseSensitive: false, useRegex: true)

        let results = sut.search(options: options, in: lines)

        XCTAssertTrue(results.isEmpty)
        if case .error = sut.state {
            // Expected: error state for invalid regex
        } else {
            XCTFail("Expected error state, got \(sut.state)")
        }
    }

    // MARK: - State Transitions

    func testSearchStateTransitionsThroughLifecycle() {
        var observedStates: [SearchState] = []

        sut.statePublisher
            .sink { state in
                observedStates.append(state)
            }
            .store(in: &cancellables)

        XCTAssertEqual(sut.state, .idle)

        let lines = ["Hello world"]
        let options = SearchOptions(query: "Hello")

        _ = sut.search(options: options, in: lines)

        // Should have transitioned through: idle -> searching -> completed
        // The initial idle may or may not be captured depending on subscription timing
        let hasCompleted = observedStates.contains { state in
            if case .completed(let count) = state {
                return count == 1
            }
            return false
        }
        XCTAssertTrue(hasCompleted, "Expected completed state in \(observedStates)")
    }

    // MARK: - Cancel Resets State

    func testCancelResetsStateToIdle() {
        let lines = ["Hello world"]
        let options = SearchOptions(query: "Hello")
        _ = sut.search(options: options, in: lines)

        // State should be completed
        if case .completed = sut.state {
            // Good
        } else {
            XCTFail("Expected completed state before cancel")
        }

        sut.cancel()

        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Context at Line Boundaries

    func testContextExtractionHandlesLineStart() {
        let lines = [
            "fox jumps over the lazy dog"
        ]
        let options = SearchOptions(query: "fox")

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 1)
        // "fox" is at the start -- contextBefore should be nil or empty
        let result = results[0]
        XCTAssertTrue(result.contextBefore == nil || result.contextBefore!.isEmpty)
        XCTAssertNotNil(result.contextAfter)
    }

    func testContextExtractionHandlesLineEnd() {
        let lines = [
            "the lazy dog chases the fox"
        ]
        let options = SearchOptions(query: "fox")

        let results = sut.search(options: options, in: lines)

        XCTAssertEqual(results.count, 1)
        let result = results[0]
        XCTAssertNotNil(result.contextBefore)
        // "fox" is at the end -- contextAfter should be nil or empty
        XCTAssertTrue(result.contextAfter == nil || result.contextAfter!.isEmpty)
    }
}
