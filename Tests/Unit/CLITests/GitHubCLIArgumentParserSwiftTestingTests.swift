// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubCLIArgumentParserSwiftTestingTests.swift - Parsing tests for
// the `cocxy github` verb family introduced in v0.1.84.

import Testing
@testable import CocxyCLILib

@Suite("CLI github verb parsing")
struct GitHubCLIArgumentParserSwiftTestingTests {

    @Test("`cocxy github status` parses with no options")
    func githubStatus_parsesWithNoOptions() throws {
        let command = try CLIArgumentParser.parse(["github", "status"])
        guard case .githubStatus = command else {
            Issue.record("Expected .githubStatus, got \(command)")
            return
        }
    }

    @Test("GitHub read commands use extended socket timeout budget")
    func githubReadCommandsUseExtendedSocketTimeoutBudget() {
        let runner = CommandRunner(
            socketClient: SocketClient(
                socketPath: "/tmp/cocxy-github-timeout.sock",
                timeoutSeconds: SocketClient.defaultTimeoutSeconds
            )
        )
        let commands: [ParsedCommand] = [
            .githubStatus,
            .githubPRs(state: nil, limit: nil),
            .githubIssues(state: nil, limit: nil),
        ]

        for command in commands {
            let client = runner.socketClient(for: command)

            #expect(client.socketPath == "/tmp/cocxy-github-timeout.sock")
            #expect(client.timeoutSeconds == CommandRunner.extendedGitHubReadSocketTimeoutSeconds)
        }
    }

    @Test("GitHub mutation commands use the approval-aware socket timeout budget")
    func githubMutationCommandsUseApprovalAwareSocketTimeoutBudget() {
        let runner = CommandRunner(
            socketClient: SocketClient(
                socketPath: "/tmp/cocxy-github-merge-timeout.sock",
                timeoutSeconds: SocketClient.defaultTimeoutSeconds
            )
        )
        let commands: [ParsedCommand] = [
            .githubPRMerge(
                method: .squash,
                prNumber: nil,
                deleteBranch: true,
                subject: nil,
                body: nil
            ),
            .reviewApprove(prNumber: 42, body: nil, readBodyFromStdin: false),
            .reviewRequestChanges(prNumber: 42, body: "Fix it", readBodyFromStdin: false),
        ]

        for command in commands {
            let client = runner.socketClient(for: command)
            #expect(client.socketPath == "/tmp/cocxy-github-merge-timeout.sock")
            #expect(client.timeoutSeconds == CommandRunner.extendedGitHubMutationSocketTimeoutSeconds)
            #expect(client.timeoutSeconds == 300)
        }
    }

    @Test("non GitHub commands keep the default socket timeout budget")
    func nonGitHubCommandsKeepDefaultSocketTimeoutBudget() {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/cocxy-fast-command.sock")
        )
        let client = runner.socketClient(for: .status)

