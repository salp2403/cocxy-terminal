// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowSwiftTestingTests.swift - Local workflow TOML and execution coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Workflow domain")
struct WorkflowSwiftTestingTests {
    @Test("parses ordered TOML workflow steps")
    func parsesOrderedWorkflowSteps() throws {
        let workflow = try WorkflowTOMLCodec.parse("""
        [workflow]
        id = "ci"
        name = "Local CI"
        description = "Build and test"
        steps = ["build", "test"]

        [step.build]
        title = "Build"
        command = "swift build"
        timeout-seconds = 30

        [step.test]
        command = "swift test --filter Notebook"
        shell = "zsh"
        working-directory = "App"
        continue-on-failure = true
        """)

        #expect(workflow.id == "ci")
        #expect(workflow.name == "Local CI")
        #expect(workflow.steps.map(\.id) == ["build", "test"])
        #expect(workflow.steps[0].title == "Build")
        #expect(workflow.steps[0].timeoutSeconds == 30)
        #expect(workflow.steps[1].shell == .zsh)
        #expect(workflow.steps[1].workingDirectory == "App")
        #expect(workflow.steps[1].continueOnFailure == true)
    }

    @Test("renders workflow TOML that round-trips through the parser")
    func rendersWorkflowTOMLRoundTrip() throws {
        let original = WorkflowDocument(
            id: "release-check",
            name: "Release Check",
            description: "Build bundle locally",
            steps: [
                WorkflowStep(id: "build", title: "Build", command: "swift build", timeoutSeconds: 60),
                WorkflowStep(id: "test", command: "swift test", shell: .zsh, continueOnFailure: true),
            ]
        )

        let rendered = WorkflowTOMLCodec.render(original)
        let reparsed = try WorkflowTOMLCodec.parse(rendered)

        #expect(rendered.contains("[workflow]"))
        #expect(rendered.contains("steps = [\"build\", \"test\"]"))
        #expect(rendered.contains("[step.build]"))
        #expect(reparsed == original)
    }

