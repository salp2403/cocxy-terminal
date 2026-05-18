// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamsCLIArgumentParserSwiftTestingTests.swift - Agent team CLI coverage.

import XCTest
@testable import CocxyCLILib

final class AgentTeamsCLIArgumentParserSwiftTestingTests: XCTestCase {
    private let runner = CommandRunner(socketClient: SocketClient(socketPath: "/tmp/test.sock"))

    func testClaudeTeamsLaunchParsesTeammatesAndConfig() throws {
        let parsed = try CLIArgumentParser.parse([
            "claude-teams",
            "--teammates", "A,B,C",
            "--team-id", "review-team",
            "--config", "/tmp/team.toml",
        ])

        XCTAssertEqual(
            parsed,
            .agentTeamLaunch(AgentTeamCLIOptions(
                teammates: "A,B,C",
                teamID: "review-team",
                configPath: "/tmp/team.toml",
                provider: "claude-code"
            ))
        )
    }

    func testAgentTeamsLaunchParsesProvider() throws {
        let parsed = try CLIArgumentParser.parse([
            "agent-teams",
            "--provider", "codex",
            "--teammates", "Plan,Build",
            "--team-id", "codex-team",
        ])

        XCTAssertEqual(
            parsed,
            .agentTeamLaunch(AgentTeamCLIOptions(
                teammates: "Plan,Build",
                teamID: "codex-team",
                provider: "codex"
            ))
        )
    }

    func testAgentTeamsLaunchParsesTemplate() throws {
        let parsed = try CLIArgumentParser.parse([
            "agent-teams",
            "--template", "cli-tool",
            "--provider", "opencode",
            "--team-id", "ship-cli",
        ])

        XCTAssertEqual(
            parsed,
            .agentTeamLaunch(AgentTeamCLIOptions(
                teammates: nil,
                teamID: "ship-cli",
                templateID: "cli-tool",
                provider: "opencode"
            ))
        )
    }

    func testClaudeTeamsLaunchBuildsSocketRequest() {
        let request = runner.buildRequest(from: .agentTeamLaunch(AgentTeamCLIOptions(
            teammates: "A,B,C",
            teamID: "review-team",
            configPath: "/tmp/team.toml",
            provider: "codex"
        )))

        XCTAssertEqual(request.command, "agent-team-launch")
        XCTAssertEqual(request.params?["provider"], "codex")
        XCTAssertEqual(request.params?["teammates"], "A,B,C")
        XCTAssertEqual(request.params?["team-id"], "review-team")
        XCTAssertEqual(request.params?["config"], "/tmp/team.toml")
    }

    func testAgentTeamsTemplateLaunchBuildsSocketRequest() {
        let request = runner.buildRequest(from: .agentTeamLaunch(AgentTeamCLIOptions(
            teammates: nil,
            teamID: "ship-cli",
            templateID: "cli-tool",
            provider: "codex"
        )))

        XCTAssertEqual(request.command, "agent-team-launch")
        XCTAssertEqual(request.params?["provider"], "codex")
        XCTAssertEqual(request.params?["template"], "cli-tool")
        XCTAssertEqual(request.params?["team-id"], "ship-cli")
        XCTAssertNil(request.params?["teammates"])
    }

    func testClaudeTeamsListAndStopParseAndBuildRequests() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["claude-teams", "list"]), .agentTeamList)
        XCTAssertEqual(try CLIArgumentParser.parse(["claude-teams", "stop", "team-1"]), .agentTeamStop(teamID: "team-1"))

        XCTAssertEqual(runner.buildRequest(from: .agentTeamList).command, "agent-team-list")

        let stopRequest = runner.buildRequest(from: .agentTeamStop(teamID: "team-1"))
        XCTAssertEqual(stopRequest.command, "agent-team-stop")
        XCTAssertEqual(stopRequest.params?["team-id"], "team-1")
    }

    func testClaudeTeamsLaunchRequiresTeammates() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["claude-teams", "--team-id", "empty"])) { error in
            XCTAssertEqual(
                error as? CLIError,
                .missingArgument(command: "claude-teams", argument: "--teammates <name,name>")
            )
        }
    }

    func testAgentTeamsLaunchRejectsTemplateAndTeammatesTogether() {
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "agent-teams",
            "--template", "cli-tool",
            "--teammates", "Plan,Build",
        ])) { error in
            XCTAssertEqual(
                error as? CLIError,
                .invalidArgument(
                    command: "claude-teams",
                    argument: "--template cli-tool --teammates Plan,Build",
                    reason: "Use either --template <id> or --teammates <name,name>, not both."
                )
            )
        }
    }
}
