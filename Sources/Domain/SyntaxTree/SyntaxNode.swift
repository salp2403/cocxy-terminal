// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxNode.swift - Stable syntax node model exposed to the editor domain.

import Foundation

struct SyntaxNode: Equatable, Hashable {
    var kind: String
    var range: SyntaxPointRange
    var isNamed: Bool
    var childCount: Int

    init(
        kind: String,
        range: SyntaxPointRange,
        isNamed: Bool = true,
        childCount: Int = 0
    ) {
        let cleanKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = cleanKind.isEmpty ? "unknown" : cleanKind
        self.range = range
        self.isNamed = isNamed
        self.childCount = max(0, childCount)
    }

    func editorRange(in buffer: EditorBuffer) -> EditorTextRange {
        range.editorRange(in: buffer)
    }
}
