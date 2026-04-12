// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownParser+Footnote.swift - Footnote definition parsing for markdown blocks.

import Foundation

extension MarkdownParser {
    func parseFootnoteDefinition(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock, Int)? {
        let line = lines[start]
        guard let header = matchFootnoteDefinitionHeader(line) else {
            return nil
        }

        var bodyLines: [String] = [header.initialBody]
        var cursor = start + 1

        while cursor < lines.count {
            let raw = lines[cursor]
            if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                bodyLines.append("")
                cursor += 1
                continue
            }
            if raw.hasPrefix("    ") {
                bodyLines.append(String(raw.dropFirst(4)))
                cursor += 1
                continue
            }
            if raw.hasPrefix("\t") {
                bodyLines.append(String(raw.dropFirst()))
                cursor += 1
                continue
            }
            break
        }

        let nestedSource = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let nestedBlocks = nestedSource.isEmpty ? [] : parse(nestedSource).blocks
        return (.footnoteDefinition(id: header.id, blocks: nestedBlocks), max(1, cursor - start))
    }

    func matchFootnoteDefinitionHeader(_ line: String) -> (id: String, initialBody: String)? {
        let trimmed = MarkdownParser.leadingSpacesTrimmed(line, max: 3)
        guard trimmed.hasPrefix("[^"),
              let closing = trimmed.firstIndex(of: "]") else {
            return nil
        }

        let idStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
        guard idStart < closing else { return nil }
        let id = String(trimmed[idStart..<closing])
        guard !id.isEmpty else { return nil }

        let colonIndex = trimmed.index(after: closing)
        guard colonIndex < trimmed.endIndex, trimmed[colonIndex] == ":" else {
            return nil
        }

        let bodyStart = trimmed.index(after: colonIndex)
        let initialBody = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespaces)
        return (id: id, initialBody: initialBody)
    }
}
