// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantCLIArgumentParserSwiftTestingTests.swift - CLI coverage for `cocxy git-assistant`.

import Testing
@testable import CocxyCLILib

@Suite("CLI git-assistant verb parsing")
struct GitAssistantCLIArgumentParserSwiftTestingTests {
    @Test("commit-message parses with no options and builds socket request")
    func commitMessageParses() throws {
        let command = try CLIArgumentParser.parse(["git-assistant", "commit-message"])
        #expect(command == .gitAssistantCommitMessage)

        let request = CommandRunner().buildRequest(from: command)
        #expect(request.command == "git-assistant-commit-message")
        #expect(request.params == nil)
    }

    @Test("pr-draft parses optional base and head branches")
    func prDraftParsesOptions() throws {
        let command = try CLIArgumentParser.parse([
            "git-assistant", "pr-draft", "--base", "main", "--head", "feature/git",
        ])
        #expect(command == .gitAssistantPRDraft(baseBranch: "main", headBranch: "feature/git"))

        let request = CommandRunner().buildRequest(from: command)
        #expect(request.command == "git-assistant-pr-draft")
        #expect(request.params?["base"] == "main")
        #expect(request.params?["head"] == "feature/git")
    }

    @Test("git-assistant commands use extended socket timeout")
    func commandsUseExtendedTimeout() {
        let runner = CommandRunner(socketClient: SocketClient(
            socketPath: "/tmp/cocxy-git-assistant.sock",
            timeoutSeconds: 1
        ))

        let client = runner.socketClient(for: .gitAssistantCommitMessage)

        #expect(client.socketPath == "/tmp/cocxy-git-assistant.sock")
        #expect(client.timeoutSeconds == CommandRunner.extendedGitAssistantSocketTimeoutSeconds)
    }

    @Test("formatter prints generated drafts")
    func formatterPrintsDrafts() {
        let commitOutput = OutputFormatter.formatSuccess(
            command: .gitAssistantCommitMessage,
            response: CLISocketResponse(
                id: "commit",
                success: true,
                data: ["subject": "feat: add draft", "body": "Body line"],
                error: nil
            )
        )
        let prOutput = OutputFormatter.formatSuccess(
            command: .gitAssistantPRDraft(baseBranch: nil, headBranch: nil),
            response: CLISocketResponse(
                id: "pr",
                success: true,
                data: ["title": "Add draft", "body": "Summary:\n- Change"],
                error: nil
            )
        )

        #expect(commitOutput == "feat: add draft\n\nBody line")
        #expect(prOutput == "Title: Add draft\n\nSummary:\n- Change")
    }
}
