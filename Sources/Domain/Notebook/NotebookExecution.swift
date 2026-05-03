// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookExecution.swift - Local execution for Cocxy notebook code cells.

import Foundation

enum NotebookExecutionError: Error, Sendable, Equatable {
    case unsupportedLanguage(String)
}

extension NotebookExecutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let language):
            return "Notebook language is not supported for local execution: \(language)"
        }
    }
}

struct NotebookCellExecutionResult: Sendable, Equatable {
    let cellIndex: Int
    let language: String
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        exitCode == 0
    }
}

struct NotebookExecutionSummary: Sendable, Equatable {
    let document: NotebookDocument
    let results: [NotebookCellExecutionResult]
    let executedCellIndices: [Int]
    let failedCellIndex: Int?
}

struct NotebookExecutor: Sendable {
    private let processRunner: any AgentProcessRunning

    init(processRunner: any AgentProcessRunning = AgentProcessRunner()) {
        self.processRunner = processRunner
    }

    func execute(
        _ document: NotebookDocument,
        workingDirectory: URL,
        timeoutSeconds: TimeInterval? = 60,
        stopOnFailure: Bool = true
    ) throws -> NotebookExecutionSummary {
        var nextCells = document.cells
        var results: [NotebookCellExecutionResult] = []
        var executedIndices: [Int] = []
        var failedIndex: Int?

        for index in nextCells.indices {
            let cell = nextCells[index]
            guard cell.kind == .code else { continue }
            let language = cell.language ?? "bash"
            let command = try NotebookKernelCommand(language: language, source: cell.source)
            let processResult = try processRunner.run(
                executableURL: command.executableURL,
                arguments: command.arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds
            )
            let executionResult = NotebookCellExecutionResult(
                cellIndex: index,
                language: command.language,
                exitCode: processResult.exitCode,
                stdout: processResult.stdout,
                stderr: processResult.stderr
            )
            results.append(executionResult)
            executedIndices.append(index)
            nextCells[index] = NotebookCell(
                kind: cell.kind,
                language: cell.language,
                source: cell.source,
                outputs: Self.outputs(from: processResult)
            )

            if stopOnFailure, processResult.exitCode != 0 {
                failedIndex = index
                break
            }
        }

        return NotebookExecutionSummary(
            document: NotebookDocument(metadata: document.metadata, cells: nextCells),
            results: results,
            executedCellIndices: executedIndices,
            failedCellIndex: failedIndex
        )
    }

    private static func outputs(from result: AgentProcessResult) -> [NotebookCellOutput] {
        var outputs: [NotebookCellOutput] = []
        if !result.stdout.isEmpty {
            outputs.append(NotebookCellOutput(kind: .stdout, text: result.stdout))
        }
        if !result.stderr.isEmpty {
            outputs.append(NotebookCellOutput(kind: .stderr, text: result.stderr))
        }
        if result.exitCode != 0 {
            outputs.append(NotebookCellOutput(
                kind: .error,
                text: "Process exited with code \(result.exitCode).\n"
            ))
        }
        return outputs
    }
}

private struct NotebookKernelCommand {
    let language: String
    let executableURL: URL
    let arguments: [String]

    init(language rawLanguage: String, source: String) throws {
        guard let language = NotebookCell.normalizedLanguage(rawLanguage) else {
            throw NotebookExecutionError.unsupportedLanguage(rawLanguage)
        }
        self.language = language

        switch language {
        case "bash":
            executableURL = URL(fileURLWithPath: "/bin/bash")
            arguments = ["-c", source]
        case "python":
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = ["python3", "-c", source]
        case "swift":
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = ["swift", "-e", source]
        default:
            throw NotebookExecutionError.unsupportedLanguage(language)
        }
    }
}
