// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import XCTest
@testable import CocxyCLILib

final class TaskQueueCLIArgumentParserSwiftTestingTests: XCTestCase {
    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    func testInlineEnqueueParsesAndBuildsExactSocketRequest() throws {
        let parsed = try CLIArgumentParser.parse([
            "task-enqueue",
            "--id", "nightly-review",
            "--provider", "codex",
            "--prompt", "Review and test",
            "--worktree", "/tmp/cocxy-review",
            "--cron", "0 2 * * MON-FRI",
            "--timezone", "UTC",
            "--retries", "3",
            "--concurrency", "4",
        ])
        XCTAssertEqual(parsed, .taskEnqueue(TaskEnqueueCLIOptions(
            taskID: "nightly-review",
            provider: "codex",
            prompt: "Review and test",
            worktree: "/tmp/cocxy-review",
            trigger: .cron(
                expression: "0 2 * * MON-FRI",
                timeZoneIdentifier: "UTC"
            ),
            maximumRetries: 3,
            maximumParallelSteps: 4
        )))

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "task-enqueue")
        XCTAssertEqual(request.params, [
            "task-id": "nightly-review",
            "provider": "codex",
            "prompt": "Review and test",
            "cwd": "/tmp/cocxy-review",
            "trigger": "cron",
            "cron": "0 2 * * MON-FRI",
            "timezone": "UTC",
            "retries": "3",
            "concurrency": "4",
        ])
    }

    func testPipelineAndEventTriggerBuildBoundAbsolutePaths() throws {
        let parsed = try CLIArgumentParser.parse([
            "task-enqueue",
            "--id", "on-save-review",
            "--pipeline", "/tmp/pipeline.json",
            "--worktree", "/tmp/project",
            "--event", "command-complete",
        ])
        XCTAssertEqual(parsed, .taskEnqueue(TaskEnqueueCLIOptions(
            taskID: "on-save-review",
            pipelinePath: "/tmp/pipeline.json",
            worktree: "/tmp/project",
            trigger: .event("command-complete")
        )))

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "task-enqueue")
        XCTAssertEqual(request.params?["input"], "/tmp/pipeline.json")
        XCTAssertEqual(request.params?["cwd"], "/tmp/project")
        XCTAssertEqual(request.params?["trigger"], "on-event")
        XCTAssertEqual(request.params?["event"], "command-complete")
        XCTAssertNil(request.params?["prompt"])
        XCTAssertNil(request.params?["provider"])
    }

    func testManualDefaultsListAndCancelRequests() throws {
        let enqueue = try CLIArgumentParser.parse([
            "task-enqueue",
            "--id", "manual-review",
            "--prompt", "Review",
            "--worktree", "/tmp/project",
        ])
        XCTAssertEqual(enqueue, .taskEnqueue(TaskEnqueueCLIOptions(
            taskID: "manual-review",
            provider: "claude-code",
            prompt: "Review",
            worktree: "/tmp/project"
        )))
        XCTAssertEqual(runner.buildRequest(from: enqueue).params?["trigger"], "manual")

        let list = try CLIArgumentParser.parse([
            "task-list", "--limit", "25", "--offset", "50",
        ])
        XCTAssertEqual(list, .taskList(TaskListCLIOptions(limit: 25, offset: 50)))
        XCTAssertEqual(runner.buildRequest(from: list).params, [
            "limit": "25",
            "offset": "50",
        ])

        let cancel = try CLIArgumentParser.parse(["task-cancel", "manual-review"])
        XCTAssertEqual(cancel, .taskCancel(taskID: "manual-review"))
        XCTAssertEqual(runner.buildRequest(from: cancel).params, [
            "task-id": "manual-review",
        ])
    }

    func testEnqueueRejectsAmbiguousSourcesAndTriggers() {
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-enqueue", "--id", "missing-source",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-enqueue", "--id", "two-sources",
            "--pipeline", "/tmp/pipeline.json", "--prompt", "Review",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-enqueue", "--id", "two-triggers", "--prompt", "Review",
            "--cron", "0 * * * *", "--event", "command-complete",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-enqueue", "--id", "bad-timezone", "--prompt", "Review",
            "--timezone", "UTC",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-enqueue", "--id", "bad-retries", "--prompt", "Review",
            "--retries", "6",
        ]))
    }

    func testListBoundsAndCancelArityAreValidated() {
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-list", "--limit", "101",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-list", "--offset", "-1",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse(["task-cancel"]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "task-cancel", "one", "two",
        ]))
    }

    func testTaskQueueOutputIsConciseAndPathFree() {
        let list = ParsedCommand.taskList(TaskListCLIOptions())
        let response = CLISocketResponse(
            id: "task-list",
            success: true,
            data: [
                "total": "1",
                "returned": "1",
                "offset": "0",
                "task_0_id": "nightly-review",
                "task_0_status": "scheduled",
                "task_0_trigger": "cron",
                "task_0_steps": "3",
                "task_0_runs": "2",
                "task_0_next-run-at": "2026-07-31T02:00:00Z",
            ],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(command: list, response: response)

        XCTAssertTrue(output.contains("nightly-review  scheduled  cron"))
        XCTAssertTrue(output.contains("next: 2026-07-31T02:00:00Z"))
        XCTAssertFalse(output.contains("prompt"))
        XCTAssertFalse(output.contains("/tmp"))
    }
}
