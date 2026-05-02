// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorDomainSwiftTestingTests.swift - Reusable editor-domain behavior tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Editor text ranges")
struct EditorTextRangeSwiftTestingTests {
    @Test("range clamps negative inputs and bounds")
    func rangeClampsInputs() {
        let range = EditorTextRange(location: -5, length: -3)
        #expect(range.location == 0)
        #expect(range.length == 0)

        let clamped = EditorTextRange(location: 4, length: 20).clamped(to: 10)
        #expect(clamped.location == 4)
        #expect(clamped.length == 6)
    }

    @Test("intersections and unions are deterministic")
    func intersectionsAndUnions() {
        let lhs = EditorTextRange(location: 2, length: 5)
        let rhs = EditorTextRange(location: 5, length: 3)
        let outside = EditorTextRange(location: 9, length: 2)

        #expect(lhs.intersects(rhs))
        #expect(!lhs.intersects(outside))
        #expect(lhs.union(rhs) == EditorTextRange(location: 2, length: 6))
    }

    @Test("contains uses half-open ranges while carets match exact offsets")
    func containsUsesHalfOpenSemantics() {
        let range = EditorTextRange(location: 2, length: 3)
        let caret = EditorTextRange(location: 5, length: 0)

        #expect(range.contains(2))
        #expect(range.contains(4))
        #expect(!range.contains(5))
        #expect(caret.contains(5))
        #expect(!caret.contains(4))
    }

    @Test("carets intersect only matching carets or containing ranges")
    func caretIntersection() {
        let range = EditorTextRange(location: 2, length: 5)
        let insideCaret = EditorTextRange(location: 4, length: 0)
        let endCaret = EditorTextRange(location: 7, length: 0)
        let matchingCaret = EditorTextRange(location: 4, length: 0)

        #expect(range.intersects(insideCaret))
        #expect(insideCaret.intersects(range))
        #expect(!range.intersects(endCaret))
        #expect(insideCaret.intersects(matchingCaret))
    }

    @Test("caret union keeps the surrounding range bounds")
    func caretUnion() {
        let caret = EditorTextRange(location: 4, length: 0)
        let range = EditorTextRange(location: 2, length: 5)

        #expect(caret.union(range) == range)
    }
}

@Suite("Editor selection")
struct EditorSelectionSwiftTestingTests {
    @Test("empty selections become a zero caret")
    func emptySelectionBecomesCaret() {
        let selection = EditorSelection(ranges: [])
        #expect(selection.ranges == [EditorTextRange(location: 0, length: 0)])
        #expect(selection.primaryRange == EditorTextRange(location: 0, length: 0))
    }

    @Test("normalization sorts and removes duplicate carets")
    func normalizationSortsAndDeduplicatesCarets() {
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 8, length: 0),
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 8, length: 0),
        ])

        #expect(selection.normalizedRanges() == [
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 8, length: 0),
        ])
    }

    @Test("normalization merges overlapping selections")
    func normalizationMergesOverlaps() {
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 5, length: 5),
            EditorTextRange(location: 2, length: 5),
            EditorTextRange(location: 20, length: 2),
        ])

        #expect(selection.normalizedRanges() == [
            EditorTextRange(location: 2, length: 8),
            EditorTextRange(location: 20, length: 2),
        ])
    }

    @Test("normalization removes carets contained by selected ranges")
    func normalizationRemovesCaretsInsideSelections() {
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 5, length: 0),
            EditorTextRange(location: 2, length: 6),
            EditorTextRange(location: 12, length: 0),
        ])

        #expect(selection.normalizedRanges() == [
            EditorTextRange(location: 2, length: 6),
            EditorTextRange(location: 12, length: 0),
        ])
    }

    @Test("primary index is clamped to available ranges")
    func primaryIndexIsClamped() {
        let selection = EditorSelection(
            ranges: [
                EditorTextRange(location: 1, length: 0),
                EditorTextRange(location: 5, length: 0),
            ],
            primaryIndex: 20
        )

        #expect(selection.primaryIndex == 1)
        #expect(selection.primaryRange == EditorTextRange(location: 5, length: 0))
    }

    @Test("clamping preserves the primary range")
    func clampingPreservesPrimaryRange() {
        let selection = EditorSelection(
            ranges: [
                EditorTextRange(location: 1, length: 0),
                EditorTextRange(location: 50, length: 10),
            ],
            primaryIndex: 1
        )

        let clamped = selection.clamped(to: 5)

        #expect(clamped.primaryIndex == 1)
        #expect(clamped.primaryRange == EditorTextRange(location: 5, length: 0))
    }
}

