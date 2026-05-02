// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorDocument.swift - File-backed document state for the reusable editor domain.

import Foundation

struct EditorDocument: Equatable, Identifiable {
    let id: UUID
    var fileURL: URL?
    private(set) var buffer: EditorBuffer
    private(set) var version: Int
    private var savedText: String

    init(id: UUID = UUID(), fileURL: URL? = nil, text: String = "") {
        self.id = id
        self.fileURL = fileURL
        self.buffer = EditorBuffer(text: text)
        self.version = 0
        self.savedText = text
    }

    var text: String { buffer.text }
    var isDirty: Bool { buffer.text != savedText }

    @discardableResult
    mutating func replaceSelection(_ selection: EditorSelection, with replacementText: String) -> EditorChange {
        let change = buffer.replaceSelection(selection, with: replacementText)
        version += 1
        return change
    }

    @discardableResult
    mutating func deleteBackward(_ selection: EditorSelection) -> EditorChange {
        let change = buffer.deleteBackward(selection)
        if !change.replacements.isEmpty {
            version += 1
        }
        return change
    }

    @discardableResult
    mutating func apply(_ replacement: EditorReplacement) -> EditorChange {
        let change = buffer.replace(replacement)
        version += 1
        return change
    }

    mutating func markSaved() {
        savedText = buffer.text
    }
}
