// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookExecutionSwiftTestingTests.swift - Local notebook execution coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Notebook execution")
struct NotebookExecutionSwiftTestingTests {
    @Test("executes supported code cells and replaces outputs while preserving markdown")
    func executesSupportedCodeCells() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingNotebookProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "bash ok\n", stderr: ""),
            AgentProcessResult(exitCode: 0, stdout: "", stderr: "swift warn\n"),
        ])
        let executor = NotebookExecutor(processRunner: runner)
        let document = NotebookDocument(cells: [
            .markdown("# Setup"),
            .code(
                language: "bash",
                source: "echo bash",
                outputs: [NotebookCellOutput(kind: .stdout, text: "stale\n")]
            ),
            .code(language: "swift", source: #"print("swift")"#),
        ])

        let summary = try executor.execute(
            document,
            workingDirectory: workspace,
            timeoutSeconds: 12
        )

        #expect(summary.executedCellIndices == [1, 2])
        #expect(summary.failedCellIndex == nil)
        #expect(summary.document.cells[0] == .markdown("# Setup"))
        #expect(summary.document.cells[1].outputs == [
            NotebookCellOutput(kind: .stdout, text: "bash ok\n"),
        ])
        #expect(summary.document.cells[2].outputs == [
            NotebookCellOutput(kind: .stderr, text: "swift warn\n"),
        ])
        #expect(runner.calls.map(\.executablePath) == ["/usr/bin/sandbox-exec", "/usr/bin/sandbox-exec"])
        #expect(Array(runner.calls[0].arguments.suffix(3)) == [
            "/bin/bash",
            "-c",
            "echo bash",
        ])
        #expect(Array(runner.calls[1].arguments.suffix(4)) == [
            "/usr/bin/env",
            "swift",
            "-e",
            #"print("swift")"#,
        ])
        #expect(runner.calls.map(\.timeoutSeconds) == [12, 12])
    }

    @Test("stops on first failing code cell by default")
    func stopsOnFirstFailingCodeCell() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingNotebookProcessRunner(results: [
            AgentProcessResult(exitCode: 2, stdout: "", stderr: "failed\n"),
            AgentProcessResult(exitCode: 0, stdout: "should not run\n", stderr: ""),
        ])
        let executor = NotebookExecutor(processRunner: runner)
        let document = NotebookDocument(cells: [
            .code(language: "python", source: "raise SystemExit(2)"),
            .code(language: "bash", source: "echo later"),
        ])

        let summary = try executor.execute(document, workingDirectory: workspace)

        #expect(summary.executedCellIndices == [0])
        #expect(summary.failedCellIndex == 0)
        #expect(summary.results.map(\.exitCode) == [2])
        #expect(summary.document.cells[0].outputs == [
            NotebookCellOutput(kind: .stderr, text: "failed\n"),
            NotebookCellOutput(kind: .error, text: "Process exited with code 2.\n"),
        ])
        #expect(summary.document.cells[1].outputs.isEmpty)
        #expect(runner.calls.count == 1)
    }

    @Test("rejects unsupported notebook languages before spawning a process")
    func rejectsUnsupportedLanguages() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingNotebookProcessRunner()
        let executor = NotebookExecutor(processRunner: runner)
        let document = NotebookDocument(cells: [
            .code(language: "ruby", source: "puts 'nope'"),
        ])

        #expect(throws: NotebookExecutionError.unsupportedLanguage("ruby")) {
            _ = try executor.execute(document, workingDirectory: workspace)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("workspace sandbox wraps kernels with sandbox-exec and keeps an explicit no-sandbox escape hatch")
    func workspaceSandboxWrapsKernelCommands() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = RecordingNotebookProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "sandboxed\n", stderr: ""),
            AgentProcessResult(exitCode: 0, stdout: "direct\n", stderr: ""),
        ])
        let executor = NotebookExecutor(processRunner: runner)
        let document = NotebookDocument(cells: [
            .code(language: "bash", source: "echo sandboxed"),
        ])

        _ = try executor.execute(document, workingDirectory: workspace, sandbox: .workspace)
        _ = try executor.execute(document, workingDirectory: workspace, sandbox: .none)

        #expect(runner.calls[0].executablePath == "/usr/bin/sandbox-exec")
        #expect(runner.calls[0].arguments.first == "-p")
        #expect(runner.calls[0].arguments[1].contains("(deny network*)"))
        #expect(runner.calls[0].arguments[1].contains("(deny file-write*)"))
        #expect(runner.calls[0].arguments[1].contains(workspace.resolvingSymlinksInPath().path))
        #expect(Array(runner.calls[0].arguments.suffix(3)) == [
            "/bin/bash",
            "-c",
            "echo sandboxed",
        ])
        #expect(runner.calls[1].executablePath == "/bin/bash")
        #expect(runner.calls[1].arguments == ["-c", "echo sandboxed"])
    }

    @Test("saves and reloads notebooks through markdown persistence")
    func savesAndReloadsNotebookDocuments() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotebookFileStore(directory: directory)
        let document = NotebookDocument(
            metadata: NotebookMetadata(title: "Persisted"),
            cells: [.code(language: "bash", source: "echo persisted")]
        )

        let url = try store.save(document, named: "demo.cocxynb")
        let loaded = try store.load(from: url)

        #expect(url.deletingLastPathComponent() == directory)
        #expect(loaded == document)
    }
}

private final class RecordingNotebookProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [NotebookProcessCall] = []
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
        calls.append(NotebookProcessCall(
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

private struct NotebookProcessCall: Equatable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-notebook-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
