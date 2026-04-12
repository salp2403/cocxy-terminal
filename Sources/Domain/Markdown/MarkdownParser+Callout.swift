// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownParser+Callout.swift - Blockquote and callout parsing for markdown blocks.

import Foundation

extension MarkdownParser {
    func parseBlockquote(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock, Int)? {
        guard Self.isBlockquoteLine(lines[start]) else { return nil }

        var innerLines: [String] = []
        var cursor = start
        while cursor < lines.count, Self.isBlockquoteLine(lines[cursor]) {
            innerLines.append(Self.stripBlockquoteMarker(lines[cursor]))
            cursor += 1
        }

        if let header = innerLines.first.flatMap(MarkdownCallout.parseHeader) {
            let bodyLines = Array(innerLines.dropFirst())
            let nestedSource = bodyLines.joined(separator: "\n")
            let nestedBlocks = nestedSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : parse(nestedSource).blocks
            return (
                .callout(
                    type: header.type,
                    title: header.title,
                    isFolded: header.isFolded,
                    blocks: nestedBlocks
                ),
                cursor - start
            )
        }

        let nestedSource = innerLines.joined(separator: "\n")
        let nested = parse(nestedSource)
        return (.blockquote(blocks: nested.blocks), cursor - start)
    }

    static func isBlockquoteLine(_ line: String) -> Bool {
        let trimmed = leadingSpacesTrimmed(line, max: 3)
        return trimmed.hasPrefix(">")
    }

    static func stripBlockquoteMarker(_ line: String) -> String {
        let trimmed = leadingSpacesTrimmed(line, max: 3)
        var body = String(trimmed.dropFirst())
        if body.hasPrefix(" ") { body.removeFirst() }
        return body
    }
}
