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
                configPath: "/tmp/team.toml"
            ))
        )
    }

    func testClaudeTeamsLaunchBuildsSocketRequest() {
        let request = runner.buildRequest(from: .agentTeamLaunch(AgentTeamCLIOptions(
            teammates: "A,B,C",
            teamID: "review-team",
            configPath: "/tmp/team.toml"
        )))

        XCTAssertEqual(request.command, "agent-team-launch")
        XCTAssertEqual(request.params?["provider"], "claude-code")
        XCTAssertEqual(request.params?["teammates"], "A,B,C")
        XCTAssertEqual(request.params?["team-id"], "review-team")
        XCTAssertEqual(request.params?["config"], "/tmp/team.toml")
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
}
