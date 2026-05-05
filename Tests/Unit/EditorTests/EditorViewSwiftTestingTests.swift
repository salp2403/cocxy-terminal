// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorViewSwiftTestingTests.swift - AppKit surface coverage for the reusable text editor.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Editor view")
struct EditorViewSwiftTestingTests {
    @Test("loads a UTF-8 text file into the editor session")
    func loadsTextFile() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\n")

        let view = EditorView(fileURL: fileURL)

        #expect(view.fileURL == fileURL)
        #expect(view.currentText == "let value = 1\n")
        #expect(!view.isDirty)
    }

    @Test("missing files keep load failure status visible")
    func missingFileShowsLoadFailureStatus() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")

        let view = EditorView(fileURL: fileURL)

        #expect(view.fileURL == fileURL)
        #expect(view.currentText == "")
        #expect(view.statusText == "Load failed")
    }

    @Test("editor chrome strings localize to Spanish")
    func editorChromeStringsLocalize() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let view = EditorView(text: "alpha", localizer: localizer)

        #expect(view.statusText == "Guardado")
        view.replaceText("beta")
        #expect(view.statusText == "Editado")
        view.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))
        #expect(view.statusText == "Edited")
        #expect(EditorView.localizedUntitled(using: localizer) == "Sin título")
        #expect(EditorView.localizedOpenFile(using: localizer) == "Abrir archivo")
        #expect(EditorView.localizedFindReferences(using: localizer) == "Buscar referencias")
        #expect(EditorLSPPresentation.localizedReferences(2, using: localizer) == "2 referencias")

        let openPanel = EditorView.localizedOpenPanelCopy(using: localizer)
        #expect(openPanel.title == "Abrir archivo")
        #expect(openPanel.message == "Elige un archivo de texto local para editar.")
        #expect(openPanel.prompt == "Abrir")
    }

    @Test("programmatic text replacement marks document dirty and save writes to disk")
    func replacementAndSaveRoundTrip() throws {
        let fileURL = try makeTemporaryFile(contents: "old\n")
        let view = EditorView(fileURL: fileURL)

        view.replaceText("new\n")

        #expect(view.currentText == "new\n")
        #expect(view.isDirty)

        try view.saveNow()

        #expect(!view.isDirty)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "new\n")
    }

    @Test("decorations are stored in the domain session")
    func decorationsRoundTripIntoSession() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\n")
        let view = EditorView(fileURL: fileURL)

        view.replaceDecorations(kind: .searchResult, with: [
            EditorDecoration(
                id: "match",
                range: EditorTextRange(location: 4, length: 5),
                kind: .searchResult
            ),
        ])

        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 20),
            kinds: [.searchResult]
        ).map(\.id) == ["match"])
    }

    @Test("syntax decoration provider refreshes on load and text changes")
    func syntaxDecorationProviderRefreshes() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\n")
        let view = EditorView(fileURL: fileURL)
        var requestedTexts: [String] = []

        view.syntaxDecorationProvider = { document in
            requestedTexts.append(document.buffer.text)
            return [
                EditorDecoration(
                    id: "syntax.keyword",
                    range: EditorTextRange(location: 0, length: 3),
                    kind: .syntaxToken,
                    message: "syntax.keyword"
                ),
            ]
        }

        #expect(requestedTexts == ["let value = 1\n"])
        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 3),
            kinds: [.syntaxToken]
        ).map(\.id) == ["syntax.keyword"])

        view.replaceText("func greet() {}\n")

        #expect(requestedTexts.last == "func greet() {}\n")
    }

    @Test("editor syntax LSP and Vim wiring coexist on one surface")
    func editorSyntaxLSPAndVimWiringCoexist() throws {
        let fileURL = try makeTemporaryFile(contents: "let value = 1\nprint(value)\n")
        let view = EditorView(fileURL: fileURL)
        let textView: EditorTextView = try #require(findSubview(in: view))
        var requestedPositions: [LSPPosition] = []

        view.syntaxDecorationProvider = { document in
            [
                EditorDecoration(
                    id: "syntax.keyword",
                    range: EditorTextRange(location: 0, length: 3),
                    kind: .syntaxToken,
                    message: "syntax:\(document.buffer.lineCount)"
                ),
            ]
        }
        view.applyLSPClientEvent(.diagnostics(uri: fileURL.absoluteString, diagnostics: [
            LSPDiagnostic(
                range: LSPRange(
                    start: LSPPosition(line: 1, character: 6),
                    end: LSPPosition(line: 1, character: 11)
                ),
                severity: .warning,
                message: "unused value",
                source: "local-lsp"
            ),
        ]))
        view.onLSPHoverRequested = { requestedPositions.append($0) }
        view.setLSPControlsEnabled(true)

        view.setSelection(.caret(at: 0))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("l"))

        #expect(view.requestLSPHoverAtSelection())
        #expect(requestedPositions == [LSPPosition(line: 0, character: 4)])
        #expect(view.session.selection == .caret(at: 4))

        let syntaxDecorations = view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: view.session.document.buffer.utf16Length),
            kinds: [.syntaxToken]
        )
        let diagnosticDecorations = view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: view.session.document.buffer.utf16Length),
            kinds: [.diagnostic]
        )

        #expect(syntaxDecorations.map(\.id) == ["syntax.keyword"])
        #expect(diagnosticDecorations.count == 1)
        #expect(diagnosticDecorations.first?.message == "local-lsp: unused value")
        #expect(diagnosticDecorations.first?.severity == .warning)
        #expect(view.currentText == "let value = 1\nprint(value)\n")
    }

    @Test("plain text keeps readable editor foreground when syntax has no tokens")
    func plainTextKeepsReadableForegroundWithoutSyntaxTokens() throws {
        let view = EditorView(text: "alpha beta\n")
        let textView: EditorTextView = try #require(findSubview(in: view))
        let scrollView: EditorScrollView = try #require(findSubview(in: view))

        let color = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        #expect(color?.isEqual(CocxyColors.text) == true)
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == CocxyColors.text)
        #expect(textView.drawsBackground)
        #expect(textView.backgroundColor == CocxyColors.base)
        #expect(scrollView.drawsBackground)
        #expect(scrollView.backgroundColor == CocxyColors.base)
    }

    @Test("editor theme repair restores readable text after AppKit color reset")
    func editorThemeRepairRestoresReadableTextAfterAppKitColorReset() throws {
        let view = EditorView(text: "alpha beta\n")
        let textView: EditorTextView = try #require(findSubview(in: view))
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.typingAttributes[.foregroundColor] = NSColor.black
        textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)

        textView.applyReadableTextTheme()

        let repairedColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        let repairedFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        #expect(repairedColor?.isEqual(CocxyColors.text) == true)
        #expect(textView.textColor == CocxyColors.text)
        #expect(textView.insertionPointColor == CocxyColors.text)
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == CocxyColors.text)
        #expect(repairedFont == EditorTextView.defaultEditorFont)
    }

    @Test("text view repairs readable foreground when AppKit changes appearance directly")
    func textViewAppearanceChangeRepairsReadableForeground() throws {
        let textView = EditorTextView()
        textView.applyDefaultConfiguration()
        textView.string = "alpha beta\n"
        textView.applyReadableTextTheme()
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.typingAttributes[.foregroundColor] = NSColor.black
        textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)

        textView.viewDidChangeEffectiveAppearance()

        let repairedColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        #expect(repairedColor?.isEqual(CocxyColors.text) == true)
        #expect(textView.textColor == CocxyColors.text)
        #expect(textView.insertionPointColor == CocxyColors.text)
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == CocxyColors.text)
    }

    @Test("text view repairs dark foreground before AppKit draws")
    func textViewPreDrawRepairsDarkForeground() throws {
        let textView = EditorTextView()
        textView.applyDefaultConfiguration()
        textView.string = "alpha beta\n"
        textView.applyReadableTextTheme()
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.typingAttributes[.foregroundColor] = NSColor.black
        textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)

        textView.viewWillDraw()

        let repairedColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        #expect(repairedColor?.isEqual(CocxyColors.text) == true)
        #expect(textView.textColor == CocxyColors.text)
        #expect(textView.insertionPointColor == CocxyColors.text)
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == CocxyColors.text)
    }

    @Test("editor appearance repair preserves syntax colors while restoring base text")
    func editorAppearanceRepairPreservesSyntaxDecorations() throws {
        let view = EditorView(text: "let value = 1\n")
        let textView: EditorTextView = try #require(findSubview(in: view))
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        view.syntaxDecorationProvider = { _ in
            [
                EditorDecoration(
                    id: "syntax.keyword",
                    range: EditorTextRange(location: 0, length: 3),
                    kind: .syntaxToken,
                    message: "syntax.keyword"
                ),
            ]
        }
        textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)

        textView.viewDidChangeEffectiveAppearance()

        let keywordColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        let baseColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 4,
            effectiveRange: nil
        ) as? NSColor

        #expect(keywordColor?.isEqual(CocxyColors.mauve) == true)
        #expect(baseColor?.isEqual(CocxyColors.text) == true)
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == CocxyColors.text)
    }

    @Test("editor view applies real bundled syntax decorations for first smoke languages")
    func editorViewAppliesRealBundledSyntaxDecorationsForSmokeLanguages() throws {
        let resourcesURL = repositoryRoot().appendingPathComponent("Resources", isDirectory: true)
        let service = try makeRepositorySyntaxService(resourcesURL: resourcesURL)
        let samples: [(fileName: String, text: String)] = [
            ("App.swift", "func greet() {\n  return 1\n}\n"),
            ("main.rs", "fn main() {\n  println!(\"hi\");\n}\n"),
            ("app.py", "def greet():\n    return 1\n"),
            ("app.ts", "export function greet(): number {\n  return 1\n}\n"),
            ("main.go", "package main\nfunc main() {\n  println(\"hi\")\n}\n"),
        ]

        for sample in samples {
            let fileURL = try makeTemporaryFile(named: sample.fileName, contents: sample.text)
            let view = EditorView(fileURL: fileURL)
            view.syntaxDecorationProvider = { document in
                guard let fileURL = document.fileURL else { return [] }
                return service.decorations(forFileURL: fileURL, buffer: document.buffer)
            }

            let decorations = view.session.decorations.intersecting(
                EditorTextRange(location: 0, length: view.session.document.buffer.utf16Length),
                kinds: [.syntaxToken]
            )
            #expect(!decorations.isEmpty, "expected syntax decorations for \(sample.fileName)")

            let textView: EditorTextView = try #require(findSubview(in: view))
            let firstDecoration = try #require(decorations.first)
            let color = textView.textStorage?.attribute(
                .foregroundColor,
                at: firstDecoration.range.location,
                effectiveRange: nil
            ) as? NSColor
            #expect(color != nil, "expected painted syntax color for \(sample.fileName)")
        }
    }

    @Test("multi-cursor insertion updates text through the editor surface")
    func multiCursorInsertion() {
        let view = EditorView(text: "a\nb\nc")
        view.setSelection(EditorSelection(ranges: [
            EditorTextRange(location: 0, length: 0),
            EditorTextRange(location: 2, length: 0),
            EditorTextRange(location: 4, length: 0),
        ]))

        view.insertTextAtSelections(">")

        #expect(view.currentText == ">a\n>b\n>c")
        #expect(view.session.selection.ranges == [
            EditorTextRange(location: 1, length: 0),
            EditorTextRange(location: 4, length: 0),
            EditorTextRange(location: 7, length: 0),
        ])
    }

    @Test("soft wrap can be toggled without changing document text")
    func softWrapToggle() {
        let view = EditorView(text: "let value = 1\n")

        #expect(view.isSoftWrapEnabled)

        view.setSoftWrapEnabled(false)

        #expect(!view.isSoftWrapEnabled)
        #expect(view.currentText == "let value = 1\n")
    }

    @Test("loads a 5000-line text file without changing line count")
    func loadsFiveThousandLineFile() throws {
        let text = (0..<5_000)
            .map { "let value\($0) = \($0)" }
            .joined(separator: "\n")
        let fileURL = try makeTemporaryFile(contents: text)

        let view = EditorView(fileURL: fileURL)

        #expect(view.session.document.buffer.lineCount == 5_000)
        #expect(view.currentText == text)
    }

    @Test("multi-cursor insertion supports 50 carets")
    func fiftyCursorInsertion() {
        let text = (0..<50)
            .map { "line-\($0)" }
            .joined(separator: "\n")
        let view = EditorView(text: text)
        let carets = view.session.document.buffer.lineStartOffsets.prefix(50).map {
            EditorTextRange(location: $0, length: 0)
        }

        view.setSelection(EditorSelection(ranges: Array(carets)))
        view.insertTextAtSelections("> ")

        let expected = (0..<50)
            .map { "> line-\($0)" }
            .joined(separator: "\n")
        #expect(view.currentText == expected)
        #expect(view.session.selection.ranges.count == 50)
    }

    @Test("50-cursor insertion and delete backward round trip through the editor surface")
    func fiftyCursorInsertionAndDeleteRoundTrip() {
        let text = (0..<50)
            .map { "line-\($0)" }
            .joined(separator: "\n")
        let view = EditorView(text: text)
        let carets = view.session.document.buffer.lineStartOffsets.prefix(50).map {
            EditorTextRange(location: $0, length: 0)
        }

        view.setSelection(EditorSelection(ranges: Array(carets)))
        #expect(view.handleTextInsertion("> "))
        #expect(view.currentText.hasPrefix("> line-0"))

        #expect(view.handleDeleteBackward())
        #expect(view.handleDeleteBackward())

        #expect(view.currentText == text)
        #expect(view.session.selection.ranges.count == 50)
    }

    @Test("additive cursor requests preserve existing carets and enable multi-cursor editing")
    func additiveCursorRequestsEnableMultiCursorEditing() {
        let view = EditorView(text: "alpha\nbeta\ngamma")

        view.setSelection(.caret(at: 0))

        #expect(view.handleAdditiveCursor(atUTF16Offset: 6))
        #expect(view.handleAdditiveCursor(atUTF16Offset: 11))
        #expect(view.session.selection.ranges == [
            EditorTextRange(location: 0, length: 0),
            EditorTextRange(location: 6, length: 0),
            EditorTextRange(location: 11, length: 0),
        ])

        #expect(view.handleTextInsertion(">"))
        #expect(view.currentText == ">alpha\n>beta\n>gamma")
    }

    @Test("additive cursor requests clamp and deduplicate UTF-16 offsets")
    func additiveCursorRequestsClampAndDeduplicateOffsets() {
        let view = EditorView(text: "abc")

        view.setSelection(.caret(at: 1))

        #expect(view.handleAdditiveCursor(atUTF16Offset: -10))
        #expect(view.handleAdditiveCursor(atUTF16Offset: 99))
        #expect(view.handleAdditiveCursor(atUTF16Offset: 3))

        #expect(view.session.selection.ranges == [
            EditorTextRange(location: 0, length: 0),
            EditorTextRange(location: 1, length: 0),
            EditorTextRange(location: 3, length: 0),
        ])
    }

    @Test("command and option clicks request additive cursors from the text view")
    func modifierClicksRequestAdditiveCursorsFromTextView() throws {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        textView.string = "abc"
        var requestedOffsets: [Int] = []
        textView.additiveCursorHandler = { offset in
            requestedOffsets.append(offset)
            return true
        }

        textView.mouseDown(with: try makeMouseDownEvent(modifiers: [.command]))
        textView.mouseDown(with: try makeMouseDownEvent(modifiers: [.option]))

        #expect(requestedOffsets.count == 2)
        #expect(requestedOffsets.allSatisfy { $0 >= 0 && $0 <= 3 })
    }

    @Test("single-caret text insertion falls back to native NSTextView editing")
    func singleCaretInsertionFallsBackToNativeEditing() {
        let view = EditorView(text: "abc")

        view.setSelection(.caret(at: 1))

        #expect(!view.handleTextInsertion("X"))
        #expect(view.currentText == "abc")
    }

    @Test("single-caret delete backward falls back to native NSTextView editing")
    func singleCaretDeleteFallsBackToNativeEditing() {
        let view = EditorView(text: "abc")

        view.setSelection(.caret(at: 1))

        #expect(!view.handleDeleteBackward())
        #expect(view.currentText == "abc")
    }

    @Test("inline completion ghost text accepts with Tab")
    func inlineCompletionAcceptsWithTab() throws {
        let view = EditorView(text: "let value = ")
        let textView: EditorTextView = try #require(findSubview(in: view))
        let caret = (view.currentText as NSString).length

        view.setSelection(.caret(at: caret))
        #expect(view.showInlineCompletion(InlineCompletion(
            text: "42",
            replacementRange: EditorTextRange(location: caret, length: 0),
            source: .foundationModelsOnDevice
        )))

        textView.keyDown(with: try makeTabKeyDownEvent())

        #expect(view.currentText == "let value = 42")
        #expect(view.inlineCompletionText == nil)
        #expect(view.session.selection == .caret(at: caret + 2))
    }

    @Test("inline completion ghost text dismisses with Escape")
    func inlineCompletionDismissesWithEscape() throws {
        let view = EditorView(text: "let value = ")
        let textView: EditorTextView = try #require(findSubview(in: view))
        let caret = (view.currentText as NSString).length

        view.setSelection(.caret(at: caret))
        #expect(view.showInlineCompletion(InlineCompletion(
            text: "42",
            replacementRange: EditorTextRange(location: caret, length: 0),
            source: .foundationModelsOnDevice
        )))

        textView.keyDown(with: try makeEscapeKeyDownEvent())

        #expect(view.currentText == "let value = ")
        #expect(view.inlineCompletionText == nil)
        #expect(view.session.selection == .caret(at: caret))
    }

    @Test("inline completion engine requests suggestions only when enabled and language is code")
    func inlineCompletionEngineRequestsSuggestions() async throws {
        let fileURL = try makeTemporaryFile(named: "Sample.swift", contents: "let value = ")
        let view = EditorView(fileURL: fileURL)
        let caret = (view.currentText as NSString).length
        let provider = ImmediateInlineCompletionProvider(text: "42")

        view.setSelection(.caret(at: caret))
        view.setInlineCompletionEngine(CompletionEngine(
            provider: provider,
            config: CompletionConfig(inlineAIEnabled: true, enabledLanguageIDs: ["swift"])
        ))

        #expect(view.requestInlineCompletion(idleDuration: 1.0))
        try await waitForInlineCompletion(in: view)

        #expect(view.inlineCompletionText == "42")
        #expect(await provider.requestCount == 1)
    }

    @Test("vim mode is disabled by default and does not intercept editor input")
    func vimModeIsDisabledByDefault() {
        let view = EditorView(text: "abc")

        #expect(!view.isVimModeEnabled)
        #expect(!view.handleVimInput(.character("l")))
        #expect(view.session.selection == .caret(at: 0))
    }

    @Test("vim mode keyDown motions update the editor selection when enabled")
    func vimModeKeyDownMotionsUpdateSelection() throws {
        let view = EditorView(text: "abc\ndef")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("j"))

        #expect(view.session.selection == .caret(at: 6))
        #expect(view.currentText == "abc\ndef")
    }

    @Test("vim insert mode keyDown mutates text through the editor session")
    func vimInsertModeKeyDownMutatesText() throws {
        let view = EditorView(text: "abc")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 1))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("i"))
        textView.keyDown(with: try makeKeyDownEvent("X"))
        textView.keyDown(with: try makeEscapeKeyDownEvent())

        #expect(view.currentText == "aXbc")
        #expect(view.session.selection == .caret(at: 2))
        #expect(view.vimMode == .normal)
    }

    @Test("vim visual mode keyDown selection and yank round trip through the editor session")
    func vimVisualModeKeyDownYanksSelection() throws {
        let view = EditorView(text: "one two three")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 4))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("v"))
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("l"))

        #expect(view.vimMode == .visual)
        #expect(view.session.selection.primaryRange == EditorTextRange(location: 4, length: 3))

        textView.keyDown(with: try makeKeyDownEvent("y"))

        #expect(view.vimMode == .normal)
        #expect(view.currentText == "one two three")
        #expect(view.session.selection == .caret(at: 4))
    }

    @Test("vim visual line mode keyDown deletes complete lines through the editor session")
    func vimVisualLineModeKeyDownDeletesLines() throws {
        let view = EditorView(text: "one\ntwo\nthree\nfour\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 4))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("V"))
        textView.keyDown(with: try makeKeyDownEvent("j"))

        #expect(view.vimMode == .visualLine)
        #expect(view.session.selection.primaryRange == EditorTextRange(location: 4, length: 10))

        textView.keyDown(with: try makeKeyDownEvent("d"))

        #expect(view.vimMode == .normal)
        #expect(view.currentText == "one\nfour\n")
        #expect(view.session.selection == .caret(at: 4))
    }

    @Test("vim visual block mode keyDown deletes rectangular selections through the editor session")
    func vimVisualBlockModeKeyDownDeletesColumns() throws {
        let view = EditorView(text: "abcd\nefgh\nijkl")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 1))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("v", modifiers: .control))
        textView.keyDown(with: try makeKeyDownEvent("l"))
        textView.keyDown(with: try makeKeyDownEvent("j"))

        #expect(view.vimMode == .visualBlock)
        #expect(view.session.selection.ranges == [
            EditorTextRange(location: 1, length: 2),
            EditorTextRange(location: 6, length: 2),
        ])

        textView.keyDown(with: try makeKeyDownEvent("d"))

        #expect(view.vimMode == .normal)
        #expect(view.currentText == "ad\neh\nijkl")
        #expect(view.session.selection == .caret(at: 1))
    }

    @Test("vim replace mode keyDown overwrites text through the editor session")
    func vimReplaceModeKeyDownOverwritesText() throws {
        let view = EditorView(text: "abcd")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 1))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("R"))
        textView.keyDown(with: try makeKeyDownEvent("X"))
        textView.keyDown(with: try makeKeyDownEvent("Y"))
        textView.keyDown(with: try makeEscapeKeyDownEvent())

        #expect(view.vimMode == .normal)
        #expect(view.currentText == "aXYd")
        #expect(view.session.selection == .caret(at: 3))
    }

    @Test("vim undo groups insert mode edits until escape and control-r redoes them")
    func vimUndoRedoGroupsInsertModeEdits() throws {
        let view = EditorView(text: "abc")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 1))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("i"))
        textView.keyDown(with: try makeKeyDownEvent("X"))
        textView.keyDown(with: try makeKeyDownEvent("Y"))
        textView.keyDown(with: try makeEscapeKeyDownEvent())

        #expect(view.vimMode == .normal)
        #expect(view.currentText == "aXYbc")
        #expect(view.session.selection == .caret(at: 3))

        textView.keyDown(with: try makeKeyDownEvent("u"))

        #expect(view.currentText == "abc")
        #expect(view.session.selection == .caret(at: 1))

        textView.keyDown(with: try makeKeyDownEvent("r", modifiers: .control))

        #expect(view.currentText == "aXYbc")
        #expect(view.session.selection == .caret(at: 3))
    }

    @Test("vim undo and control-r redo a normal-mode line delete")
    func vimUndoRedoNormalModeLineDelete() throws {
        let view = EditorView(text: "one\ntwo\nthree\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 4))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("d"))
        textView.keyDown(with: try makeKeyDownEvent("d"))

        #expect(view.currentText == "one\nthree\n")
        #expect(view.session.selection == .caret(at: 4))

        textView.keyDown(with: try makeKeyDownEvent("u"))

        #expect(view.currentText == "one\ntwo\nthree\n")
        #expect(view.session.selection == .caret(at: 4))

        textView.keyDown(with: try makeKeyDownEvent("r", modifiers: .control))

        #expect(view.currentText == "one\nthree\n")
        #expect(view.session.selection == .caret(at: 4))
    }

    @Test("vim command-line write saves the current editor file")
    func vimCommandLineWriteSavesFile() throws {
        let fileURL = try makeTemporaryFile(contents: "old\n")
        let view = EditorView(fileURL: fileURL)
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.replaceText("new\n")
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent(":"))
        textView.keyDown(with: try makeKeyDownEvent("w"))
        textView.keyDown(with: try makeReturnKeyDownEvent())

        #expect(view.vimMode == .normal)
        #expect(!view.isDirty)
        #expect(view.statusText == "Written")
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "new\n")
    }

    @Test("vim command-line q refuses to quit a dirty editor")
    func vimCommandLineQuitRefusesDirtyEditor() throws {
        let fileURL = try makeTemporaryFile(contents: "old\n")
        let view = EditorView(fileURL: fileURL)
        let textView: EditorTextView = try #require(findSubview(in: view))
        var quitRequests = 0
        view.onQuitRequested = { quitRequests += 1 }

        view.replaceText("new\n")
        view.setVimModeEnabled(true)
        try enterVimCommand("q", into: textView)

        #expect(view.vimMode == .normal)
        #expect(view.isDirty)
        #expect(view.statusText == "No write since last change")
        #expect(quitRequests == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "old\n")
    }

    @Test("vim command-line q requests close for a clean editor")
    func vimCommandLineQuitRequestsCloseForCleanEditor() throws {
        let fileURL = try makeTemporaryFile(contents: "clean\n")
        let view = EditorView(fileURL: fileURL)
        let textView: EditorTextView = try #require(findSubview(in: view))
        var quitRequests = 0
        view.onQuitRequested = { quitRequests += 1 }

        #expect(!view.isDirty)

        view.setVimModeEnabled(true)
        try enterVimCommand("q", into: textView)

        #expect(view.vimMode == .normal)
        #expect(!view.isDirty)
        #expect(quitRequests == 1)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "clean\n")
    }

    @Test("vim command-line wq saves the current editor file")
    func vimCommandLineWriteQuitSavesFile() throws {
        let fileURL = try makeTemporaryFile(contents: "old\n")
        let view = EditorView(fileURL: fileURL)
        let textView: EditorTextView = try #require(findSubview(in: view))
        var quitRequests = 0
        view.onQuitRequested = { quitRequests += 1 }

        view.replaceText("new\n")
        view.setVimModeEnabled(true)
        try enterVimCommand("wq", into: textView)

        #expect(view.vimMode == .normal)
        #expect(!view.isDirty)
        #expect(view.statusText == "Written")
        #expect(quitRequests == 1)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "new\n")
    }

    @Test("vim uppercase mark jump loads the marked file in the same editor")
    func vimUppercaseMarkJumpLoadsMarkedFile() throws {
        let firstURL = try makeTemporaryFile(named: "Marked.swift", contents: "one\n  two\nthree\n")
        let secondURL = try makeTemporaryFile(named: "Current.swift", contents: "alpha\nbeta\n")
        let view = EditorView(fileURL: firstURL)
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setVimModeEnabled(true)
        view.setSelection(.caret(at: 7))
        textView.keyDown(with: try makeKeyDownEvent("m"))
        textView.keyDown(with: try makeKeyDownEvent("A"))

        view.loadFile(secondURL)
        #expect(view.fileURL == secondURL)
        #expect(view.currentText == "alpha\nbeta\n")

        textView.keyDown(with: try makeKeyDownEvent("'"))
        textView.keyDown(with: try makeKeyDownEvent("A"))

        #expect(view.fileURL == firstURL)
        #expect(view.currentText == "one\n  two\nthree\n")
        #expect(view.session.selection == .caret(at: 6))
    }

    @Test("vim command-line set nowrap disables editor soft wrap")
    func vimCommandLineSetNoWrapDisablesSoftWrap() throws {
        let view = EditorView(text: "let value = 1\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        #expect(view.isSoftWrapEnabled)

        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent(":"))
        textView.keyDown(with: try makeKeyDownEvent("s"))
        textView.keyDown(with: try makeKeyDownEvent("e"))
        textView.keyDown(with: try makeKeyDownEvent("t"))
        textView.keyDown(with: try makeKeyDownEvent(" "))
        textView.keyDown(with: try makeKeyDownEvent("n"))
        textView.keyDown(with: try makeKeyDownEvent("o"))
        textView.keyDown(with: try makeKeyDownEvent("w"))
        textView.keyDown(with: try makeKeyDownEvent("r"))
        textView.keyDown(with: try makeKeyDownEvent("a"))
        textView.keyDown(with: try makeKeyDownEvent("p"))
        textView.keyDown(with: try makeReturnKeyDownEvent())

        #expect(view.vimMode == .normal)
        #expect(!view.isSoftWrapEnabled)
        #expect(view.currentText == "let value = 1\n")
    }

    @Test("vim command-line set wrap enables editor soft wrap")
    func vimCommandLineSetWrapEnablesSoftWrap() throws {
        let view = EditorView(text: "let value = 1\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSoftWrapEnabled(false)
        #expect(!view.isSoftWrapEnabled)

        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent(":"))
        textView.keyDown(with: try makeKeyDownEvent("s"))
        textView.keyDown(with: try makeKeyDownEvent("e"))
        textView.keyDown(with: try makeKeyDownEvent("t"))
        textView.keyDown(with: try makeKeyDownEvent(" "))
        textView.keyDown(with: try makeKeyDownEvent("w"))
        textView.keyDown(with: try makeKeyDownEvent("r"))
        textView.keyDown(with: try makeKeyDownEvent("a"))
        textView.keyDown(with: try makeKeyDownEvent("p"))
        textView.keyDown(with: try makeReturnKeyDownEvent())

        #expect(view.vimMode == .normal)
        #expect(view.isSoftWrapEnabled)
        #expect(view.currentText == "let value = 1\n")
    }

    @Test("vim command-line set wrap bang toggles editor soft wrap")
    func vimCommandLineSetWrapBangTogglesSoftWrap() throws {
        let view = EditorView(text: "let value = 1\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        #expect(view.isSoftWrapEnabled)

        view.setVimModeEnabled(true)
        try enterVimCommand("set wrap!", into: textView)

        #expect(!view.isSoftWrapEnabled)

        try enterVimCommand("set invwrap", into: textView)

        #expect(view.isSoftWrapEnabled)
        #expect(view.currentText == "let value = 1\n")
    }

    @Test("vim command-line set wrap question reports editor soft wrap")
    func vimCommandLineSetWrapQuestionReportsSoftWrap() throws {
        let view = EditorView(text: "let value = 1\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSoftWrapEnabled(false)
        view.setVimModeEnabled(true)
        try enterVimCommand("set wrap?", into: textView)

        #expect(!view.isSoftWrapEnabled)
        #expect(view.statusText == "nowrap")
        #expect(view.currentText == "let value = 1\n")
    }

    @Test("vim search mode keyDown moves selection and repeats results")
    func vimSearchModeKeyDownMovesSelection() throws {
        let view = EditorView(text: "one two\nthree two\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 0))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("/"))
        textView.keyDown(with: try makeKeyDownEvent("t"))
        textView.keyDown(with: try makeKeyDownEvent("w"))
        textView.keyDown(with: try makeKeyDownEvent("o"))
        textView.keyDown(with: try makeReturnKeyDownEvent())

        #expect(view.vimMode == .normal)
        #expect(view.session.selection == .caret(at: 4))

        textView.keyDown(with: try makeKeyDownEvent("n"))
        #expect(view.session.selection == .caret(at: 14))

        textView.keyDown(with: try makeKeyDownEvent("N"))
        #expect(view.session.selection == .caret(at: 4))
    }

    @Test("vim nohl clears search decorations without clearing repeat search")
    func vimNoHighlightClearsSearchDecorationsOnly() throws {
        let view = EditorView(text: "one two\nthree two\n")
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 0))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("/"))
        textView.keyDown(with: try makeKeyDownEvent("t"))
        textView.keyDown(with: try makeKeyDownEvent("w"))
        textView.keyDown(with: try makeKeyDownEvent("o"))
        textView.keyDown(with: try makeReturnKeyDownEvent())

        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 20),
            kinds: [.searchResult]
        ).map(\.range) == [
            EditorTextRange(location: 4, length: 3),
            EditorTextRange(location: 14, length: 3),
        ])

        try enterVimCommand("nohl", into: textView)

        #expect(view.session.decorations.intersecting(
            EditorTextRange(location: 0, length: 20),
            kinds: [.searchResult]
        ).isEmpty)

        textView.keyDown(with: try makeKeyDownEvent("n"))
        #expect(view.session.selection == .caret(at: 14))
    }

    @Test("vim system clipboard register uses the editor clipboard service")
    func vimSystemClipboardRegisterUsesEditorClipboardService() throws {
        let clipboard = MockClipboardService()
        let view = EditorView(text: "one\ntwo\n", clipboardService: clipboard)
        let textView: EditorTextView = try #require(findSubview(in: view))

        view.setSelection(.caret(at: 0))
        view.setVimModeEnabled(true)
        textView.keyDown(with: try makeKeyDownEvent("\""))
        textView.keyDown(with: try makeKeyDownEvent("+"))
        textView.keyDown(with: try makeKeyDownEvent("y"))
        textView.keyDown(with: try makeKeyDownEvent("y"))

        #expect(clipboard.read() == "one\n")
        #expect(view.currentText == "one\ntwo\n")

        clipboard.write("clip\n")
        textView.keyDown(with: try makeKeyDownEvent("\""))
        textView.keyDown(with: try makeKeyDownEvent("+"))
        textView.keyDown(with: try makeKeyDownEvent("p"))

        #expect(view.currentText == "one\nclip\ntwo\n")
        #expect(view.session.selection == .caret(at: 4))
    }

    private func makeTemporaryFile(contents: String) throws -> URL {
        try makeTemporaryFile(named: "Sample.swift", contents: contents)
    }

    private func makeTemporaryFile(named fileName: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-editor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func enterVimCommand(_ command: String, into textView: EditorTextView) throws {
        textView.keyDown(with: try makeKeyDownEvent(":"))
        for character in command {
            textView.keyDown(with: try makeKeyDownEvent(String(character)))
        }
        textView.keyDown(with: try makeReturnKeyDownEvent())
    }

    private func makeRepositorySyntaxService(resourcesURL: URL) throws -> SyntaxTreeService {
        let manifest = try SyntaxLanguageManifestLoader(bundleResourceURL: resourcesURL).load()
        let registry = try SyntaxLanguageRegistry(manifest: manifest) { resource in
            FileManager.default.fileExists(
                atPath: resourcesURL.appendingPathComponent(resource, isDirectory: false).path
            )
        }
        let symbolProvider = TreeSitterSymbolProvider.bundledOrProcess(bundleResourceURL: resourcesURL)
        let parser = SyntaxTreeParser(
            bundleLoader: SyntaxGrammarBundleLoader(
                locator: SyntaxGrammarLocator(bundleResourceURL: resourcesURL),
                checksumVerifier: SyntaxGrammarChecksumVerifier(),
                queryLoader: SyntaxHighlightQueryLoader(bundleResourceURL: resourcesURL),
                dynamicLoader: SyntaxGrammarDynamicLoader()
            ),
            runtime: SyntaxTreeRuntime.treeSitterOrUnavailable(symbolProvider: symbolProvider),
            extractTokens: { tree, bundle, buffer in
                guard let adapter = TreeSitterHighlightQueryAdapter.resolveBundledOrProcess(
                    symbolProvider: symbolProvider
                ) else {
                    return []
                }
                return try SyntaxHighlightQueryExecutor { tree, querySource, buffer in
                    try adapter.collectCaptures(
                        for: tree,
                        bundle: bundle,
                        querySource: querySource,
                        buffer: buffer
                    )
                }
                .tokens(for: tree, querySource: bundle.querySource, buffer: buffer)
            }
        )
        return SyntaxTreeService(registry: registry, parser: parser)
    }

    private func waitForInlineCompletion(in view: EditorView) async throws {
        let deadline = Date().addingTimeInterval(1.0)
        while view.inlineCompletionText == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizationBundle() -> Bundle? {
        Bundle(url: repositoryRoot().appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func findSubview<T: NSView>(in root: NSView) -> T? {
        if let root = root as? T { return root }
        for subview in root.subviews {
            if let match: T = findSubview(in: subview) {
                return match
            }
        }
        return nil
    }

    private func makeMouseDownEvent(modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 4, y: 4),
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func makeKeyDownEvent(
        _ character: String,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        ))
    }

    private func makeEscapeKeyDownEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    private func makeTabKeyDownEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))
    }

    private func makeReturnKeyDownEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }
}

private actor ImmediateInlineCompletionProvider: InlineCompletionProviding {
    let text: String
    private(set) var requestCount = 0

    init(text: String) {
        self.text = text
    }

    func completion(for context: CompletionContext) async throws -> InlineCompletion? {
        requestCount += 1
        return InlineCompletion(
            text: text,
            replacementRange: context.caretRange,
            source: .foundationModelsOnDevice
        )
    }
}
