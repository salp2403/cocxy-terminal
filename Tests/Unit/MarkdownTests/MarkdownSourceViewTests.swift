// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownSourceView", .serialized)
@MainActor
struct MarkdownSourceViewTests {

    @Test("source view is editable plain text with find bar enabled")
    func sourceViewIsEditable() {
        let view = MarkdownSourceView()
        let editor = view.editorTextView

        #expect(editor.isEditable == true)
        #expect(editor.isRichText == false)
        #expect(editor.usesFindBar == true)
        #expect(editor.isIncrementalSearchingEnabled == true)
    }

    @Test("applyBold wraps selected text")
    func applyBoldWrapsSelection() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("hello")
        view.setSelectedSourceRange(NSRange(location: 0, length: 5))

        view.applyBold()

        #expect(view.currentSource == "**hello**")
        #expect(view.selectedSourceRange == NSRange(location: 2, length: 5))
    }

    @Test("applyBold unwraps an already wrapped selection")
    func applyBoldUnwrapsSelection() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("**hello**")
        view.setSelectedSourceRange(NSRange(location: 2, length: 5))

        view.applyBold()

        #expect(view.currentSource == "hello")
        #expect(view.selectedSourceRange == NSRange(location: 0, length: 5))
    }

    @Test("applyItalic wraps selected text")
    func applyItalicWrapsSelection() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("hello")
        view.setSelectedSourceRange(NSRange(location: 0, length: 5))

        view.applyItalic()

        #expect(view.currentSource == "*hello*")
        #expect(view.selectedSourceRange == NSRange(location: 1, length: 5))
    }

    @Test("applyLink wraps selected text and selects the URL placeholder")
    func applyLinkWrapsSelection() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("hello")
        view.setSelectedSourceRange(NSRange(location: 0, length: 5))

        view.applyLink()

        #expect(view.currentSource == "[hello](https://)")
        #expect(view.selectedSourceRange == NSRange(location: 8, length: 8))
    }

    @Test("applyStrikethrough wraps selected text")
    func applyStrikethroughWrapsSelection() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("hello")
        view.setSelectedSourceRange(NSRange(location: 0, length: 5))

        view.applyStrikethrough()

        #expect(view.currentSource == "~~hello~~")
        #expect(view.selectedSourceRange == NSRange(location: 2, length: 5))
    }

    @Test("cycleHeading adds and increments heading markers")
    func cycleHeadingUpdatesCurrentLine() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("Heading")
        view.setSelectedSourceRange(NSRange(location: 0, length: 0))

        view.cycleHeading()
        #expect(view.currentSource == "# Heading")

        view.cycleHeading()
        #expect(view.currentSource == "## Heading")
    }

    @Test("Cmd+B key equivalent formats the current selection")
    func commandBFormatsSelection() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("hello")
        view.setSelectedSourceRange(NSRange(location: 0, length: 5))

        let event = makeKeyEvent(characters: "b", modifiers: .command)
        let handled = view.editorTextView.performKeyEquivalent(with: event)

        #expect(handled == true)
        #expect(view.currentSource == "**hello**")
    }

    @Test("Cmd+Shift+X applies strikethrough")
    func commandShiftXStrikethrough() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("hello")
        view.setSelectedSourceRange(NSRange(location: 0, length: 5))

        let event = makeKeyEvent(characters: "x", modifiers: [.command, .shift])
        let handled = view.editorTextView.performKeyEquivalent(with: event)

        #expect(handled == true)
        #expect(view.currentSource == "~~hello~~")
    }

    @Test("Cmd+Shift+H cycles heading level")
    func commandShiftHCyclesHeading() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("Heading")
        view.setSelectedSourceRange(NSRange(location: 0, length: 0))

        let event = makeKeyEvent(characters: "h", modifiers: [.command, .shift])

        #expect(view.editorTextView.performKeyEquivalent(with: event) == true)
        #expect(view.currentSource == "# Heading")

        #expect(view.editorTextView.performKeyEquivalent(with: event) == true)
        #expect(view.currentSource == "## Heading")
    }

    @Test("insert helpers create common markdown blocks")
    func insertHelpersCreateBlocks() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("")

        view.insertTable()
        #expect(view.currentSource.contains("| Column 1 | Column 2 |"))

        view.replaceEntireSource(with: "")
        view.insertBlockquote()
        #expect(view.currentSource == "> ")

        view.replaceEntireSource(with: "")
        view.insertHorizontalRule()
        #expect(view.currentSource == "---")

        view.replaceEntireSource(with: "")
        view.insertCodeBlock()
        #expect(view.currentSource == "```\n\n```")

        view.replaceEntireSource(with: "")
        view.insertMathBlock()
        #expect(view.currentSource == "$$\n\n$$")
    }

    private func makeKeyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}
