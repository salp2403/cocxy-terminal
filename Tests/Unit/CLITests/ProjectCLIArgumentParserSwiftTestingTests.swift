// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("Project CLI parser")
struct ProjectCLIArgumentParserSwiftTestingTests {
    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/cocxy-project-cli.sock")
    )

    @Test("all project verbs parse into their closed command cases")
    func parsesEveryProjectVerb() throws {
        #expect(try CLIArgumentParser.parse(["project-open", "/tmp/repo"])
            == .projectOpen(path: "/tmp/repo"))
        #expect(try CLIArgumentParser.parse(["project-list", "--json"])
            == .projectList(json: true))
        #expect(try CLIArgumentParser.parse(["project-pin", "/tmp/repo"])
            == .projectPin(reference: "/tmp/repo"))
        #expect(try CLIArgumentParser.parse(["project-unpin", "/tmp/repo"])
            == .projectUnpin(reference: "/tmp/repo"))
        #expect(try CLIArgumentParser.parse(["project-alias", "/tmp/repo", "Local", "API"])
            == .projectAlias(reference: "/tmp/repo", alias: "Local API"))
        #expect(try CLIArgumentParser.parse(["project-forget", "/tmp/repo"])
            == .projectForget(reference: "/tmp/repo"))
        #expect(try CLIArgumentParser.parse([
            "project-clone", "https://example.com/team/repo.git", "--into", "/tmp",
        ]) == .projectClone(
            remote: "https://example.com/team/repo.git",
            parentDirectory: "/tmp"
        ))
        #expect(try CLIArgumentParser.parse([
            "project-tasks", "--json", "--project", "/tmp/repo",
        ]) == .projectTasks(project: "/tmp/repo", json: true))
    }

    @Test("project command arity and flags fail closed")
    func rejectsInvalidArguments() {
        #expect(throws: CLIError.self) { try CLIArgumentParser.parse(["project-open"]) }
        #expect(throws: CLIError.self) {
            try CLIArgumentParser.parse(["project-list", "--json", "--json"])
        }
        #expect(throws: CLIError.self) {
            try CLIArgumentParser.parse(["project-alias", "/tmp/repo"])
        }
        #expect(throws: CLIError.self) {
            try CLIArgumentParser.parse([
                "project-clone", "https://example.com/repo.git", "/tmp",
            ])
        }
        #expect(throws: CLIError.self) {
            try CLIArgumentParser.parse(["project-tasks", "--project"])
        }
        #expect(throws: CLIError.self) {
            try CLIArgumentParser.parse(["project-tasks", "--unknown"])
        }
    }

    @Test("socket requests bind paths and exact command names")
    func buildsExactSocketRequests() throws {
        let open = runner.buildRequest(from: try CLIArgumentParser.parse([
            "project-open", "/tmp/repo",
        ]))
        #expect(open.command == "project-open")
        #expect(open.params == ["path": "/tmp/repo"])

        let alias = runner.buildRequest(from: try CLIArgumentParser.parse([
            "project-alias", "/tmp/repo", "API",
        ]))
        #expect(alias.command == "project-alias")
        #expect(alias.params == ["project": "/tmp/repo", "alias": "API"])

        let clone = runner.buildRequest(from: try CLIArgumentParser.parse([
            "project-clone", "ssh://git@example.com/team/repo.git", "--into", "/tmp",
        ]))
        #expect(clone.command == "project-clone")
        #expect(clone.params == [
            "remote": "ssh://git@example.com/team/repo.git",
            "parent": "/tmp",
        ])

        let tasks = runner.buildRequest(from: .projectTasks(project: "/tmp/repo", json: true))
        #expect(tasks.command == "project-tasks")
        #expect(tasks.params == ["project": "/tmp/repo"])
    }

    @Test("JSON output exposes only the server collection payload")
    func formatsProjectCollections() {
        let response = CLISocketResponse(
            id: "projects",
            success: true,
            data: [
                "projects": #"[{"id":"/tmp/repo","name":"API"}]"#,
                "summary": "[live] API - /tmp/repo",
            ],
            error: nil
        )
        let json = OutputFormatter.formatSuccess(
            command: .projectList(json: true),
            response: response
        )
        #expect(json.contains(#""id" : "/tmp/repo""#))
        #expect(!json.contains("summary"))
        #expect(OutputFormatter.formatSuccess(
            command: .projectList(json: false),
            response: response
        ) == "[live] API - /tmp/repo")
    }

    @Test("project open receives approval grace and clone receives bounded Git time")
    func usesBoundedSocketTimeouts() {
        #expect(runner.socketClient(for: .projectOpen(path: "/tmp/repo")).timeoutSeconds == 70)
        #expect(runner.socketClient(for: .projectClone(
            remote: "https://example.com/repo.git",
            parentDirectory: "/tmp"
        )).timeoutSeconds == 300)
    }
}
