// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookMarkdownCodec.swift - Canonical `.cocxynb` markdown parser/renderer.

import Foundation
import CocxyMarkdownLib

enum NotebookMarkdownCodec {
    private static let outputFenceInfoPrefix = "cocxy-output"

    private static let executableLanguages: Set<String> = [
        "bash",
        "python",
        "swift",
    ]

    static func parse(_ source: String) -> NotebookDocument {
        let extraction = MarkdownFrontmatter.extract(from: source)
        let metadata = NotebookMetadata(
            title: extraction.frontmatter.scalars["title"],
            tags: extraction.frontmatter.lists["tags"] ?? []
        )
        return NotebookDocument(
            metadata: metadata,
            cells: parseCells(from: extraction.body)
        )
    }

    static func render(_ notebook: NotebookDocument) -> String {
        var parts: [String] = [renderFrontmatter(notebook.metadata)]
        parts.append(contentsOf: notebook.cells.map(renderCell))
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func parseCells(from body: String) -> [NotebookCell] {
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalizedBody.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard !lines.isEmpty else { return [] }

        var cells: [NotebookCell] = []
        var markdownLines: [String] = []
        var index = 0

        func flushMarkdown() {
            let source = trimBoundaryNewlines(markdownLines.joined(separator: "\n"))
            if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cells.append(.markdown(source))
            }
            markdownLines = []
        }

        while index < lines.count {
            let line = lines[index]
            if let fence = parseExecutableFenceStart(line) {
                flushMarkdown()
                index += 1
                var codeLines: [String] = []

                while index < lines.count, !isFenceClose(lines[index], marker: fence.marker) {
                    codeLines.append(lines[index])
                    index += 1
                }

                if index < lines.count {
                    index += 1
                }

                let outputParse = parseAttachedOutputs(from: lines, startingAt: index)
                index = outputParse.nextIndex

                cells.append(.code(
                    language: fence.language,
                    source: trimBoundaryNewlines(codeLines.joined(separator: "\n")),
                    outputs: outputParse.outputs
                ))
            } else {
                markdownLines.append(line)
                index += 1
            }
        }

        flushMarkdown()
        return cells
    }

    private static func renderFrontmatter(_ metadata: NotebookMetadata) -> String {
        var lines = [
            "---",
            "cocxy-notebook: \"1\"",
        ]

        if let title = metadata.title {
            lines.append("title: \"\(escapeYAMLString(title))\"")
        }
        if !metadata.tags.isEmpty {
            lines.append("tags: [\(metadata.tags.joined(separator: ", "))]")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func renderCell(_ cell: NotebookCell) -> String {
        switch cell.kind {
        case .markdown:
            return trimBoundaryNewlines(cell.source)
        case .code:
            let language = cell.language ?? "bash"
            var parts = ["""
            ```\(language)
            \(trimBoundaryNewlines(cell.source))
            ```
            """]
            parts.append(contentsOf: cell.outputs.map(renderOutput))
            return parts.joined(separator: "\n\n")
        }
    }

    private static func renderOutput(_ output: NotebookCellOutput) -> String {
        let finalNewlineFlag = output.text.hasSuffix("\n") ? "" : " no-final-newline"
        let closingSeparator = output.text.hasSuffix("\n") ? "" : "\n"
        return """
        ```\(outputFenceInfoPrefix) \(output.kind.rawValue)\(finalNewlineFlag)
        \(output.text)\(closingSeparator)```
        """
    }

    private static func parseExecutableFenceStart(_ line: String) -> (marker: String, language: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker: String
        if trimmed.hasPrefix("```") {
            marker = "```"
        } else if trimmed.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }

        let info = trimmed.dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawLanguage = info.split(separator: " ").first.map(String.init),
              let language = NotebookCell.normalizedLanguage(rawLanguage),
              executableLanguages.contains(language)
        else {
            return nil
        }

        return (marker, language)
    }

    private static func parseAttachedOutputs(
        from lines: [String],
        startingAt startingIndex: Int
    ) -> (outputs: [NotebookCellOutput], nextIndex: Int) {
        var cursor = startingIndex
        var outputs: [NotebookCellOutput] = []

        while cursor < lines.count {
            let blankStart = cursor
            while cursor < lines.count,
                  lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cursor += 1
            }

            guard cursor < lines.count,
                  let fence = parseOutputFenceStart(lines[cursor])
            else {
                return (outputs, outputs.isEmpty ? startingIndex : blankStart)
            }

            cursor += 1
            var outputLines: [String] = []
            while cursor < lines.count, !isFenceClose(lines[cursor], marker: fence.marker) {
                outputLines.append(lines[cursor])
                cursor += 1
            }

            if cursor < lines.count {
                cursor += 1
            }

            outputs.append(NotebookCellOutput(
                kind: fence.kind,
                text: outputText(
                    from: outputLines,
                    preservesFinalNewline: fence.preservesFinalNewline
                )
            ))
        }

        return (outputs, cursor)
    }

    private static func parseOutputFenceStart(
        _ line: String
    ) -> (marker: String, kind: NotebookCellOutputKind, preservesFinalNewline: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker: String
        if trimmed.hasPrefix("```") {
            marker = "```"
        } else if trimmed.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }

        let info = trimmed.dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = info.split(separator: " ").map(String.init)
        guard parts.first == outputFenceInfoPrefix else {
            return nil
        }
        parts.removeFirst()
        guard let rawKind = parts.first else {
            return nil
        }

        let normalizedKind = rawKind.replacingOccurrences(of: "_", with: "-")
        guard let kind = NotebookCellOutputKind(rawValue: normalizedKind) else {
            return nil
        }
        return (marker, kind, !parts.contains("no-final-newline"))
    }

    private static func outputText(
        from lines: [String],
        preservesFinalNewline: Bool
    ) -> String {
        let body = lines.joined(separator: "\n")
        guard preservesFinalNewline, !lines.isEmpty else {
            return body
        }
        return body + "\n"
    }

    private static func isFenceClose(_ line: String, marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(marker)
    }

    private static func trimBoundaryNewlines(_ value: String) -> String {
        var result = value
        while result.hasPrefix("\n") {
            result.removeFirst()
        }
        while result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

    private static func escapeYAMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
