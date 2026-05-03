// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorSession.swift - Reusable editor-domain session state.

import Foundation

struct EditorSession: EditorProviding, Equatable {
    private(set) var document: EditorDocument
    private(set) var selection: EditorSelection
    private(set) var decorations: EditorDecorationSet
    private(set) var pendingEvents: [EditorEvent]

    init(
        document: EditorDocument = EditorDocument(),
        selection: EditorSelection = .caret(at: 0),
        decorations: EditorDecorationSet = EditorDecorationSet()
    ) {
        self.document = document
        self.selection = selection.clamped(to: document.buffer.utf16Length)
        self.decorations = decorations
        self.pendingEvents = []
    }

    @discardableResult
    mutating func replaceSelection(with text: String) -> EditorChange {
        let change = document.replaceSelection(selection, with: text)
        selection = change.selectionAfter.clamped(to: document.buffer.utf16Length)
        pendingEvents.append(.documentChanged(
            documentID: document.id,
            version: document.version,
            ranges: change.changedRanges
        ))
        pendingEvents.append(.selectionChanged(documentID: document.id, selection: selection))
        return change
    }

    @discardableResult
    mutating func deleteBackward() -> EditorChange {
        let change = document.deleteBackward(selection)
        guard !change.replacements.isEmpty else { return change }
        selection = change.selectionAfter.clamped(to: document.buffer.utf16Length)
        pendingEvents.append(.documentChanged(
            documentID: document.id,
            version: document.version,
            ranges: change.changedRanges
        ))
        pendingEvents.append(.selectionChanged(documentID: document.id, selection: selection))
        return change
    }

    @discardableResult
    mutating func replaceAllText(with text: String) -> EditorChange {
        let range = EditorTextRange(location: 0, length: document.buffer.utf16Length)
        let change = document.apply(EditorReplacement(range: range, text: text))
        selection = selection.clamped(to: document.buffer.utf16Length)
        pendingEvents.append(.documentChanged(
            documentID: document.id,
            version: document.version,
            ranges: change.changedRanges
        ))
        pendingEvents.append(.selectionChanged(documentID: document.id, selection: selection))
        return change
    }

    @discardableResult
    mutating func apply(_ replacement: EditorReplacement) -> EditorChange {
        let change = document.apply(replacement)
        selection = change.selectionAfter.clamped(to: document.buffer.utf16Length)
        pendingEvents.append(.documentChanged(
            documentID: document.id,
            version: document.version,
            ranges: change.changedRanges
        ))
        pendingEvents.append(.selectionChanged(documentID: document.id, selection: selection))
        return change
    }

    mutating func setSelection(_ selection: EditorSelection) {
        self.selection = selection.clamped(to: document.buffer.utf16Length)
        pendingEvents.append(.selectionChanged(documentID: document.id, selection: self.selection))
    }

    mutating func replaceDecorations(kind: EditorDecorationKind, with decorations: [EditorDecoration]) {
        self.decorations.replace(kind: kind, with: decorations)
        pendingEvents.append(.decorationsChanged(documentID: document.id, kinds: [kind]))
    }

    mutating func markSaved() {
        document.markSaved()
        pendingEvents.append(.documentSaved(documentID: document.id, version: document.version))
    }

    mutating func drainEvents() -> [EditorEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }
}
