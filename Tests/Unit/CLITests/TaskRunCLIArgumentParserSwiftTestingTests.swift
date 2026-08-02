// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import XCTest
@testable import CocxyCLILib

final class TaskRunCLIArgumentParserSwiftTestingTests: XCTestCase {
    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    func testLaunchParsesAndBuildsExactSocketRequest() throws {
        let parsed = try CLIArgumentParser.parse([
            "task-run",
            "--prompt", "Implement and verify",
            "--agents", "claude,codex",
            "--count", "4",
            "--base-ref", "main",
        ])
        XCTAssertEqual(parsed, .taskRun(TaskRunCLIOptions(
            prompt: "Implement and verify",
            agents: "claude,codex",
            count: 4,
            baseRef: "main"
        )))

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "task-run")
        XCTAssertEqual(request.params, [
            "prompt": "Implement and verify",
            "agents": "claude,codex",
            "count": "4",
            "base-ref": "main",
        ])
    }

    func testExplicitLaunchAndDefaultCountParse() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "task-run", "launch",
                "--prompt", "Compare",
                "--agents", "codex,claude",
                "--base-ref", "   ",
            ]),
            .taskRun(TaskRunCLIOptions(
                prompt: "Compare",
                agents: "codex,claude"
            ))
        )
    }

    func testListAndPromoteBuildSocketRequests() throws {
        let list = try CLIArgumentParser.parse(["task-run", "list"])
        XCTAssertEqual(list, .taskRunList(project: nil))
        XCTAssertEqual(runner.buildRequest(from: list).command, "task-run-list")

        let promote = try CLIArgumentParser.parse([
            "task-run", "promote", "task-1",
            "--candidate", "task-1-candidate-2",
        ])
        XCTAssertEqual(
            promote,
            .taskRunPromote(
                runID: "task-1",
                candidateID: "task-1-candidate-2"
            )
        )
        let request = runner.buildRequest(from: promote)
        XCTAssertEqual(request.command, "task-run-promote")
        XCTAssertEqual(request.params, [
            "run-id": "task-1",
            "candidate-id": "task-1-candidate-2",
        ])
    }

    func testLaunchRejectsMissingInputsAndInvalidCounts() {
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-run", "--agents", "codex,claude",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-run", "--prompt", "Compare",
        ]))

        for count in ["one", "1", "9"] {
            XCTAssertThrowsError(try CLIArgumentParser.parse([
                "task-run",
                "--prompt", "Compare",
                "--agents", "codex,claude",
                "--count", count,
            ]))
        }
    }

    func testPromoteRequiresCandidateAndRejectsUnknownFlags() {
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-run", "promote", "task-1",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-run", "promote", "task-1", "--force",
        ]))
    }

    func testLaunchOutputExposesTheScopedSessionOnce() {
        let command = ParsedCommand.taskRun(TaskRunCLIOptions(
            prompt: "Compare",
            agents: "codex,claude"
        ))
        let response = CLISocketResponse(
            id: "task-run",
            success: true,
            data: [
                "run-id": "task-1",
                "candidates": "2",
                "orchestration-session": "lease-1",
                "orchestration-expires-at": "2026-07-30T01:00:00Z",
            ],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(command: command, response: response)

        XCTAssertTrue(output.contains("Task run task-1 launched with 2 candidates."))
        XCTAssertTrue(output.contains("Orchestration session (shown once): lease-1"))
        XCTAssertTrue(output.contains("2026-07-30T01:00:00Z"))
    }
}
