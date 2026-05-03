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

    @Test("executes workflow steps sequentially and stops on first failure")
    func executesWorkflowStepsAndStopsOnFailure() throws {
        let workspace = try temporaryWorkflowDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingWorkflowProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "built\n", stderr: ""),
            AgentProcessResult(exitCode: 1, stdout: "", stderr: "tests failed\n"),
            AgentProcessResult(exitCode: 0, stdout: "deploy\n", stderr: ""),
        ])
        let executor = WorkflowExecutor(processRunner: runner)
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
            ["-lc", "swift build"],
            ["-lc", "swift test"],
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
        let executor = WorkflowExecutor(processRunner: runner)
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
        let executor = WorkflowExecutor(processRunner: runner)
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

private func temporaryWorkflowDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
