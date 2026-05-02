// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxHighlightBridge.swift - Converts syntax tokens into editor decorations.

import Foundation

enum SyntaxTokenRole: String, Equatable, Hashable, Codable, CaseIterable {
    case keyword
    case string
    case comment
    case function
    case type
    case variable
    case number
    case operatorToken
    case punctuation
}

enum SyntaxCaptureMapper {
    static func role(for captureName: String) -> SyntaxTokenRole? {
        let baseName = captureName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: ".")
            .first
            .map(String.init)

        switch baseName {
        case "keyword":
            return .keyword
        case "string":
            return .string
        case "comment":
            return .comment
        case "function", "method":
            return .function
        case "type", "constructor", "constant":
            return .type
        case "variable", "property", "field", "parameter":
            return .variable
        case "number", "float":
            return .number
        case "operator":
            return .operatorToken
        case "punctuation":
            return .punctuation
        default:
            return nil
        }
    }
}

struct SyntaxToken: Equatable, Hashable {
    var role: SyntaxTokenRole
    var range: EditorTextRange

    init(role: SyntaxTokenRole, range: EditorTextRange) {
        self.role = role
        self.range = range
    }
}

struct SyntaxPoint: Equatable, Hashable {
    var line: Int
    var column: Int

    init(line: Int, column: Int) {
        self.line = max(0, line)
        self.column = max(0, column)
    }
}

struct SyntaxPointRange: Equatable, Hashable {
    var start: SyntaxPoint
    var end: SyntaxPoint

    func editorRange(in buffer: EditorBuffer) -> EditorTextRange {
        let startOffset = buffer.offset(line: start.line, column: start.column)
        let endOffset = buffer.offset(line: end.line, column: end.column)
        return EditorTextRange(
            location: min(startOffset, endOffset),
            length: abs(endOffset - startOffset)
        )
    }
}

enum SyntaxHighlightBridge {
    static func decorations(from tokens: [SyntaxToken], in buffer: EditorBuffer) -> [EditorDecoration] {
        tokens.enumerated().compactMap { index, token in
            let range = token.range.clamped(to: buffer.utf16Length)
            guard range.length > 0 else { return nil }
            return EditorDecoration(
                id: "syntax.\(token.role.rawValue).\(range.location).\(range.length).\(index)",
                range: range,
                kind: .syntaxToken,
                priority: -10,
                message: "syntax.\(token.role.rawValue)"
            )
        }
    }
}
