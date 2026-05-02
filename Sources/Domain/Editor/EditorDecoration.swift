// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorDecoration.swift - Domain model for non-mutating editor annotations.

import Foundation

enum EditorDecorationKind: String, Equatable, Hashable, CaseIterable {
    case searchResult
    case diagnostic
    case syntaxToken
    case selection
    case inlineHint
    case custom
}

enum EditorDiagnosticSeverity: String, Equatable, Hashable {
    case info
    case warning
    case error
}

struct EditorDecoration: Identifiable, Equatable, Hashable {
    var id: String
    var range: EditorTextRange
    var kind: EditorDecorationKind
    var priority: Int
    var message: String?
    var severity: EditorDiagnosticSeverity?

    init(
        id: String,
        range: EditorTextRange,
        kind: EditorDecorationKind,
        priority: Int = 0,
        message: String? = nil,
        severity: EditorDiagnosticSeverity? = nil
    ) {
        self.id = id
        self.range = range
        self.kind = kind
        self.priority = priority
        self.message = message
        self.severity = severity
    }
}

struct EditorDecorationSet: Equatable {
    private(set) var decorations: [EditorDecoration] = []

    init(_ decorations: [EditorDecoration] = []) {
        self.decorations = Self.sorted(decorations)
    }

    mutating func replace(kind: EditorDecorationKind, with newDecorations: [EditorDecoration]) {
        decorations.removeAll { $0.kind == kind }
        decorations.append(contentsOf: newDecorations.filter { $0.kind == kind })
        decorations = Self.sorted(decorations)
    }

    mutating func remove(id: String) {
        decorations.removeAll { $0.id == id }
    }

    func intersecting(_ range: EditorTextRange, kinds: Set<EditorDecorationKind>? = nil) -> [EditorDecoration] {
        decorations.filter { decoration in
            (kinds?.contains(decoration.kind) ?? true) && decoration.range.intersects(range)
        }
    }

    private static func sorted(_ decorations: [EditorDecoration]) -> [EditorDecoration] {
        decorations.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
    }
}