@Suite("Editor buffer")
struct EditorBufferSwiftTestingTests {
    @Test("line count and starts handle empty and trailing newline")
    func lineCountAndStarts() {
        #expect(EditorBuffer().lineCount == 1)

        let buffer = EditorBuffer(text: "one\ntwo\n")
        #expect(buffer.lineCount == 3)
        #expect(buffer.lineStartOffsets == [0, 4, 8])
    }

    @Test("line and column mapping clamps to content")
    func lineAndColumnMapping() {
        let buffer = EditorBuffer(text: "alpha\nbeta\n")

        #expect(buffer.offset(line: 0, column: 2) == 2)
        #expect(buffer.offset(line: 1, column: 99) == 10)
        #expect(buffer.lineAndColumn(for: 8).line == 1)
        #expect(buffer.lineAndColumn(for: 8).column == 2)
    }

    @Test("offset trims CRLF line endings")
    func offsetTrimsCRLFLineEndings() {
        let buffer = EditorBuffer(text: "alpha\r\nbeta")

        #expect(buffer.offset(line: 0, column: 99) == 5)
    }

    @Test("line range containing offset clamps to content")
    func lineRangeContainingOffsetClamps() {
        let buffer = EditorBuffer(text: "alpha\nbeta")

        #expect(buffer.lineRange(containing: 200) == EditorTextRange(location: 6, length: 4))
    }

    @Test("string extraction uses UTF-16 offsets")
    func extractionUsesUTF16() {
        let buffer = EditorBuffer(text: "a😀b")
        #expect(buffer.utf16Length == 4)
        #expect(buffer.string(in: EditorTextRange(location: 1, length: 2)) == "😀")
    }

    @Test("single replacement updates text and change metadata")
    func singleReplacement() {
        var buffer = EditorBuffer(text: "hello world")
        let change = buffer.replace(EditorReplacement(range: EditorTextRange(location: 6, length: 5), text: "Cocxy"))

        #expect(buffer.text == "hello Cocxy")
        #expect(change.beforeText == "hello world")
        #expect(change.afterText == "hello Cocxy")
        #expect(change.selectionAfter.primaryRange.location == 11)
    }

    @Test("multi-cursor insertion applies in source order and returns new carets")
    func multiCursorInsertion() {
        var buffer = EditorBuffer(text: "a\nb\nc")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 0, length: 0),
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 4, length: 0),
        ])

        let change = buffer.replaceSelection(selection, with: ">")

        #expect(buffer.text == ">a\n>b\n>c")
        #expect(change.selectionAfter.ranges == [
            EditorTextRange(location: 1, length: 0),
            EditorTextRange(location: 4, length: 0),
            EditorTextRange(location: 7, length: 0),
        ])
    }

    @Test("multi-cursor delete backward removes the character before each caret")
    func multiCursorDeleteBackward() {
        var buffer = EditorBuffer(text: "> line-0\n> line-1\n> line-2")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 11, length: 0),
            EditorTextRange(location: 20, length: 0),
        ])

        let change = buffer.deleteBackward(selection)

        #expect(buffer.text == ">line-0\n>line-1\n>line-2")
        #expect(change.selectionAfter.ranges == [
            EditorTextRange(location: 1, length: 0),
            EditorTextRange(location: 9, length: 0),
            EditorTextRange(location: 17, length: 0),
        ])
    }

    @Test("delete backward removes selected ranges before caret deletions")
    func deleteBackwardDeletesSelectionsAndCarets() {
        var buffer = EditorBuffer(text: "abcdef")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 1, length: 3),
            EditorTextRange(location: 5, length: 0),
        ])

        let change = buffer.deleteBackward(selection)

        #expect(buffer.text == "af")
        #expect(change.replacements == [
            EditorReplacement(range: EditorTextRange(location: 1, length: 3), text: ""),
            EditorReplacement(range: EditorTextRange(location: 4, length: 1), text: ""),
        ])
    }

    @Test("delete backward at document start is a no-op")
    func deleteBackwardAtDocumentStartIsNoop() {
        var buffer = EditorBuffer(text: "abc")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 0, length: 0),
        ])

        let change = buffer.deleteBackward(selection)

        #expect(buffer.text == "abc")
        #expect(change.replacements.isEmpty)
        #expect(change.selectionAfter == selection)
    }

    @Test("delete backward removes a full composed character")
    func deleteBackwardRemovesComposedCharacter() {
        var buffer = EditorBuffer(text: "a😀b")
        let change = buffer.deleteBackward(.caret(at: 3))

        #expect(buffer.text == "ab")
        #expect(change.replacements == [
            EditorReplacement(range: EditorTextRange(location: 1, length: 2), text: ""),
        ])
    }

    @Test("delete backward deduplicates matching carets")
    func deleteBackwardDeduplicatesMatchingCarets() {
        var buffer = EditorBuffer(text: "abc")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 2, length: 0),
        ])

        buffer.deleteBackward(selection)

        #expect(buffer.text == "ac")
    }

    @Test("empty replacement transaction preserves multi-cursor selection")
    func emptyReplacementTransactionPreservesSelection() {
        var buffer = EditorBuffer(text: "abc")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 1, length: 0),
            EditorTextRange(location: 2, length: 0),
        ])

        let change = buffer.replace([], selectionBefore: selection)

        #expect(change.selectionAfter == selection)
    }

    @Test("multi-selection replacement clamps out of range input")
    func multiSelectionReplacementClamps() {
        var buffer = EditorBuffer(text: "abcdef")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 1, length: 2),
            EditorTextRange(location: 20, length: 4),
        ])

        buffer.replaceSelection(selection, with: "X")

        #expect(buffer.text == "aXdefX")
    }

    @Test("multi-selection replacement ignores carets inside selected ranges")
    func multiSelectionReplacementIgnoresCaretsInsideSelections() {
        var buffer = EditorBuffer(text: "abcdef")
        let selection = EditorSelection(ranges: [
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 1, length: 3),
        ])

        let change = buffer.replaceSelection(selection, with: "X")

        #expect(buffer.text == "aXef")
        #expect(change.selectionAfter.ranges == [
            EditorTextRange(location: 2, length: 0),
        ])
    }

    @Test("replacement transactions ignore carets inside replacement ranges")
    func replacementTransactionsIgnoreCaretsInsideRanges() {
        var buffer = EditorBuffer(text: "abcdef")

        let change = buffer.replace(
            [
                EditorReplacement(range: EditorTextRange(location: 2, length: 0), text: "Y"),
                EditorReplacement(range: EditorTextRange(location: 1, length: 3), text: "X"),
            ],
            selectionBefore: EditorSelection(ranges: [
                EditorTextRange(location: 2, length: 0),
                EditorTextRange(location: 1, length: 3),
            ])
        )

        #expect(buffer.text == "aXef")
        #expect(change.replacements == [
            EditorReplacement(range: EditorTextRange(location: 1, length: 3), text: "X"),
        ])
    }
}

