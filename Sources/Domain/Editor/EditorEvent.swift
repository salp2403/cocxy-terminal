// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorEvent.swift - Typed editor-domain events emitted by reusable editor services.

import Foundation

enum EditorEvent: Equatable {
    case documentChanged(documentID: UUID, version: Int, ranges: [EditorTextRange])
    case documentSaved(documentID: UUID, version: Int)
    case selectionChanged(documentID: UUID, selection: EditorSelection)
    case decorationsChanged(documentID: UUID, kinds: Set<EditorDecorationKind>)
}
