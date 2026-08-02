// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Scrollback search validation")
@MainActor
struct ScrollbackSearchValidationSwiftTestingTests {
    @Test("invalid regex is surfaced before any search engine runs")
    func invalidRegexStopsSearch() {
        let engine = MockScrollbackSearchEngine()
        let viewModel = ScrollbackSearchBarViewModel(searchEngine: engine)
        viewModel.query = "[invalid"
        viewModel.useRegex = true

        viewModel.performSearch(in: ["[invalid"])

        #expect(viewModel.hasInvalidRegularExpression)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.totalMatches == 0)
        #expect(engine.searchCallCount == 0)
    }

    @Test("fixing the pattern clears the error and resumes search")
    func validRegexResumesSearch() {
        let engine = MockScrollbackSearchEngine()
        engine.mockResults = [SearchResult(
            id: UUID(),
            lineNumber: 0,
            column: 0,
            matchText: "valid",
            contextBefore: nil,
            contextAfter: nil
        )]
        let viewModel = ScrollbackSearchBarViewModel(searchEngine: engine)
        viewModel.query = "[invalid"
        viewModel.useRegex = true
        viewModel.performSearch(in: ["valid"])

        viewModel.query = "valid"
        viewModel.performSearch(in: ["valid"])

        #expect(!viewModel.hasInvalidRegularExpression)
        #expect(viewModel.totalMatches == 1)
        #expect(engine.searchCallCount == 1)
    }
}
