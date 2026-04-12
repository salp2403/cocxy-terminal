// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownFootnote.swift - Footnote identifier helpers for markdown rendering.

import Foundation

enum MarkdownFootnote {
    static func anchorID(for rawID: String) -> String {
        let lowered = rawID.lowercased()
        let filtered = lowered.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "-"
        }
        let collapsed = String(filtered).replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func displayLabel(for rawID: String, ordinal: Int) -> String {
        if Int(rawID) != nil {
            return rawID
        }
        return String(ordinal)
    }

    static func definitionPreviewText(from blocks: [MarkdownBlock]) -> String {
        blocks.map(plainText(from:)).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainText(from block: MarkdownBlock) -> String {
        switch block {
        case .heading(_, let inlines), .paragraph(let inlines):
            return MarkdownOutline.plainText(from: inlines)
        case .blockquote(let blocks), .callout(_, _, _, let blocks), .footnoteDefinition(_, let blocks):
            return blocks.map(plainText(from:)).joined(separator: " ")
        case .list(_, _, let items):
            return items.map { $0.blocks.map(plainText(from:)).joined(separator: " ") }.joined(separator: " ")
        case .codeBlock(_, let text):
            return text
        case .table(let headers, _, let rows):
            let headerText = headers.map(MarkdownOutline.plainText(from:)).joined(separator: " ")
            let rowText = rows.flatMap { $0 }.map(MarkdownOutline.plainText(from:)).joined(separator: " ")
            return [headerText, rowText].filter { !$0.isEmpty }.joined(separator: " ")
        case .horizontalRule:
            return ""
        }
    }
}