@Suite("Editor decorations")
struct EditorDecorationSwiftTestingTests {
    @Test("decorations sort by range then priority")
    func decorationsSort() {
        let set = EditorDecorationSet([
            EditorDecoration(id: "low", range: EditorTextRange(location: 2, length: 2), kind: .searchResult, priority: 0),
            EditorDecoration(id: "high", range: EditorTextRange(location: 2, length: 2), kind: .diagnostic, priority: 10),
            EditorDecoration(id: "first", range: EditorTextRange(location: 0, length: 1), kind: .syntaxToken),
        ])

        #expect(set.decorations.map(\.id) == ["first", "high", "low"])
    }

    @Test("intersection filters by range and kind")
    func intersectionFilters() {
        let set = EditorDecorationSet([
            EditorDecoration(id: "a", range: EditorTextRange(location: 0, length: 5), kind: .searchResult),
            EditorDecoration(id: "b", range: EditorTextRange(location: 10, length: 2), kind: .diagnostic),
            EditorDecoration(id: "hint", range: EditorTextRange(location: 6, length: 0), kind: .inlineHint),
        ])

        let all = set.intersecting(EditorTextRange(location: 3, length: 8))
        let diagnostics = set.intersecting(EditorTextRange(location: 3, length: 8), kinds: [.diagnostic])

        #expect(all.map(\.id) == ["a", "hint", "b"])
        #expect(diagnostics.map(\.id) == ["b"])
    }

    @Test("replace by kind preserves unrelated decorations")
    func replaceByKind() {
        var set = EditorDecorationSet([
            EditorDecoration(id: "search", range: EditorTextRange(location: 0, length: 1), kind: .searchResult),
            EditorDecoration(id: "diag-old", range: EditorTextRange(location: 2, length: 1), kind: .diagnostic),
        ])

        set.replace(kind: .diagnostic, with: [
            EditorDecoration(id: "diag-new", range: EditorTextRange(location: 4, length: 1), kind: .diagnostic),
            EditorDecoration(id: "ignored", range: EditorTextRange(location: 9, length: 1), kind: .searchResult),
        ])

        #expect(set.decorations.map(\.id) == ["search", "diag-new"])
    }
}

