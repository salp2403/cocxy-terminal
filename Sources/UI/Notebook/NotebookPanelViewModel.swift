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
    private enum StatusState {
        case loaded(String)
        case new
        case unsaved
        case saved(String)
        case runFailed
        case summary(NotebookExecutionSummary)
    }

    @Published var sourceText: String
    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?
    @Published private(set) var isRunning = false

    let fileURL: URL?
    let workingDirectory: URL

    private let executor: NotebookExecutor
    private var localizer: AppLocalizer
    private var statusState: StatusState

    var document: NotebookDocument {
        NotebookDocument.parseMarkdown(sourceText)
    }

    var title: String {
        document.metadata.title
            ?? fileURL?.lastPathComponent
            ?? localizer.string("notebook.untitledTitle", fallback: "Untitled Notebook")
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
        executor: NotebookExecutor = NotebookExecutor(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.fileURL = fileURL
        self.workingDirectory = workingDirectory
        self.executor = executor
        self.localizer = localizer

        if let fileURL,
           let loaded = try? String(contentsOf: fileURL, encoding: .utf8) {
            sourceText = loaded
            statusState = .loaded(fileURL.lastPathComponent)
        } else {
            sourceText = Self.defaultNotebookSource()
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
            setStatus(.summary(summary))
        } catch {
            errorText = error.localizedDescription
            setStatus(.runFailed)
        }
    }

    private func setStatus(_ state: StatusState) {
        statusState = state
        statusText = Self.localizedStatusText(state, localizer: localizer)
    }

    private static func localizedStatusText(_ state: StatusState, localizer: AppLocalizer) -> String {
        switch state {
        case .loaded(let name):
            return String(format: localizer.string("notebook.status.loaded", fallback: "Loaded %@"), name)
        case .new:
            return localizer.string("notebook.status.new", fallback: "New notebook")
        case .unsaved:
            return localizer.string("notebook.status.unsaved", fallback: "Unsaved notebook")
        case .saved(let name):
            return String(format: localizer.string("notebook.status.saved", fallback: "Saved %@"), name)
        case .runFailed:
            return localizer.string("notebook.status.runFailed", fallback: "Notebook run failed")
        case .summary(let summary):
            return summaryText(for: summary, localizer: localizer)
        }
    }

    private static func summaryText(
        for summary: NotebookExecutionSummary,
        localizer: AppLocalizer
    ) -> String {
        let count = summary.executedCellIndices.count
        if let failedIndex = summary.failedCellIndex {
            return String(
                format: localizer.string(
                    count == 1
                        ? "notebook.status.stopped.one"
                        : "notebook.status.stopped.many",
                    fallback: count == 1
                        ? "Notebook stopped at cell %d after %d cell."
                        : "Notebook stopped at cell %d after %d cells."
                ),
                failedIndex,
                count
            )
        }
        if let failedResult = summary.results.first(where: { !$0.succeeded }) {
            return String(
                format: localizer.string(
                    count == 1
                        ? "notebook.status.failed.one"
                        : "notebook.status.failed.many",
                    fallback: count == 1
                        ? "Notebook failed at cell %d after %d cell."
                        : "Notebook failed at cell %d after %d cells."
                ),
                failedResult.cellIndex,
                count
            )
        }
        return String(
            format: localizer.string(
                count == 1
                    ? "notebook.status.executed.one"
                    : "notebook.status.executed.many",
                fallback: count == 1
                    ? "Executed %d notebook cell."
                    : "Executed %d notebook cells."
            ),
            count
        )
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
