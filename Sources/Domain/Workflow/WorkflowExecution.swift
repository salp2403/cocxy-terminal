// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowExecution.swift - Sequential local workflow execution.

import Foundation

enum WorkflowExecutionError: Error, Sendable, Equatable {
    case workingDirectoryEscapesRoot(String)
    case workingDirectoryMissing(String)
}

extension WorkflowExecutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .workingDirectoryEscapesRoot(let path):
            return "Workflow working directory escapes the workspace root: \(path)"
        case .workingDirectoryMissing(let path):
            return "Workflow working directory does not exist: \(path)"
        }
    }
}

enum WorkflowExecutionStatus: Sendable, Equatable {
    case completed
    case failed(stepID: String, exitCode: Int32)
}

struct WorkflowStepExecutionResult: Sendable, Equatable {
    let stepID: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct WorkflowExecutionSummary: Sendable, Equatable {
    let workflowID: String
    let status: WorkflowExecutionStatus
    let results: [WorkflowStepExecutionResult]
}

struct WorkflowExecutor: Sendable {
    private let processRunner: any AgentProcessRunning
    private let defaultTimeoutSeconds: TimeInterval

    init(
        processRunner: any AgentProcessRunning = AgentProcessRunner(),
        defaultTimeoutSeconds: TimeInterval = 300
    ) {
        self.processRunner = processRunner
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
    }

    func execute(
        _ workflow: WorkflowDocument,
        workspaceRoot: URL
    ) throws -> WorkflowExecutionSummary {
        var results: [WorkflowStepExecutionResult] = []
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()

        for step in workflow.steps {
            let workingDirectory = try resolveWorkingDirectory(
                step.workingDirectory,
                workspaceRoot: root
            )
            let processResult = try processRunner.run(
                executableURL: step.shell.executableURL,
                arguments: step.shell.commandArguments(for: step.command),
                workingDirectory: workingDirectory,
                timeoutSeconds: step.timeoutSeconds ?? defaultTimeoutSeconds
            )
            results.append(WorkflowStepExecutionResult(
                stepID: step.id,
                exitCode: processResult.exitCode,
                stdout: processResult.stdout,
                stderr: processResult.stderr
            ))

            if processResult.exitCode != 0, !step.continueOnFailure {
                return WorkflowExecutionSummary(
                    workflowID: workflow.id,
                    status: .failed(stepID: step.id, exitCode: processResult.exitCode),
                    results: results
                )
            }
        }

        return WorkflowExecutionSummary(
            workflowID: workflow.id,
            status: .completed,
            results: results
        )
    }

    private func resolveWorkingDirectory(
        _ rawPath: String?,
        workspaceRoot: URL
    ) throws -> URL {
        guard let rawPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return workspaceRoot
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed, isDirectory: true)
            : workspaceRoot.appendingPathComponent(trimmed, isDirectory: true)
        let standardized = candidate.standardizedFileURL.resolvingSymlinksInPath()

        guard isInsideWorkspace(standardized, root: workspaceRoot) else {
            throw WorkflowExecutionError.workingDirectoryEscapesRoot(rawPath)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw WorkflowExecutionError.workingDirectoryMissing(rawPath)
        }
        return standardized
    }

    private func isInsideWorkspace(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
