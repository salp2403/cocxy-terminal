// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookModels.swift - Pure domain values for Cocxy notebooks.

import Foundation

struct NotebookMetadata: Codable, Sendable, Equatable {
    let title: String?
    let tags: [String]

    init(title: String? = nil, tags: [String] = []) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        self.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum NotebookCellKind: String, Codable, Sendable, Equatable {
    case markdown
    case code
}

enum NotebookCellOutputKind: String, Codable, Sendable, Equatable {
    case stdout
    case stderr
    case displayData = "display-data"
    case error
}

struct NotebookCellOutput: Codable, Sendable, Equatable {
    let kind: NotebookCellOutputKind
    let text: String

    init(kind: NotebookCellOutputKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

struct NotebookCell: Codable, Sendable, Equatable {
    let kind: NotebookCellKind
    let language: String?
    let source: String
    let outputs: [NotebookCellOutput]

    init(
        kind: NotebookCellKind,
        language: String? = nil,
        source: String,
        outputs: [NotebookCellOutput] = []
    ) {
        self.kind = kind
        self.language = language.flatMap(Self.normalizedLanguage)
        self.source = source
        self.outputs = outputs
    }

    static func markdown(_ source: String) -> NotebookCell {
        NotebookCell(kind: .markdown, source: source)
    }

    static func code(
        language: String,
        source: String,
        outputs: [NotebookCellOutput] = []
    ) -> NotebookCell {
        NotebookCell(
            kind: .code,
            language: language,
            source: source,
            outputs: outputs
        )
    }

    static func normalizedLanguage(_ raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "py":
            return "python"
        case "shell", "sh", "zsh":
            return "bash"
        default:
            return normalized
        }
    }
}

struct NotebookDocument: Codable, Sendable, Equatable {
    let metadata: NotebookMetadata
    let cells: [NotebookCell]

    init(
        metadata: NotebookMetadata = NotebookMetadata(),
        cells: [NotebookCell] = []
    ) {
        self.metadata = metadata
        self.cells = cells
    }

    static func parseMarkdown(_ source: String) -> NotebookDocument {
        NotebookMarkdownCodec.parse(source)
    }
}
