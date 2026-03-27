// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SearchBarViewModelTests.swift - Tests for the scrollback search bar ViewModel.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Search Bar ViewModel Tests

/// Tests for `ScrollbackSearchBarViewModel` covering:
///
/// - Initial state is idle with empty query
/// - Navigate next increments current match index
/// - Navigate next wraps at end of results
/// - Navigate prev wraps at beginning of results
/// - Update query triggers search and resets index
/// - Toggle case sensitivity re-triggers search
/// - Toggle regex mode re-triggers search
/// - Close resets all state
/// - Result count display string format
@MainActor
final class SearchBarViewModelTests: XCTestCase {

    private var sut: ScrollbackSearchBarViewModel!
    private var mockEngine: MockScrollbackSearchEngine!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockEngine = MockScrollbackSearchEngine()
        sut = ScrollbackSearchBarViewModel(searchEngine: mockEngine)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockEngine = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdleWithEmptyQuery() {
        XCTAssertEqual(sut.query, "")
        XCTAssertEqual(sut.currentMatchIndex, 0)
        XCTAssertEqual(sut.totalMatches, 0)
        XCTAssertFalse(sut.caseSensitive)
        XCTAssertFalse(sut.useRegex)
    }

    // MARK: - Navigate Next

    func testNavigateNextIncrementsCurrentMatchIndex() {
        // Set up mock results
        mockEngine.mockResults = makeSearchResults(count: 5)
        sut.performSearch(in: makeSampleLines())

        XCTAssertEqual(sut.currentMatchIndex, 0)
        XCTAssertEqual(sut.totalMatches, 5)

        sut.navigateNext()

        XCTAssertEqual(sut.currentMatchIndex, 1)
    }

    // MARK: - Navigate Next Wraps

    func testNavigateNextWrapsAtEnd() {
        mockEngine.mockResults = makeSearchResults(count: 3)
        sut.performSearch(in: makeSampleLines())

        // Move to last result
        sut.navigateNext() // index = 1
        sut.navigateNext() // index = 2

        XCTAssertEqual(sut.currentMatchIndex, 2)

        // Next should wrap to 0
        sut.navigateNext()
        XCTAssertEqual(sut.currentMatchIndex, 0)
    }

    // MARK: - Navigate Prev Wraps

    func testNavigatePrevWrapsAtBeginning() {
        mockEngine.mockResults = makeSearchResults(count: 3)
        sut.performSearch(in: makeSampleLines())

        XCTAssertEqual(sut.currentMatchIndex, 0)

        // Prev should wrap to last (index 2)
        sut.navigatePrev()
        XCTAssertEqual(sut.currentMatchIndex, 2)
    }

    // MARK: - Update Query Triggers Search

    func testUpdateQueryTriggersSearchAndResetsIndex() {
        mockEngine.mockResults = makeSearchResults(count: 5)
        sut.performSearch(in: makeSampleLines())

        // Move forward
        sut.navigateNext()
        sut.navigateNext()
        XCTAssertEqual(sut.currentMatchIndex, 2)

        // Change query should reset index
        mockEngine.mockResults = makeSearchResults(count: 2)
        sut.query = "new query"
        sut.performSearch(in: makeSampleLines())

        XCTAssertEqual(sut.currentMatchIndex, 0)
        XCTAssertEqual(sut.totalMatches, 2)
    }

    // MARK: - Toggle Case Sensitivity

    func testToggleCaseSensitivityRetriggersSearch() {
        mockEngine.mockResults = makeSearchResults(count: 3)
        sut.query = "test"
        sut.performSearch(in: makeSampleLines())
        XCTAssertEqual(mockEngine.searchCallCount, 1)

        // Toggle case sensitivity and search again
        sut.caseSensitive = true
        sut.performSearch(in: makeSampleLines())

        XCTAssertEqual(mockEngine.searchCallCount, 2)
        // Verify the options passed to the engine
        XCTAssertTrue(mockEngine.lastSearchOptions?.caseSensitive ?? false)
    }

