// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PR reviewer suggester")
struct PRReviewerSuggesterSwiftTestingTests {

    @Test("suggestions rank authors by blamed lines and touched files")
    func suggestionsRankAuthorsByBlamedLinesAndTouchedFiles() {
        let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let blameByPath = [
            "Sources/App.swift": """
            aaaaaaaa 1 1 1
            author Alice Rivera
            author-mail <alice@example.com>
            \tlet first = true
            bbbbbbbb 2 2 1
            author Bob Stone
            author-mail <bob@example.com>
            \tlet second = true
            """,
            "Sources/Feature.swift": """
            cccccccc 1 1 1
            author Alice Rivera
            author-mail <alice@example.com>
            \tlet feature = true
            """,
        ]
        let suggester = PRReviewerSuggester(blameProvider: { _, filePath in
            blameByPath[filePath] ?? ""
        })

        let suggestions = suggester.suggestions(
            root: root,
            changedFilePaths: ["Sources/App.swift", "Sources/Feature.swift"]
        )

        #expect(suggestions.map(\.displayName) == ["Alice Rivera", "Bob Stone"])
        #expect(suggestions[0].email == "alice@example.com")
        #expect(suggestions[0].lineCount == 2)
        #expect(suggestions[0].fileCount == 2)
        #expect(suggestions[1].lineCount == 1)
        #expect(suggestions[1].fileCount == 1)
    }

    @Test("suggestions skip excluded authors and unsafe paths")
    func suggestionsSkipExcludedAuthorsAndUnsafePaths() {
        let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        var requestedPaths: [String] = []
        let suggester = PRReviewerSuggester(blameProvider: { _, filePath in
            requestedPaths.append(filePath)
            return """
            aaaaaaaa 1 1 1
            author Alice Rivera
            author-mail <alice@example.com>
            \tlet first = true
            bbbbbbbb 2 2 1
            author Current User
            author-mail <current@example.com>
            \tlet second = true
            """
        })

        let suggestions = suggester.suggestions(
            root: root,
            changedFilePaths: [
                "/tmp/repo/Sources/App.swift",
                "../Secrets.swift",
                "Sources/App.swift",
            ],
            excludingEmails: ["current@example.com"]
        )

        #expect(requestedPaths == ["Sources/App.swift"])
        #expect(suggestions.map(\.email) == ["alice@example.com"])
    }

    @Test("suggestions tolerate blame failures and missing emails")
    func suggestionsTolerateBlameFailuresAndMissingEmails() {
        let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let suggester = PRReviewerSuggester(blameProvider: { _, filePath in
            if filePath == "Sources/Broken.swift" {
                throw TestBlameError()
            }
            return """
            aaaaaaaa 1 1 1
            author Dana Lee
            \tlet value = true
            """
        })

        let suggestions = suggester.suggestions(
            root: root,
            changedFilePaths: ["Sources/Broken.swift", "Sources/App.swift"]
        )

        #expect(suggestions.count == 1)
        #expect(suggestions[0].displayName == "Dana Lee")
        #expect(suggestions[0].email == nil)
        #expect(suggestions[0].lineCount == 1)
    }
}

private struct TestBlameError: Error {}
