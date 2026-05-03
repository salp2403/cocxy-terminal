// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowPanelViewModelSwiftTestingTests.swift - UI state for workflow panels.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Workflow panel view model")
struct WorkflowPanelViewModelSwiftTestingTests {
    @Test("loads, saves and executes workflow TOML")
    @MainActor
    func runsWorkflowAndExposesStepResults() async throws {
        let workspace = try temporaryWorkflowPanelDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let fileURL = workspace.appendingPathComponent("ci.toml")
        try """
        [workflow]
        id = "ci"
        steps = ["verify"]

        [step.verify]
        command = "echo workflow-panel-ok"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let runner = RecordingWorkflowPanelProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "workflow-panel-ok\n", stderr: ""),
        ])
        let viewModel = WorkflowPanelViewModel(
            fileURL: fileURL,
            workspaceRoot: workspace,
            executor: WorkflowExecutor(processRunner: runner)
        )

        #expect(viewModel.workflowID == "ci")
        #expect(viewModel.stepPresentations.map(\.id) == ["verify"])

        await viewModel.run()

        #expect(viewModel.statusText == "Workflow ci completed after 1 step.")
        #expect(viewModel.errorText == nil)
        #expect(viewModel.stepPresentations.first?.stdout == "workflow-panel-ok\n")
        #expect(runner.calls.map(\.arguments) == [["-c", "echo workflow-panel-ok"]])
    }
}

private final class RecordingWorkflowPanelProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [WorkflowPanelProcessCall] = []
    private var results: [AgentProcessResult]

    init(results: [AgentProcessResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        calls.append(WorkflowPanelProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        ))
        return results.removeFirst()
    }
}

private struct WorkflowPanelProcessCall: Equatable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private func temporaryWorkflowPanelDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-workflow-panel-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
