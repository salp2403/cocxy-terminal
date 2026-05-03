// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowPanelViewModel.swift - State and execution for workflow panels.

import Combine
import Foundation

struct WorkflowStepPresentation: Identifiable, Equatable {
    let id: String
    let title: String?
    let command: String
    let shell: WorkflowShell
    let status: String
    let stdout: String
    let stderr: String
    let exitCode: Int32?
}

@MainActor
final class WorkflowPanelViewModel: ObservableObject {
    @Published var sourceText: String
    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?
    @Published private(set) var isRunning = false
    @Published private var lastSummary: WorkflowExecutionSummary?

    let fileURL: URL?
    let workspaceRoot: URL

    private let executor: WorkflowExecutor

    var workflow: WorkflowDocument? {
        try? WorkflowTOMLCodec.parse(sourceText)
    }

    var workflowID: String {
        workflow?.id
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "workflow"
    }

    var stepPresentations: [WorkflowStepPresentation] {
        let resultsByStepID = (lastSummary?.results ?? []).reduce(
            into: [String: WorkflowStepExecutionResult]()
        ) { partial, result in
            partial[result.stepID] = result
        }
        return (workflow?.steps ?? []).map { step in
            let result = resultsByStepID[step.id]
            return WorkflowStepPresentation(
                id: step.id,
                title: step.title,
                command: step.command,
                shell: step.shell,
                status: status(for: step.id, result: result),
                stdout: result?.stdout ?? "",
                stderr: result?.stderr ?? "",
                exitCode: result?.exitCode
            )
        }
    }

    init(
        fileURL: URL?,
        workspaceRoot: URL,
        executor: WorkflowExecutor = WorkflowExecutor()
    ) {
        self.fileURL = fileURL
        self.workspaceRoot = workspaceRoot
        self.executor = executor

        if let fileURL,
           let loaded = try? String(contentsOf: fileURL, encoding: .utf8) {
            sourceText = loaded
            statusText = "Loaded \(fileURL.lastPathComponent)"
        } else {
            sourceText = Self.defaultWorkflowSource()
            statusText = "New workflow"
        }
    }

    func save() throws {
        guard let fileURL else {
            statusText = "Unsaved workflow"
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sourceText.write(to: fileURL, atomically: true, encoding: .utf8)
        statusText = "Saved \(fileURL.lastPathComponent)"
        errorText = nil
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        errorText = nil
        defer { isRunning = false }

        do {
            let workflow = try WorkflowTOMLCodec.parse(sourceText)
            try save()

            let workspaceRoot = self.workspaceRoot
            let executor = self.executor
            let summary = try await Task.detached(priority: .userInitiated) {
                try executor.execute(workflow, workspaceRoot: workspaceRoot)
            }.value

            lastSummary = summary
            statusText = Self.summaryText(for: summary)
        } catch {
            errorText = error.localizedDescription
            statusText = "Workflow run failed"
        }
    }

    private func status(
        for stepID: String,
        result: WorkflowStepExecutionResult?
    ) -> String {
        guard let result else { return "Pending" }
        if result.exitCode == 0 {
            return "Completed"
        }
        if case .failed(let failedStepID, _) = lastSummary?.status,
           failedStepID == stepID {
            return "Failed"
        }
        return "Exited \(result.exitCode)"
    }

    private static func summaryText(for summary: WorkflowExecutionSummary) -> String {
        let count = summary.results.count
        let noun = count == 1 ? "step" : "steps"
        switch summary.status {
        case .completed:
            return "Workflow \(summary.workflowID) completed after \(count) \(noun)."
        case .failed(let stepID, let exitCode):
            return "Workflow \(summary.workflowID) failed at \(stepID) with exit \(exitCode)."
        }
    }

    private static func defaultWorkflowSource() -> String {
        """
        [workflow]
        id = "local"
        name = "Local Workflow"
        steps = ["verify"]

        [step.verify]
        command = "echo workflow ready"
        """
    }
}
