// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowPanelViewModel.swift - State and execution for workflow panels.

import Combine
import Foundation

struct WorkflowStepPresentation: Identifiable, Equatable {
    enum StatusKind: Equatable {
        case pending
        case completed
        case failed
        case exited(Int32)
    }

    let id: String
    let title: String?
    let command: String
    let shell: WorkflowShell
    let status: String
    let statusKind: StatusKind
    let stdout: String
    let stderr: String
    let exitCode: Int32?
}

@MainActor
final class WorkflowPanelViewModel: ObservableObject {
    private enum StatusState {
        case loaded(String)
        case new
        case unsaved
        case saved(String)
        case runFailed
        case summary(WorkflowExecutionSummary)
    }

    @Published var sourceText: String
    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?
    @Published private(set) var isRunning = false
    @Published private var lastSummary: WorkflowExecutionSummary?

    let fileURL: URL?
    let workspaceRoot: URL

    private let executor: WorkflowExecutor
    private var localizer: AppLocalizer
    private var statusState: StatusState

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
            let status = statusPresentation(for: step.id, result: result)
            return WorkflowStepPresentation(
                id: step.id,
                title: step.title,
                command: step.command,
                shell: step.shell,
                status: status.text,
                statusKind: status.kind,
                stdout: result?.stdout ?? "",
                stderr: result?.stderr ?? "",
                exitCode: result?.exitCode
            )
        }
    }

    init(
        fileURL: URL?,
        workspaceRoot: URL,
        executor: WorkflowExecutor = WorkflowExecutor(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.fileURL = fileURL
        self.workspaceRoot = workspaceRoot
        self.executor = executor
        self.localizer = localizer

        if let fileURL,
           let loaded = try? String(contentsOf: fileURL, encoding: .utf8) {
            sourceText = loaded
            statusState = .loaded(fileURL.lastPathComponent)
        } else {
            sourceText = Self.defaultWorkflowSource()
            statusState = .new
        }
        statusText = Self.localizedStatusText(statusState, localizer: localizer)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        statusText = Self.localizedStatusText(statusState, localizer: localizer)
    }

    func save() throws {
        guard let fileURL else {
            setStatus(.unsaved)
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sourceText.write(to: fileURL, atomically: true, encoding: .utf8)
        setStatus(.saved(fileURL.lastPathComponent))
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
            setStatus(.summary(summary))
        } catch {
            errorText = error.localizedDescription
            setStatus(.runFailed)
        }
    }

    private func statusPresentation(
        for stepID: String,
        result: WorkflowStepExecutionResult?
    ) -> (text: String, kind: WorkflowStepPresentation.StatusKind) {
        guard let result else {
            return (
                localizer.string("workflow.step.status.pending", fallback: "Pending"),
                .pending
            )
        }
        if result.exitCode == 0 {
            return (
                localizer.string("workflow.step.status.completed", fallback: "Completed"),
                .completed
            )
        }
        if case .failed(let failedStepID, _) = lastSummary?.status,
           failedStepID == stepID {
            return (
                localizer.string("workflow.step.status.failed", fallback: "Failed"),
                .failed
            )
        }
        return (
            String(
                format: localizer.string("workflow.step.status.exited", fallback: "Exited %d"),
                result.exitCode
            ),
            .exited(result.exitCode)
        )
    }

    private func setStatus(_ state: StatusState) {
        statusState = state
        statusText = Self.localizedStatusText(state, localizer: localizer)
    }

    private static func localizedStatusText(_ state: StatusState, localizer: AppLocalizer) -> String {
        switch state {
        case .loaded(let name):
            return String(format: localizer.string("workflow.status.loaded", fallback: "Loaded %@"), name)
        case .new:
            return localizer.string("workflow.status.new", fallback: "New workflow")
        case .unsaved:
            return localizer.string("workflow.status.unsaved", fallback: "Unsaved workflow")
        case .saved(let name):
            return String(format: localizer.string("workflow.status.saved", fallback: "Saved %@"), name)
        case .runFailed:
            return localizer.string("workflow.status.runFailed", fallback: "Workflow run failed")
        case .summary(let summary):
            return summaryText(for: summary, localizer: localizer)
        }
    }

    private static func summaryText(
        for summary: WorkflowExecutionSummary,
        localizer: AppLocalizer
    ) -> String {
        let count = summary.results.count
        switch summary.status {
        case .completed:
            return String(
                format: localizer.string(
                    count == 1
                        ? "workflow.status.completed.one"
                        : "workflow.status.completed.many",
                    fallback: count == 1
                        ? "Workflow %@ completed after %d step."
                        : "Workflow %@ completed after %d steps."
                ),
                summary.workflowID,
                count
            )
        case .failed(let stepID, let exitCode):
            return String(
                format: localizer.string(
                    "workflow.status.failed",
                    fallback: "Workflow %@ failed at %@ with exit %d."
                ),
                summary.workflowID,
                stepID,
                exitCode
            )
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
