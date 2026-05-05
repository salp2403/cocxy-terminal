// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PR review suggestions")
struct PRReviewSuggestionSwiftTestingTests {

    @Test("thread builder groups comments by file and line range and extracts suggestions")
    func threadBuilderGroupsCommentsAndExtractsSuggestions() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = ReviewComment(
            id: firstID,
            filePath: "Sources/App.swift",
            lineRange: 4...4,
            body: "Prefer an early return here.",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let second = ReviewComment(
            id: secondID,
            filePath: "Sources/App.swift",
            lineRange: 4...4,
            body: """
            This is the exact patch I expect:

            ```suggestion
            guard isReady else { return }
            ```
            """,
            timestamp: Date(timeIntervalSince1970: 2)
        )

        let threads = PRThreadedCommentBuilder.makeThreads(from: [second, first])

        let thread = try #require(threads.only)
        #expect(thread.filePath == "Sources/App.swift")
        #expect(thread.lineRange == 4...4)
        #expect(thread.rootComment.id == firstID)
        #expect(thread.replies.map(\.id) == [secondID])
        #expect(thread.comments.map(\.id) == [firstID, secondID])
        #expect(thread.suggestions.count == 1)
        #expect(thread.suggestions[0].replacementText == "guard isReady else { return }")
    }

    @Test("suggestion applier applies non-overlapping suggestions from bottom to top")
    func suggestionApplierAppliesNonOverlappingSuggestions() {
        let original = """
        let enabled = false
        print(enabled)
        """
        let suggestions = [
            PRSuggestion(
                filePath: "Sources/App.swift",
                lineRange: 1...1,
                replacementText: "let enabled = true",
                expectedOriginalText: "let enabled = false"
            ),
            PRSuggestion(
                filePath: "Sources/App.swift",
                lineRange: 2...2,
                replacementText: #"print("enabled:", enabled)"#,
                expectedOriginalText: "print(enabled)"
            ),
        ]

        let report = PRSuggestionApplier.apply(suggestions, to: original)

        #expect(report.conflicts.isEmpty)
        #expect(report.appliedSuggestions.map(\.lineRange) == [1...1, 2...2])
        #expect(report.updatedContent == """
        let enabled = true
        print("enabled:", enabled)
        """)
    }

    @Test("suggestion applier refuses stale originals without modifying content")
    func suggestionApplierRefusesStaleOriginals() {
        let original = "let enabled = alreadyEnabled\n"
        let suggestion = PRSuggestion(
            filePath: "Sources/App.swift",
            lineRange: 1...1,
            replacementText: "let enabled = true",
            expectedOriginalText: "let enabled = false"
        )

        let report = PRSuggestionApplier.apply([suggestion], to: original)

        #expect(report.updatedContent == original)
        #expect(report.appliedSuggestions.isEmpty)
        #expect(report.conflicts.map(\.reason) == [.staleOriginal])
        #expect(report.conflicts[0].actualText == "let enabled = alreadyEnabled")
    }

    @Test("suggestion applier reports overlapping suggestions without partial writes")
    func suggestionApplierReportsOverlapsWithoutPartialWrites() {
        let original = "a\nb\nc\n"
        let suggestions = [
            PRSuggestion(filePath: "Sources/App.swift", lineRange: 1...2, replacementText: "x"),
            PRSuggestion(filePath: "Sources/App.swift", lineRange: 2...3, replacementText: "y"),
        ]

        let report = PRSuggestionApplier.apply(suggestions, to: original)

        #expect(report.updatedContent == original)
        #expect(report.appliedSuggestions.isEmpty)
        #expect(report.conflicts.map(\.reason) == [.overlappingRanges])
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
