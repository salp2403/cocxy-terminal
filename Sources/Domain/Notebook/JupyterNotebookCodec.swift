// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// JupyterNotebookCodec.swift - nbformat 4 import/export for Cocxy notebooks.

import Foundation

enum JupyterNotebookCodec {
    enum CodecError: Error, Sendable, Equatable {
        case unsupportedFormat(nbformat: Int)
    }

    static func exportData(from notebook: NotebookDocument) throws -> Data {
        let firstCodeLanguage = notebook.cells.first(where: { $0.kind == .code })?.language
        let jupyter = JupyterNotebook(
            nbformat: 4,
            nbformatMinor: 5,
            metadata: JupyterNotebookMetadata(
                kernelspec: firstCodeLanguage.map {
                    JupyterKernelspec(displayName: $0, language: $0, name: $0)
                },
                cocxy: JupyterCocxyNotebookMetadata(title: notebook.metadata.title)
            ),
            cells: notebook.cells.map(exportCell)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(jupyter)
    }

    static func importDocument(from data: Data) throws -> NotebookDocument {
        let decoder = JSONDecoder()
        let jupyter = try decoder.decode(JupyterNotebook.self, from: data)
        guard jupyter.nbformat == 4 else {
            throw CodecError.unsupportedFormat(nbformat: jupyter.nbformat)
        }

        let fallbackLanguage = NotebookCell.normalizedLanguage(
            jupyter.metadata.kernelspec?.language ?? ""
        ) ?? "python"
        let metadata = NotebookMetadata(
            title: jupyter.metadata.cocxy?.title
        )
        let cells = jupyter.cells.compactMap { cell -> NotebookCell? in
            importCell(cell, fallbackLanguage: fallbackLanguage)
        }
        return NotebookDocument(metadata: metadata, cells: cells)
    }

    private static func exportCell(_ cell: NotebookCell) -> JupyterCell {
        switch cell.kind {
        case .markdown:
            return JupyterCell(
                cellType: "markdown",
                metadata: JupyterCellMetadata(cocxy: nil),
                source: .lines(splitPreservingNewlines(cell.source)),
                executionCount: nil,
                outputs: nil
            )
        case .code:
            return JupyterCell(
                cellType: "code",
                metadata: JupyterCellMetadata(
                    cocxy: JupyterCocxyCellMetadata(language: cell.language)
                ),
                source: .lines(splitPreservingNewlines(cell.source)),
                executionCount: nil,
                outputs: cell.outputs.map(exportOutput)
            )
        }
    }

    private static func importCell(
        _ cell: JupyterCell,
        fallbackLanguage: String
    ) -> NotebookCell? {
        switch cell.cellType {
        case "markdown":
            return .markdown(cell.source.joined)
        case "code":
            let language = NotebookCell.normalizedLanguage(
                cell.metadata.cocxy?.language ?? ""
            ) ?? fallbackLanguage
            return .code(
                language: language,
                source: cell.source.joined,
                outputs: cell.outputs?.compactMap(importOutput) ?? []
            )
        default:
            return nil
        }
    }

    private static func exportOutput(_ output: NotebookCellOutput) -> JupyterOutput {
        switch output.kind {
        case .stdout:
            return JupyterOutput(
                outputType: "stream",
                name: "stdout",
                text: .lines(splitPreservingNewlines(output.text)),
                data: nil,
                traceback: nil
            )
        case .stderr:
            return JupyterOutput(
                outputType: "stream",
                name: "stderr",
                text: .lines(splitPreservingNewlines(output.text)),
                data: nil,
                traceback: nil
            )
        case .displayData:
            return JupyterOutput(
                outputType: "display_data",
                name: nil,
                text: nil,
                data: ["text/plain": .lines(splitPreservingNewlines(output.text))],
                traceback: nil
            )
        case .error:
            return JupyterOutput(
                outputType: "error",
                name: nil,
                text: nil,
                data: nil,
                traceback: splitPreservingNewlines(output.text)
            )
        }
    }

    private static func importOutput(_ output: JupyterOutput) -> NotebookCellOutput? {
        switch output.outputType {
        case "stream":
            let kind: NotebookCellOutputKind = output.name == "stderr" ? .stderr : .stdout
            return NotebookCellOutput(kind: kind, text: output.text?.joined ?? "")
        case "display_data", "execute_result":
            return NotebookCellOutput(
                kind: .displayData,
                text: output.data?["text/plain"]?.joined ?? ""
            )
        case "error":
            return NotebookCellOutput(
                kind: .error,
                text: output.traceback?.joined() ?? ""
            )
        default:
            return nil
        }
    }

    private static func splitPreservingNewlines(_ value: String) -> [String] {
        guard !value.isEmpty else { return [] }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.count > 1 else { return [value] }

        var result: [String] = []
        for index in lines.indices {
            if index < lines.index(before: lines.endIndex) {
                result.append(lines[index] + "\n")
            } else if !lines[index].isEmpty {
                result.append(lines[index])
            }
        }
        return result
    }
}

private struct JupyterNotebook: Codable {
    let nbformat: Int
    let nbformatMinor: Int
    let metadata: JupyterNotebookMetadata
    let cells: [JupyterCell]

    enum CodingKeys: String, CodingKey {
        case nbformat
        case nbformatMinor = "nbformat_minor"
        case metadata
        case cells
    }
}

private struct JupyterNotebookMetadata: Codable {
    let kernelspec: JupyterKernelspec?
    let cocxy: JupyterCocxyNotebookMetadata?
}

private struct JupyterKernelspec: Codable {
    let displayName: String
    let language: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case language
        case name
    }
}

private struct JupyterCocxyNotebookMetadata: Codable {
    let title: String?
}

private struct JupyterCell: Codable {
    let cellType: String
    let metadata: JupyterCellMetadata
    let source: JupyterText
    let executionCount: Int?
    let outputs: [JupyterOutput]?

    enum CodingKeys: String, CodingKey {
        case cellType = "cell_type"
        case metadata
        case source
        case executionCount = "execution_count"
        case outputs
    }
}

private struct JupyterCellMetadata: Codable {
    let cocxy: JupyterCocxyCellMetadata?
}

private struct JupyterCocxyCellMetadata: Codable {
    let language: String?
}

private struct JupyterOutput: Codable {
    let outputType: String
    let name: String?
    let text: JupyterText?
    let data: [String: JupyterText]?
    let traceback: [String]?

    enum CodingKeys: String, CodingKey {
        case outputType = "output_type"
        case name
        case text
        case data
        case traceback
    }
}

private enum JupyterText: Codable, Equatable {
    case string(String)
    case lines([String])

    var joined: String {
        switch self {
        case .string(let value):
            return value
        case .lines(let lines):
            return lines.joined()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .lines(try container.decode([String].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .lines(let lines):
            try container.encode(lines)
        }
    }
}