@Suite("Editor document")
struct EditorDocumentSwiftTestingTests {
    @Test("document tracks version and dirty state")
    func documentTracksDirtyState() {
        var document = EditorDocument(text: "let a = 1")
        #expect(document.version == 0)
        #expect(!document.isDirty)

        document.replaceSelection(.caret(at: 9), with: "\n")

        #expect(document.version == 1)
        #expect(document.isDirty)

        document.markSaved()
        #expect(!document.isDirty)
    }
}

@Suite("Editor session")
struct EditorSessionSwiftTestingTests {
    @Test("session replaces selection, updates caret and emits events")
    func sessionReplaceSelection() {
        let document = EditorDocument(text: "alpha beta")
        var session = EditorSession(
            document: document,
            selection: EditorSelection(ranges: [EditorTextRange(location: 6, length: 4)])
        )

        let change = session.replaceSelection(with: "Cocxy")
        let events = session.drainEvents()

        #expect(change.afterText == "alpha Cocxy")
        #expect(session.document.text == "alpha Cocxy")
        #expect(session.selection.primaryRange == EditorTextRange(location: 11, length: 0))
        #expect(events == [
            .documentChanged(documentID: document.id, version: 1, ranges: [EditorTextRange(location: 6, length: 5)]),
            .selectionChanged(documentID: document.id, selection: EditorSelection.caret(at: 11)),
        ])
        #expect(session.pendingEvents.isEmpty)
    }

    @Test("session delete backward updates carets and emits document events")
    func sessionDeleteBackward() {
        let document = EditorDocument(text: "ab\ncd")
        var session = EditorSession(
            document: document,
            selection: EditorSelection(ranges: [
                EditorTextRange(location: 1, length: 0),
                EditorTextRange(location: 4, length: 0),
            ])
        )

        let change = session.deleteBackward()

        #expect(session.document.buffer.text == "b\nd")
        #expect(change.selectionAfter.ranges == [
            EditorTextRange(location: 0, length: 0),
            EditorTextRange(location: 2, length: 0),
        ])
        #expect(session.drainEvents() == [
            .documentChanged(documentID: document.id, version: 1, ranges: [
                EditorTextRange(location: 0, length: 0),
                EditorTextRange(location: 3, length: 0),
            ]),
            .selectionChanged(documentID: document.id, selection: EditorSelection(ranges: [
                EditorTextRange(location: 0, length: 0),
                EditorTextRange(location: 2, length: 0),
            ])),
        ])
    }

    @Test("session delete backward no-op preserves version and selection")
    func sessionDeleteBackwardNoop() {
        let document = EditorDocument(text: "abc")
        var session = EditorSession(document: document, selection: .caret(at: 0))

        let change = session.deleteBackward()

        #expect(change.replacements.isEmpty)
        #expect(session.document.version == 0)
        #expect(session.selection == .caret(at: 0))
        #expect(session.drainEvents().isEmpty)
    }

    @Test("session clamps selections to document bounds")
    func sessionClampsSelection() {
        var session = EditorSession(document: EditorDocument(text: "short"))

        session.setSelection(EditorSelection(ranges: [EditorTextRange(location: 50, length: 10)]))

        #expect(session.selection.primaryRange == EditorTextRange(location: 5, length: 0))
    }

    @Test("session replaces decoration kinds and emits event")
    func sessionReplacesDecorations() {
        let document = EditorDocument(text: "let value = 1")
        var session = EditorSession(document: document)

        session.replaceDecorations(kind: .diagnostic, with: [
            EditorDecoration(
                id: "error",
                range: EditorTextRange(location: 4, length: 5),
                kind: .diagnostic,
                priority: 10,
                message: "Example diagnostic",
                severity: .error
            ),
        ])

        #expect(session.decorations.decorations.map(\.id) == ["error"])
        #expect(session.drainEvents() == [
            .decorationsChanged(documentID: document.id, kinds: [.diagnostic]),
        ])
    }

    @Test("session markSaved clears dirty state and emits save event")
    func sessionMarkSaved() {
        let document = EditorDocument(text: "initial")
        var session = EditorSession(document: document, selection: .caret(at: 7))

        session.replaceSelection(with: " text")
        _ = session.drainEvents()
        #expect(session.document.isDirty)

        session.markSaved()

        #expect(!session.document.isDirty)
        #expect(session.drainEvents() == [
            .documentSaved(documentID: document.id, version: 1),
        ])
    }

    @Test("session replace all text keeps selection inside new bounds")
    func sessionReplaceAllTextClampsSelection() {
        var session = EditorSession(document: EditorDocument(text: "abcdef"), selection: .caret(at: 6))

        session.replaceAllText(with: "xy")

        #expect(session.selection == .caret(at: 2))
    }
}