    @Test("rejects unsupported workflow shells instead of falling back")
    func rejectsUnsupportedWorkflowShells() {
        #expect(throws: WorkflowTOMLCodecError.unsupportedShell(
            stepID: "build",
            shell: "fish"
        )) {
            _ = try WorkflowTOMLCodec.parse("""
            [workflow]
            id = "ci"
            steps = ["build"]

            [step.build]
            command = "swift build"
            shell = "fish"
            """)
        }
    }

    @Test("executes workflow steps sequentially and stops on first failure")
    func executesWorkflowStepsAndStopsOnFailure() throws {
        let workspace = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingWorkflowProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "built\n", stderr: ""),
            AgentProcessResult(exitCode: 1, stdout: "", stderr: "tests failed\n"),
            AgentProcessResult(exitCode: 0, stdout: "deploy\n", stderr: ""),
        ])
        let executor = WorkflowExecutor(processRunner: runner, sandboxPolicy: .none)
        let workflow = WorkflowDocument(
            id: "ci",
            name: "CI",
            steps: [
                WorkflowStep(id: "build", command: "swift build"),
                WorkflowStep(id: "test", command: "swift test"),
                WorkflowStep(id: "deploy", command: "echo deploy"),
            ]
        )

        let summary = try executor.execute(workflow, workspaceRoot: workspace)

        #expect(summary.status == .failed(stepID: "test", exitCode: 1))
        #expect(summary.results.map(\.stepID) == ["build", "test"])
        #expect(runner.calls.map(\.arguments) == [
            ["-c", "swift build"],
            ["-c", "swift test"],
        ])
    }

    @Test("continue-on-failure allows later workflow steps to run")
    func continueOnFailureAllowsLaterSteps() throws {
        let workspace = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingWorkflowProcessRunner(results: [
            AgentProcessResult(exitCode: 1, stdout: "", stderr: "lint failed\n"),
            AgentProcessResult(exitCode: 0, stdout: "tests ok\n", stderr: ""),
        ])
        let executor = WorkflowExecutor(processRunner: runner, sandboxPolicy: .none)
        let workflow = WorkflowDocument(
            id: "ci",
            steps: [
                WorkflowStep(id: "lint", command: "swiftlint", continueOnFailure: true),
                WorkflowStep(id: "test", command: "swift test"),
            ]
        )

        let summary = try executor.execute(workflow, workspaceRoot: workspace)

        #expect(summary.status == .completed)
        #expect(summary.results.map(\.exitCode) == [1, 0])
        #expect(runner.calls.count == 2)
    }

    @Test("workflow working directories cannot escape the workspace root")
    func workflowWorkingDirectoryCannotEscapeWorkspace() throws {
        let workspace = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingWorkflowProcessRunner()
        let executor = WorkflowExecutor(processRunner: runner, sandboxPolicy: .none)
        let workflow = WorkflowDocument(
            id: "escape",
            steps: [
                WorkflowStep(id: "bad", command: "pwd", workingDirectory: "../outside"),
            ]
        )

        #expect(throws: WorkflowExecutionError.workingDirectoryEscapesRoot("../outside")) {
            _ = try executor.execute(workflow, workspaceRoot: workspace)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("workspace sandbox wraps commands with bounded filesystem and network authority")
    func workspaceSandboxWrapsCommandsWithBoundedAuthority() throws {
        let workspace = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingWorkflowProcessRunner()
        let executor = WorkflowExecutor(processRunner: runner)
        let workflow = WorkflowDocument(
            id: "sandboxed",
            steps: [WorkflowStep(id: "verify", command: "printf ok")]
        )

        _ = try executor.execute(workflow, workspaceRoot: workspace)

        let call = try #require(runner.calls.first)
        #expect(call.executablePath == "/usr/bin/sandbox-exec")
        #expect(call.arguments.first == "-p")
        let profile = try #require(call.arguments.dropFirst().first)
        #expect(profile.contains("(deny network*)"))
        #expect(profile.contains("(deny file-read*)"))
        #expect(profile.contains("(deny file-write*)"))
        #expect(profile.contains("(deny process-exec)"))
        #expect(profile.contains(workspace.resolvingSymlinksInPath().path))
        #expect(call.arguments.contains("/bin/bash"))
        let remainingNames = try FileManager.default.contentsOfDirectory(atPath: workspace.path)
        #expect(!remainingNames.contains { $0.hasPrefix(".cocxy-workflow-") })
    }

    @Test("workspace sandbox fails closed when sandbox-exec is unavailable")
    func workspaceSandboxFailsClosedWhenUnavailable() throws {
        let workspace = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingWorkflowProcessRunner()
        let executor = WorkflowExecutor(
            processRunner: runner,
            sandboxExecutor: SandboxExecutor(
                fileManager: WorkflowSandboxFileManager(executable: false)
            )
        )
        let workflow = WorkflowDocument(
            id: "sandboxed",
            steps: [WorkflowStep(id: "verify", command: "printf ok")]
        )

        #expect(throws: WorkflowExecutionError.sandboxUnavailable) {
            _ = try executor.execute(workflow, workspaceRoot: workspace)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("workspace sandbox permits workspace writes and blocks sibling reads")
    func workspaceSandboxEnforcesFilesystemBoundary() throws {
        let root = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let secretURL = root.appendingPathComponent("outside-secret.txt")
        try "outside-secret".write(to: secretURL, atomically: true, encoding: .utf8)
        let artifactURL = workspace.appendingPathComponent("artifact.txt")
        let workflow = WorkflowDocument(
            id: "filesystem-boundary",
            steps: [
                WorkflowStep(
                    id: "inside-write",
                    command: "printf inside > artifact.txt"
                ),
                WorkflowStep(
                    id: "outside-read",
                    command: "cat \(shellQuoted(secretURL.path))"
                ),
            ]
        )

        let summary = try WorkflowExecutor().execute(workflow, workspaceRoot: workspace)

        guard case .failed(let stepID, let exitCode) = summary.status else {
            Issue.record("Expected the out-of-workspace read to fail")
            return
        }
        #expect(stepID == "outside-read")
        #expect(exitCode != 0)
        #expect(summary.results.count == 2)
        #expect(summary.results[0].exitCode == 0)
        #expect(summary.results[1].exitCode != 0)
        #expect(!summary.results[1].stdout.contains("outside-secret"))
        #expect(try String(contentsOf: artifactURL, encoding: .utf8) == "inside")
    }

    @Test("registry lists and loads workflow TOML files by id")
    func registryListsAndLoadsWorkflowFiles() throws {
        let directory = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = WorkflowRegistry(directory: directory)
        try WorkflowTOMLCodec.render(WorkflowDocument(
            id: "build",
            name: "Build",
            steps: [WorkflowStep(id: "compile", command: "swift build")]
        )).write(to: directory.appendingPathComponent("build.toml"), atomically: true, encoding: .utf8)

        let workflows = try registry.list()
        let loaded = try registry.load(id: "build")

        #expect(workflows.map(\.id) == ["build"])
        #expect(loaded?.name == "Build")
    }
}

private final class RecordingWorkflowProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [WorkflowProcessCall] = []
    private var results: [AgentProcessResult]

    init(results: [AgentProcessResult] = []) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        calls.append(WorkflowProcessCall(
            executablePath: executableURL.path,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        ))
        return results.isEmpty
            ? AgentProcessResult(exitCode: 0, stdout: "", stderr: "")
            : results.removeFirst()
    }
}

private struct WorkflowProcessCall: Equatable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private struct WorkflowSandboxFileManager: SandboxFileManaging {
    let executable: Bool

    func isExecutableFile(atPath path: String) -> Bool {
        executable
    }
}

private func temporaryWorkflowDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
