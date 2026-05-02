// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorProviding.swift - Protocol boundary for reusable editor services.

import Foundation

protocol EditorProviding {
    var document: EditorDocument { get }
    var selection: EditorSelection { get }
    var decorations: EditorDecorationSet { get }

    @discardableResult
    mutating func replaceSelection(with text: String) -> EditorChange
    @discardableResult
    mutating func deleteBackward() -> EditorChange
    @discardableResult
    mutating func replaceAllText(with text: String) -> EditorChange
    mutating func setSelection(_ selection: EditorSelection)
    mutating func replaceDecorations(kind: EditorDecorationKind, with decorations: [EditorDecoration])
}
