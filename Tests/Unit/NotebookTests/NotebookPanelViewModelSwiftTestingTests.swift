// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookPanelViewModelSwiftTestingTests.swift - UI state for notebook panels.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Notebook panel view model")
struct NotebookPanelViewModelSwiftTestingTests {
    @Test("loads, executes, renders outputs and persists the notebook")
    @MainActor
    func runsNotebookAndPersistsRenderedOutputs() async throws {
        let workspace = try temporaryNotebookPanelDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let fileURL = workspace.appendingPathComponent("demo.cocxynb")
        try """
        ---
        cocxy-notebook: "1"
        title: "Panel Demo"
        ---

        ```bash
        echo stale
        ```
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let runner = RecordingNotebookPanelProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "panel-ok\n", stderr: ""),
        ])
        let viewModel = NotebookPanelViewModel(
            fileURL: fileURL,
            workingDirectory: workspace,
            executor: NotebookExecutor(processRunner: runner)
        )

        #expect(viewModel.title == "Panel Demo")
        #expect(viewModel.cellPresentations.map(\.language) == ["bash"])

        await viewModel.runAll()

        #expect(viewModel.statusText == "Executed 1 notebook cell.")
        #expect(viewModel.errorText == nil)
        #expect(viewModel.sourceText.contains("panel-ok"))
        #expect(viewModel.cellPresentations.first?.outputs.map(\.text) == ["panel-ok\n"])
        #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("panel-ok"))
        #expect(runner.calls.map(\.executableURL.path) == ["/usr/bin/sandbox-exec"])
        #expect(Array(runner.calls[0].arguments.suffix(3)) == [
            "/bin/bash",
            "-c",
            "echo stale",
        ])
    }

    @Test("Spanish localizer updates notebook status text")
    @MainActor
    func spanishLocalizerUpdatesNotebookStatusText() async throws {
        let workspace = try temporaryNotebookPanelDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let runner = RecordingNotebookPanelProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
        ])
        let viewModel = NotebookPanelViewModel(
            fileURL: nil,
            workingDirectory: workspace,
            executor: NotebookExecutor(processRunner: runner),
            localizer: spanish
        )

        #expect(viewModel.statusText == "Notebook nuevo")
        #expect(viewModel.title == "Notebook sin título")
        #expect(!viewModel.sourceText.contains("Untitled Notebook"))
        viewModel.sourceText = ""
        #expect(viewModel.title == "Notebook sin título")
        viewModel.sourceText = """
        ```bash
        echo ok
        ```
        """

        await viewModel.runAll()

        #expect(viewModel.statusText == "1 celda de notebook ejecutada.")

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))

        #expect(viewModel.statusText == "Executed 1 notebook cell.")
    }
}

private final class RecordingNotebookPanelProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [NotebookPanelProcessCall] = []
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
        calls.append(NotebookPanelProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        ))
        return results.removeFirst()
    }
}

private struct NotebookPanelProcessCall: Equatable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private func temporaryNotebookPanelDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-notebook-panel-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