    // MARK: - Toggle Regex Mode

    func testToggleRegexModeRetriggersSearch() {
        mockEngine.mockResults = makeSearchResults(count: 3)
        sut.query = "test"
        sut.performSearch(in: makeSampleLines())
        XCTAssertEqual(mockEngine.searchCallCount, 1)

        // Toggle regex and search again
        sut.useRegex = true
        sut.performSearch(in: makeSampleLines())

        XCTAssertEqual(mockEngine.searchCallCount, 2)
        XCTAssertTrue(mockEngine.lastSearchOptions?.useRegex ?? false)
    }

    // MARK: - Close Resets State

    func testCloseResetsAllState() {
        mockEngine.mockResults = makeSearchResults(count: 5)
        sut.query = "test"
        sut.performSearch(in: makeSampleLines())
        sut.navigateNext()
        sut.navigateNext()

        XCTAssertEqual(sut.currentMatchIndex, 2)
        XCTAssertEqual(sut.totalMatches, 5)

        sut.close()

        XCTAssertEqual(sut.query, "")
        XCTAssertEqual(sut.currentMatchIndex, 0)
        XCTAssertEqual(sut.totalMatches, 0)
    }

    // MARK: - Result Count Display

    func testResultCountDisplayStringFormat() {
        mockEngine.mockResults = makeSearchResults(count: 47)
        sut.performSearch(in: makeSampleLines())

        // Navigate to 3rd match (index 2)
        sut.navigateNext() // 1
        sut.navigateNext() // 2

        XCTAssertEqual(sut.resultCountDisplay, "3 of 47 matches")
    }

    func testResultCountDisplayWhenNoResults() {
        mockEngine.mockResults = []
        sut.query = "nope"
        sut.performSearch(in: makeSampleLines())

        XCTAssertEqual(sut.resultCountDisplay, "No matches")
    }

    // MARK: - Navigate With No Results

    func testNavigateNextWithNoResultsDoesNotCrash() {
        mockEngine.mockResults = []
        sut.performSearch(in: makeSampleLines())

        // Should not crash or change index
        sut.navigateNext()
        XCTAssertEqual(sut.currentMatchIndex, 0)
    }

    func testNavigatePrevWithNoResultsDoesNotCrash() {
        mockEngine.mockResults = []
        sut.performSearch(in: makeSampleLines())

        // Should not crash or change index
        sut.navigatePrev()
        XCTAssertEqual(sut.currentMatchIndex, 0)
    }

    // MARK: - Helpers

    private func makeSearchResults(count: Int) -> [SearchResult] {
        (0..<count).map { index in
            SearchResult(
                id: UUID(),
                lineNumber: index,
                column: 0,
                matchText: "match",
                contextBefore: "before",
                contextAfter: "after"
            )
        }
    }

    private func makeSampleLines() -> [String] {
        ["line 1", "line 2", "line 3", "line 4", "line 5"]
    }
}

// MARK: - Mock Search Engine

/// Mock implementation of `ScrollbackSearching` for testing the ViewModel.
@MainActor
final class MockScrollbackSearchEngine: ScrollbackSearching {
    var mockResults: [SearchResult] = []
    var searchCallCount = 0
    var lastSearchOptions: SearchOptions?

    private let stateSubject = CurrentValueSubject<SearchState, Never>(.idle)

    var state: SearchState {
        stateSubject.value
    }

    var statePublisher: AnyPublisher<SearchState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    func search(options: SearchOptions, in lines: [String]) -> [SearchResult] {
        searchCallCount += 1
        lastSearchOptions = options
        stateSubject.send(.completed(resultCount: mockResults.count))
        return mockResults
    }

    func searchAsync(options: SearchOptions, in lines: [String]) async -> [SearchResult] {
        search(options: options, in: lines)
    }

    func cancel() {
        stateSubject.send(.idle)
    }
}
