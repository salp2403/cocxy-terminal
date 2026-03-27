// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SearchBufferConnectionTests.swift - Tests for search bar + buffer integration.

import XCTest
@testable import CocxyTerminal

// MARK: - Search Buffer Connection Tests

/// Tests that `ScrollbackSearchBarViewModel.performSearch` works with
/// `TerminalOutputBuffer` lines as input.
///
/// This validates the integration between the output buffer and the
/// search engine without requiring a live terminal.
@MainActor
final class SearchBufferConnectionTests: XCTestCase {

    func testSearchFindsMatchesInBufferLines() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)
        buffer.append("error: file not found\n".data(using: .utf8)!)
        buffer.append("warning: deprecated API\n".data(using: .utf8)!)
        buffer.append("error: permission denied\n".data(using: .utf8)!)

        let viewModel = ScrollbackSearchBarViewModel()
        viewModel.query = "error"
        viewModel.performSearch(in: buffer.lines)

        XCTAssertEqual(viewModel.totalMatches, 2,
                       "Search should find 2 error lines in the buffer")
    }

    func testSearchInEmptyBufferReturnsNoResults() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        let viewModel = ScrollbackSearchBarViewModel()
        viewModel.query = "anything"
        viewModel.performSearch(in: buffer.lines)

        XCTAssertEqual(viewModel.totalMatches, 0)
    }

    func testSearchAfterClearReturnsNoResults() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)
        buffer.append("match this\n".data(using: .utf8)!)
        buffer.clear()

        let viewModel = ScrollbackSearchBarViewModel()
        viewModel.query = "match"
        viewModel.performSearch(in: buffer.lines)

        XCTAssertEqual(viewModel.totalMatches, 0)
    }
}