        #expect(client.socketPath == "/tmp/cocxy-fast-command.sock")
        #expect(client.timeoutSeconds == SocketClient.defaultTimeoutSeconds)
    }

    @Test("custom larger socket timeout is preserved for GitHub commands")
    func customLargerSocketTimeoutIsPreservedForGitHubCommands() {
        let runner = CommandRunner(
            socketClient: SocketClient(
                socketPath: "/tmp/cocxy-custom-github-timeout.sock",
                timeoutSeconds: 60
            )
        )
        let client = runner.socketClient(for: .githubStatus)

        #expect(client.socketPath == "/tmp/cocxy-custom-github-timeout.sock")
        #expect(client.timeoutSeconds == 60)
    }

    @Test("`cocxy github prs` accepts optional --state and --limit")
    func githubPRs_parsesStateAndLimit() throws {
        let command = try CLIArgumentParser.parse([
            "github", "prs", "--state", "merged", "--limit", "10",
        ])
        guard case .githubPRs(let state, let limit) = command else {
            Issue.record("Expected .githubPRs, got \(command)")
            return
        }
        #expect(state == "merged")
        #expect(limit == 10)
    }

    @Test("`cocxy github prs` without flags leaves state and limit nil")
    func githubPRs_parsesNoFlags() throws {
        let command = try CLIArgumentParser.parse(["github", "prs"])
        guard case .githubPRs(let state, let limit) = command else {
            Issue.record("Expected .githubPRs, got \(command)")
            return
        }
        #expect(state == nil)
        #expect(limit == nil)
    }

    @Test("`cocxy github issues` accepts optional --state and --limit")
    func githubIssues_parsesStateAndLimit() throws {
        let command = try CLIArgumentParser.parse([
            "github", "issues", "--state", "closed", "--limit", "50",
        ])
        guard case .githubIssues(let state, let limit) = command else {
            Issue.record("Expected .githubIssues, got \(command)")
            return
        }
        #expect(state == "closed")
        #expect(limit == 50)
    }

    @Test("`cocxy github open` parses with no options")
    func githubOpen_parsesNoOptions() throws {
        let command = try CLIArgumentParser.parse(["github", "open"])
        guard case .githubOpen = command else {
            Issue.record("Expected .githubOpen, got \(command)")
            return
        }
    }

    @Test("`cocxy github refresh` parses with no options")
    func githubRefresh_parsesNoOptions() throws {
        let command = try CLIArgumentParser.parse(["github", "refresh"])
        guard case .githubRefresh = command else {
            Issue.record("Expected .githubRefresh, got \(command)")
            return
        }
    }

    @Test("`cocxy github pr-merge --help` prints help instead of hitting the socket")
    func githubPRMerge_helpReturnsHelp() throws {
        #expect(try CLIArgumentParser.parse(["github", "pr-merge", "--help"]) == .help)

        let runner = CommandRunner(socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock"))
        let result = runner.run(arguments: ["github", "pr-merge", "--help"])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("cocxy github pr-merge"))
        #expect(result.stderr.isEmpty)
    }

    @Test("`cocxy github pr-merge` keeps the branch by default")
    func githubPRMerge_keepsBranchByDefault() throws {
        let command = try CLIArgumentParser.parse([
            "github", "pr-merge", "--squash"
        ])

        guard case .githubPRMerge(_, _, let deleteBranch, _, _) = command else {
            Issue.record("Expected .githubPRMerge, got \(command)")
            return
        }
        #expect(!deleteBranch)
    }

    @Test("`cocxy github pr-merge --delete-branch` opts into branch deletion")
    func githubPRMerge_acceptsDeleteBranchFlag() throws {
        let command = try CLIArgumentParser.parse([
            "github", "pr-merge", "--merge", "--delete-branch"
        ])

        guard case .githubPRMerge(_, _, let deleteBranch, _, _) = command else {
            Issue.record("Expected .githubPRMerge, got \(command)")
            return
        }
        #expect(deleteBranch)
    }

    @Test("`cocxy github pr-merge --no-delete-branch` explicitly keeps the branch")
    func githubPRMerge_acceptsNoDeleteBranchFlag() throws {
        let command = try CLIArgumentParser.parse([
            "github", "pr-merge", "--rebase", "--no-delete-branch"
        ])

        guard case .githubPRMerge(_, _, let deleteBranch, _, _) = command else {
            Issue.record("Expected .githubPRMerge, got \(command)")
            return
        }
        #expect(!deleteBranch)
    }

    @Test("GitHub merge help advertises both explicit branch choices")
    func githubPRMerge_helpAdvertisesBothBranchChoices() {
        let help = CLIArgumentParser.helpText()

        #expect(help.contains("[--delete-branch|--no-delete-branch]"))
    }

    @Test("`cocxy github bogus` throws invalidArgument")
    func github_unknownSubcommandThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["github", "bogus"])
        }
    }

    @Test("`cocxy github prs --limit abc` rejects non-integer limit")
    func githubPRs_rejectsNonIntegerLimit() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse([
                "github", "prs", "--limit", "abc",
            ])
        }
    }

    @Test("`cocxy github open extra-arg` rejects extra positional argument")
    func githubOpen_rejectsExtraArgument() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["github", "open", "extra"])
        }
    }

    @Test("`cocxy github status --foo` rejects unknown flag")
    func githubStatus_rejectsUnknownFlag() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["github", "status", "--foo"])
        }
    }
}
