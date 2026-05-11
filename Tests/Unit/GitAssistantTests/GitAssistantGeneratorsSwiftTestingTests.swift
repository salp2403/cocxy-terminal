import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Git Assistant generators")
struct GitAssistantGeneratorsSwiftTestingTests {
    @Test("commit generator sends privacy-safe diff prompt and parses subject/body")
    func commitGeneratorBuildsPromptAndParsesResponse() async throws {
        let client = RecordingGitAssistantLLMClient(response: """
        feat(vcs): add source control tabs

        Add branches, commits and diff views.
        """)
        let generator = CommitMessageGenerator(client: client)

        let draft = try await generator.generate(
            diff: """
            diff --git a/A.swift b/A.swift
            +let token = "ghp_abcdefghijklmnopqrstuvwxyz123456"
            """,
            settings: GitAssistantSettings(maxDiffLines: 40)
        )

        #expect(draft.subject == "feat(vcs): add source control tabs")
        #expect(draft.body == "Add branches, commits and diff views.")
        let prompt = try #require(client.messages.last?.content)
        #expect(prompt.contains("[redacted-secret]"))
        #expect(!prompt.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
    }

    @Test("pull request generator parses title and body from model response")
    func pullRequestGeneratorParsesTitleAndBody() async throws {
        let client = RecordingGitAssistantLLMClient(response: """
        Title: Add source control workspace

        Summary:
        - Adds branch and commit navigation.
        - Adds split diff review.

        Tests:
        - swift test --filter GitHub
        """)
        let generator = PullRequestDraftGenerator(client: client)

        let draft = try await generator.generate(
            baseBranch: "main",
            headBranch: "feature/source-control",
            diff: "diff --git a/A.swift b/A.swift\n+change",
            settings: .defaults
        )

        #expect(draft.title == "Add source control workspace")
        #expect(draft.body.contains("Adds branch and commit navigation."))
        #expect(draft.body.contains("swift test --filter GitHub"))
    }

    @Test("release notes generator groups conventional commits locally before model prompt")
    func releaseNotesGeneratorIncludesGroupedCommits() async throws {
        let client = RecordingGitAssistantLLMClient(response: """
        ## Features
        - Add source control workspace.
        """)
        let generator = ReleaseNotesGenerator(client: client)

        let notes = try await generator.generate(
            commits: [
                GitAssistantCommit(hash: "abc123", subject: "feat(vcs): add branches"),
                GitAssistantCommit(hash: "def456", subject: "fix(ui): avoid empty browser tabs"),
            ],
            settings: .defaults
        )

        #expect(notes.markdown.contains("## Features"))
        let prompt = try #require(client.messages.last?.content)
        #expect(prompt.contains("Features"))
        #expect(prompt.contains("Bug Fixes"))
    }
}

@Suite("GitAssistantService")
struct GitAssistantServiceSwiftTestingTests {
    @Test("service orchestrates commit, pull request and release note generation")
    func serviceOrchestratesGenerators() async throws {
        let client = RecordingGitAssistantLLMClient(responses: [
            "fix: keep pane refresh stable",
            "Title: Keep pane refresh stable\n\nBody line",
            "## Fixes\n- Keep pane refresh stable.",
        ])
        let service = DefaultGitAssistantService(client: client)

        let commit = try await service.generateCommitMessage(
            diff: "diff --git a/A.swift b/A.swift\n+change",
            settings: .defaults
        )
        let pr = try await service.generatePullRequestDraft(
            baseBranch: "main",
            headBranch: "fix/pane-refresh",
            diff: "diff --git a/A.swift b/A.swift\n+change",
            settings: .defaults
        )
        let notes = try await service.generateReleaseNotes(
            commits: [GitAssistantCommit(hash: "abc123", subject: "fix: keep pane refresh stable")],
            settings: .defaults
        )

        #expect(commit.subject == "fix: keep pane refresh stable")
        #expect(pr.title == "Keep pane refresh stable")
        #expect(notes.markdown.contains("Keep pane refresh stable"))
        #expect(client.messages.count == 3)
    }
}

private final class RecordingGitAssistantLLMClient: AgentLLMClient, @unchecked Sendable {
    private(set) var messages: [AgentMessage] = []
    private var responses: [String]

    init(response: String) {
        self.responses = [response]
    }

    init(responses: [String]) {
        self.responses = responses
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        self.messages.append(contentsOf: messages.filter { $0.role == .user })
        let response = responses.isEmpty ? "" : responses.removeFirst()
        return AgentLLMResponse(content: response)
    }
}
