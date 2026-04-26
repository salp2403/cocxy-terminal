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
