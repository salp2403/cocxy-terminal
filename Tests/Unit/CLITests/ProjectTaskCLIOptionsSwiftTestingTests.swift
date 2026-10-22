// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("Project task CLI options")
struct ProjectTaskCLIOptionsSwiftTestingTests {
    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    @Test("task run list carries an absolute project filter")
    func taskRunListProjectFilter() throws {
        let parsed = try CLIArgumentParser.parse([
            "task-run-list", "--project", "/tmp/cocxy-project",
        ])
        #expect(parsed == .taskRunList(project: "/tmp/cocxy-project"))

        let request = runner.buildRequest(from: parsed)
        #expect(request.command == "task-run-list")
        #expect(request.params == ["project": "/tmp/cocxy-project"])

        #expect(try CLIArgumentParser.parse([
            "task-run", "list", "--project", "/tmp/cocxy-project",
        ]) == parsed)
    }

    @Test("task enqueue carries its project independently from the worktree")
    func taskEnqueueProjectAnchor() throws {
        let parsed = try CLIArgumentParser.parse([
            "task-enqueue",
            "--id", "review",
            "--prompt", "Review changes",
            "--worktree", "/tmp/cocxy-project/worktree",
            "--project", "/tmp/cocxy-project",
        ])
        let request = runner.buildRequest(from: parsed)

        #expect(request.command == "task-enqueue")
        #expect(request.params?["cwd"] == "/tmp/cocxy-project/worktree")
        #expect(request.params?["project"] == "/tmp/cocxy-project")
    }

    @Test("project options reject empty values and extra list arguments")
    func rejectsInvalidProjectOptions() {
        #expect(throws: (any Error).self) {
            _ = try CLIArgumentParser.parse([
                "task-run", "list", "--project", "   ",
            ])
        }
        #expect(throws: (any Error).self) {
            _ = try CLIArgumentParser.parse([
                "task-run", "list", "--project", "/tmp/project", "extra",
            ])
        }
        #expect(throws: (any Error).self) {
            _ = try CLIArgumentParser.parse([
                "task-enqueue", "--id", "review", "--prompt", "Review",
                "--project", "   ",
            ])
        }
    }
}
