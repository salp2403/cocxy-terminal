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
        let requestedPaths = LockedStringArray()
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

        #expect(requestedPaths.values == ["Sources/App.swift"])
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

    @Test("AI suggestions rerank local reviewer candidates without inventing people")
    func aiSuggestionsRerankLocalCandidates() async throws {
        let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let client = RecordingReviewerClient(response: """
        bob@example.com
        missing@example.com
        Alice Rivera
        """)
        let suggester = PRReviewerSuggester(blameProvider: { _, filePath in
            switch filePath {
            case "Sources/App.swift":
                return """
                aaaaaaaa 1 1 1
                author Alice Rivera
                author-mail <alice@example.com>
                \tlet first = true
                bbbbbbbb 2 2 1
                author Bob Stone
                author-mail <bob@example.com>
                \tlet second = true
                """
            case "Sources/Feature.swift":
                return """
                cccccccc 1 1 1
                author Alice Rivera
                author-mail <alice@example.com>
                \tlet feature = true
                """
            default:
                return ""
            }
        })

        let suggestions = try await suggester.aiSuggestions(
            root: root,
            changedFilePaths: ["Sources/App.swift", "Sources/Feature.swift"],
            diff: """
            diff --git a/Sources/App.swift b/Sources/App.swift
            +let token = "sk-live-secret"
            """,
            settings: GitAssistantSettings(maxDiffLines: 80),
            client: client,
            limit: 2
        )

        #expect(suggestions.map(\.email) == ["bob@example.com", "alice@example.com"])
        #expect(client.messages.last?.content.contains("[redacted-secret]") == true)
        #expect(client.messages.last?.content.contains("sk-live-secret") == false)
    }

    @Test("reviewer candidates infer editable GitHub handles when possible")
    func reviewerCandidatesInferEditableGitHubHandles() {
        let candidates = [
            PRReviewerCandidate(
                id: "noreply",
                displayName: "Said",
                email: "12345+salp2403@users.noreply.github.com",
                lineCount: 4,
                fileCount: 2
            ),
            PRReviewerCandidate(
                id: "simple",
                displayName: "Alice",
                email: "alice@example.com",
                lineCount: 3,
                fileCount: 1
            ),
            PRReviewerCandidate(
                id: "duplicate",
                displayName: "ALICE",
                email: nil,
                lineCount: 2,
                fileCount: 1
            ),
            PRReviewerCandidate(
                id: "invalid",
                displayName: "Dana Lee",
                email: "dana.lee@example.com",
                lineCount: 1,
                fileCount: 1
            ),
        ]

        #expect(PRReviewerCandidate.reviewerIdentifiers(from: candidates) == ["salp2403", "alice"])
    }
}

private struct TestBlameError: Error {}

private final class RecordingReviewerClient: AgentLLMClient, @unchecked Sendable {
    private let response: String
    private(set) var messages: [AgentMessage] = []

    init(response: String) {
        self.response = response
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        self.messages = messages
        return AgentLLMResponse(content: response)
    }
}

private final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
