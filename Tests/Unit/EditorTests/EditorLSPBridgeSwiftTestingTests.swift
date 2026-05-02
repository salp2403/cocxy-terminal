// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorLSPBridgeSwiftTestingTests.swift - LSP diagnostics wiring into editor decorations.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Editor LSP bridge")
struct EditorLSPBridgeSwiftTestingTests {
    @Test("LSP diagnostics map to editor diagnostic decorations")
    func diagnosticsMapToDecorations() {
        let buffer = EditorBuffer(text: "let value = 1\nprint(value)\n")
        let diagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 1, character: 0),
                end: LSPPosition(line: 1, character: 5)
            ),
            severity: .warning,
            message: "Prefer logger",
            source: "sourcekit"
        )

        let decorations = LSPEditorBridge.decorations(
            from: [diagnostic],
            in: buffer,
            uri: "file:///tmp/Sample.swift"
        )

        #expect(decorations == [
            EditorDecoration(
                id: "lsp:file:///tmp/Sample.swift:0:14:5",
                range: EditorTextRange(location: 14, length: 5),
                kind: .diagnostic,
                priority: 20,
                message: "sourcekit: Prefer logger",
                severity: .warning
            ),
        ])
    }

    @Test("zero length LSP diagnostics stay visible when the buffer has text")
    func zeroLengthDiagnosticsStayVisible() {
        let buffer = EditorBuffer(text: "abc")
        let diagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 0, character: 1),
                end: LSPPosition(line: 0, character: 1)
            ),
            severity: .error,
            message: "Missing token"
        )

        let decorations = LSPEditorBridge.decorations(
            from: [diagnostic],
            in: buffer,
            uri: "file:///tmp/Sample.swift"
        )

        #expect(decorations.first?.range == EditorTextRange(location: 1, length: 1))
        #expect(decorations.first?.severity == .error)
        #expect(decorations.first?.priority == 30)
    }

    @Test("EditorView applies and clears matching diagnostic events")
    func editorViewAppliesAndClearsDiagnostics() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\n")
        let view = EditorView(fileURL: fileURL)
        let uri = fileURL.absoluteString

        view.applyLSPClientEvent(.diagnostics(uri: uri, diagnostics: [
            LSPDiagnostic(
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 4),
                    end: LSPPosition(line: 0, character: 9)
                ),
                severity: .information,
                message: "Unused value"
            ),
        ]))

        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 20),
            kinds: [.diagnostic]
        ).count == 1)

        view.applyLSPClientEvent(.diagnostics(uri: uri, diagnostics: []))

        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 20),
            kinds: [.diagnostic]
        ).isEmpty)
    }

    @Test("EditorView ignores diagnostic events for other documents")
    func editorViewIgnoresOtherDocuments() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\n")
        let view = EditorView(fileURL: fileURL)

        view.applyLSPClientEvent(.diagnostics(uri: "file:///tmp/Other.swift", diagnostics: [
            LSPDiagnostic(
                range: LSPRange(
                    start: LSPPosition(line: 0, character: 0),
                    end: LSPPosition(line: 0, character: 3)
                ),
                severity: .error,
                message: "Wrong file"
            ),
        ]))

        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 20),
            kinds: [.diagnostic]
        ).isEmpty)
    }

    @Test("EditorView creates an LSP document snapshot from current text")
    func editorViewCreatesDocumentSnapshot() throws {
        let fileURL = try makeTemporaryFile(contents: "old\n")
        let view = EditorView(fileURL: fileURL)
        view.replaceText("new\n")

        let snapshot = try #require(view.lspDocumentSnapshot(languageID: "swift"))

        #expect(snapshot.uri == fileURL.absoluteString)
        #expect(snapshot.languageID == "swift")
        #expect(snapshot.version == view.session.document.version)
        #expect(snapshot.text == "new\n")
    }

    @Test("EditorView surfaces hover and completion response events")
    func editorViewSurfacesHoverAndCompletionEvents() {
        let view = EditorView(text: "pri")

        view.applyLSPClientEvent(.hover(
            id: .int(1),
            hover: LSPHover(contents: "`String`")
        ))
        view.applyLSPClientEvent(.completion(
            id: .int(2),
            items: [
                LSPCompletionItem(label: "print", detail: "Swift.print", insertText: "print($0)"),
            ]
        ))

        #expect(view.lspHoverText == "`String`")
        #expect(view.lspCompletionItems.map(\.label) == ["print"])
        #expect(view.lspAccessoryText == "print - Swift.print")
    }

    @Test("EditorView exposes multiple LSP results as selectable list titles")
    func editorViewExposesMultipleLSPResults() {
        let view = EditorView(text: "pri")

        view.applyLSPClientEvent(.completion(
            id: .int(1),
            items: [
                LSPCompletionItem(label: "print", detail: "Swift.print", insertText: "print($0)"),
                LSPCompletionItem(label: "private", detail: nil, insertText: nil),
            ]
        ))

        #expect(view.lspResultItemTitles == ["print - Swift.print", "private"])
        #expect(view.acceptLSPCompletion(at: 1) == true)
        #expect(view.currentText == "privatepri")
    }

    @Test("EditorView request buttons emit LSP positions from the primary selection")
    func editorViewRequestButtonsEmitSelectionPosition() {
        let view = EditorView(text: "let value = 1\nprint(value)\n")
        var requestedPositions: [LSPPosition] = []
        view.onLSPHoverRequested = { requestedPositions.append($0) }
        view.onLSPCompletionRequested = { requestedPositions.append($0) }
        view.onLSPDefinitionRequested = { requestedPositions.append($0) }
        view.onLSPReferencesRequested = { requestedPositions.append($0) }
        view.setLSPControlsEnabled(true)
        view.setSelection(.caret(at: 20))

        #expect(view.requestLSPHoverAtSelection() == true)
        #expect(view.requestLSPCompletionAtSelection() == true)
        #expect(view.requestLSPDefinitionAtSelection() == true)
        #expect(view.requestLSPReferencesAtSelection() == true)

        #expect(requestedPositions == Array(repeating: LSPPosition(line: 1, character: 6), count: 4))
    }

    @Test("EditorView LSP request buttons stay inert until enabled")
    func editorViewLSPRequestsStayInertUntilEnabled() {
        let view = EditorView(text: "let value = 1\n")
        var requestCount = 0
        view.onLSPCompletionRequested = { _ in requestCount += 1 }

        #expect(view.isLSPControlsEnabled == false)
        #expect(view.requestLSPCompletionAtSelection() == false)
        #expect(requestCount == 0)
    }

    @Test("EditorView accepts a surfaced completion at the current selection")
    func editorViewAcceptsCompletion() {
        let view = EditorView(text: "pri")
        view.setSelection(EditorSelection(ranges: [
            EditorTextRange(location: 0, length: 3),
        ]))
        view.applyLSPClientEvent(.completion(
            id: .int(1),
            items: [
                LSPCompletionItem(label: "print", detail: nil, insertText: "print($0)"),
            ]
        ))

        #expect(view.acceptLSPCompletion(at: 0) == true)
        #expect(view.currentText == "print($0)")
    }

    @Test("EditorView navigates to definition and reference locations")
    func editorViewNavigatesToLSPLocations() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\nprint(value)\n")
        let view = EditorView(fileURL: fileURL)
        let location = LSPLocation(
            uri: fileURL.absoluteString,
            range: LSPRange(
                start: LSPPosition(line: 1, character: 6),
                end: LSPPosition(line: 1, character: 11)
            )
        )

        view.applyLSPClientEvent(.definition(id: .int(1), locations: [location]))
        #expect(view.goToLSPDefinition(at: 0) == true)

        let definitionRange = try #require(view.session.selection.normalizedRanges(
            maximumLength: view.session.document.buffer.utf16Length
        ).first)
        #expect(definitionRange == EditorTextRange(location: 20, length: 5))

        view.setSelection(.caret(at: 0))
        view.applyLSPClientEvent(.references(id: .int(2), locations: [location]))
        #expect(view.goToLSPReference(at: 0) == true)

        let referenceRange = try #require(view.session.selection.normalizedRanges(
            maximumLength: view.session.document.buffer.utf16Length
        ).first)
        #expect(referenceRange == EditorTextRange(location: 20, length: 5))
    }

    private func makeTemporaryFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-editor-lsp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Sample.swift")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
