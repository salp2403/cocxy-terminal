// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookPanelViewModel.swift - State and execution for notebook panels.

import Combine
import Foundation

struct NotebookOutputPresentation: Identifiable, Equatable {
    let id: String
    let kind: NotebookCellOutputKind
    let text: String
}

struct NotebookCellPresentation: Identifiable, Equatable {
    let id: Int
    let index: Int
    let kind: NotebookCellKind
    let language: String?
    let source: String
    let outputs: [NotebookOutputPresentation]
}

@MainActor
final class NotebookPanelViewModel: ObservableObject {
    @Published var sourceText: String
    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?
    @Published private(set) var isRunning = false

    let fileURL: URL?
    let workingDirectory: URL

    private let executor: NotebookExecutor

    var document: NotebookDocument {
        NotebookDocument.parseMarkdown(sourceText)
    }

    var title: String {
        document.metadata.title
            ?? fileURL?.lastPathComponent
            ?? "Untitled Notebook"
    }

    var cellPresentations: [NotebookCellPresentation] {
        document.cells.enumerated().map { index, cell in
            NotebookCellPresentation(
                id: index,
                index: index,
                kind: cell.kind,
                language: cell.language,
                source: cell.source,
                outputs: cell.outputs.enumerated().map { outputIndex, output in
                    NotebookOutputPresentation(
                        id: "\(index)-\(outputIndex)-\(output.kind.rawValue)",
                        kind: output.kind,
                        text: output.text
                    )
                }
            )
        }
    }

    init(
        fileURL: URL?,
        workingDirectory: URL,
        executor: NotebookExecutor = NotebookExecutor()
    ) {
        self.fileURL = fileURL
        self.workingDirectory = workingDirectory
        self.executor = executor

        if let fileURL,
           let loaded = try? String(contentsOf: fileURL, encoding: .utf8) {
            sourceText = loaded
            statusText = "Loaded \(fileURL.lastPathComponent)"
        } else {
            sourceText = Self.defaultNotebookSource()
            statusText = "New notebook"
        }
    }

    func save() throws {
        guard let fileURL else {
            statusText = "Unsaved notebook"
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

    func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        errorText = nil
        defer { isRunning = false }

        let document = NotebookDocument.parseMarkdown(sourceText)
        let workingDirectory = self.workingDirectory
        let executor = self.executor

        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                try executor.execute(
                    document,
                    workingDirectory: workingDirectory,
                    timeoutSeconds: 60,
                    stopOnFailure: true
                )
            }.value

            sourceText = NotebookMarkdownCodec.render(summary.document)
            try save()
            statusText = Self.summaryText(for: summary)
        } catch {
            errorText = error.localizedDescription
            statusText = "Notebook run failed"
        }
    }

    private static func summaryText(for summary: NotebookExecutionSummary) -> String {
        let count = summary.executedCellIndices.count
        let noun = count == 1 ? "cell" : "cells"
        if let failedIndex = summary.failedCellIndex {
            return "Notebook stopped at cell \(failedIndex) after \(count) \(noun)."
        }
        if let failedResult = summary.results.first(where: { !$0.succeeded }) {
            return "Notebook failed at cell \(failedResult.cellIndex) after \(count) \(noun)."
        }
        return "Executed \(count) notebook \(noun)."
    }

    private static func defaultNotebookSource() -> String {
        """
        ---
        cocxy-notebook: "1"
        title: "Untitled Notebook"
        ---

        ```bash
        echo "hello from Cocxy"
        ```
        """
    }
}
