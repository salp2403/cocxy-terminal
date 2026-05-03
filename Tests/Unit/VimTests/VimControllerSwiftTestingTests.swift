// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VimControllerSwiftTestingTests.swift - Phase D editor-only Vim state machine coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Vim controller")
struct VimControllerSwiftTestingTests {
    @Test("insert mode accepts text and escape returns to normal")
    func insertModeAcceptsTextAndEscapeReturnsToNormal() {
        var session = EditorSession(
            document: EditorDocument(text: "abc"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.mode == .normal)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.mode == .insert)

        #expect(controller.handle(.text("X"), session: &session).handled)
        #expect(session.document.buffer.text == "aXbc")
        #expect(session.selection == .caret(at: 2))

        #expect(controller.handle(.escape, session: &session).handled)
        #expect(controller.mode == .normal)
    }

    @Test("normal mode motions move the caret without mutating text")
    func normalModeMotionsMoveCaretWithoutMutatingText() {
        var session = EditorSession(
            document: EditorDocument(text: "abc\ndef\nxyz"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(session.selection == .caret(at: 2))

        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(session.selection == .caret(at: 6))

        #expect(controller.handle(.character("0"), session: &session).handled)
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.character("$"), session: &session).handled)
        #expect(session.selection == .caret(at: 6))
        #expect(session.document.buffer.text == "abc\ndef\nxyz")
    }

    @Test("WORD motions treat punctuation as part of the word")
    func wordMotionsTreatPunctuationAsPartOfWord() {
        var session = EditorSession(
            document: EditorDocument(text: "foo.bar baz"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("W"), session: &session).handled)
        #expect(session.selection == .caret(at: 8))

        #expect(controller.handle(.character("B"), session: &session).handled)
        #expect(session.selection == .caret(at: 0))
        #expect(session.document.buffer.text == "foo.bar baz")
    }

    @Test("% jumps between matching delimiters")
    func percentJumpsBetweenMatchingDelimiters() {
        var session = EditorSession(
            document: EditorDocument(text: "func(a[bc])"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("%"), session: &session).handled)
        #expect(session.selection == .caret(at: 10))

        #expect(controller.handle(.character("%"), session: &session).handled)
        #expect(session.selection == .caret(at: 4))
    }

    @Test("[{ and ]} jump across nested brace blocks")
    func bracketBraceMotionsJumpAcrossNestedBraceBlocks() {
        let text = "func outer() {\n  if ok {\n    call()\n  }\n}\n"
        let nsText = text as NSString
        let ifOffset = nsText.range(of: "if ok").location
        let callOffset = nsText.range(of: "call").location
        let innerOpen = nsText.range(
            of: "{",
            options: [],
            range: NSRange(location: ifOffset, length: nsText.length - ifOffset)
        ).location
        let innerClose = nsText.range(
            of: "}",
            options: [],
            range: NSRange(location: callOffset, length: nsText.length - callOffset)
        ).location
        var session = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: callOffset)
        )
        var controller = VimController()

        #expect(controller.handle(.character("["), session: &session).handled)
        #expect(controller.handle(.character("{"), session: &session).handled)
        #expect(session.selection == .caret(at: innerOpen))

        session.setSelection(.caret(at: callOffset))
        #expect(controller.handle(.character("]"), session: &session).handled)
        #expect(controller.handle(.character("}"), session: &session).handled)
        #expect(session.selection == .caret(at: innerClose))
    }

    @Test("find motions move within the current line and repeat with semicolon and comma")
    func findMotionsRepeatWithinCurrentLine() {
        var session = EditorSession(
            document: EditorDocument(text: "abacad\nzzza"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("f"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(session.selection == .caret(at: 2))

        #expect(controller.handle(.character(";"), session: &session).handled)
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.character(","), session: &session).handled)
        #expect(session.selection == .caret(at: 2))
    }

    @Test("till motions stop before or after the target character")
    func tillMotionsStopAdjacentToTarget() {
        var session = EditorSession(
            document: EditorDocument(text: "abacad"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("t"), session: &session).handled)
        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(session.selection == .caret(at: 2))

        #expect(controller.handle(.character("T"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(session.selection == .caret(at: 1))
    }

    @Test("normal mode text input is consumed without inserting text")
    func normalModeTextInputIsConsumedWithoutInsertingText() {
        var session = EditorSession(
            document: EditorDocument(text: "abc"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.text("X"), session: &session).handled)
        #expect(session.document.buffer.text == "abc")
        #expect(session.selection == .caret(at: 1))
    }

    @Test("v enters visual character mode and motions extend the selection")
    func visualModeMotionsExtendSelection() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.mode == .visual)
        #expect(session.selection.primaryRange == EditorTextRange(location: 4, length: 1))

        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)

        #expect(controller.mode == .visual)
        #expect(session.selection.primaryRange == EditorTextRange(location: 4, length: 3))
        #expect(session.document.buffer.text == "one two three")
    }

    @Test("visual yank stores selected text and returns to normal mode")
    func visualYankStoresSelectedTextAndReturnsNormal() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "two")
        #expect(session.document.buffer.text == "one two three")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("visual delete removes selected text and returns to normal mode")
    func visualDeleteRemovesSelectedTextAndReturnsNormal() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "two")
        #expect(session.document.buffer.text == "one  three")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("dot repeats a visual character delete at the current caret")
    func dotRepeatsVisualCharacterDeleteAtCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd efgh"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(session.document.buffer.text == "ad efgh")

        session.setSelection(.caret(at: 3))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "ad gh")
        #expect(session.selection == .caret(at: 3))
        #expect(controller.unnamedRegister == "ef")
    }

    @Test("V enters visual line mode and motions extend whole-line selection")
    func visualLineModeMotionsExtendWholeLineSelection() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("V"), session: &session).handled)
        #expect(controller.mode == .visualLine)
        #expect(session.selection.primaryRange == EditorTextRange(location: 4, length: 4))

        #expect(controller.handle(.character("j"), session: &session).handled)

        #expect(controller.mode == .visualLine)
        #expect(session.selection.primaryRange == EditorTextRange(location: 4, length: 10))
        #expect(session.document.buffer.string(in: session.selection.primaryRange) == "two\nthree\n")
    }

    @Test("visual line yank stores complete lines and returns normal")
    func visualLineYankStoresCompleteLines() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("V"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "two\nthree\n")
        #expect(session.selection == .caret(at: 4))
        #expect(session.document.buffer.text == "one\ntwo\nthree\nfour\n")
    }

    @Test("visual line delete removes complete lines and returns normal")
    func visualLineDeleteRemovesCompleteLines() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("V"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "two\nthree\n")
        #expect(session.document.buffer.text == "one\nfour\n")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("dot repeats a visual line delete at the current line")
    func dotRepeatsVisualLineDeleteAtCurrentLine() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\nfive\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("V"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(session.document.buffer.text == "one\nfour\nfive\n")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "one\n")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "four\nfive\n")
    }

    @Test("control-v enters visual block mode and motions extend rectangular selections")
    func visualBlockModeMotionsExtendRectangularSelections() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd\nefgh\nijkl"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\u{16}"), session: &session).handled)
        #expect(controller.mode == .visualBlock)
        #expect(session.selection.ranges == [EditorTextRange(location: 1, length: 1)])

        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)

        #expect(controller.mode == .visualBlock)
        #expect(session.selection.ranges == [
            EditorTextRange(location: 1, length: 2),
            EditorTextRange(location: 6, length: 2),
        ])
        #expect(session.selection.primaryRange == EditorTextRange(location: 6, length: 2))
    }

    @Test("visual block yank stores selected columns line by line and returns normal")
    func visualBlockYankStoresSelectedColumns() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd\nefgh\nijkl"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\u{16}"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "bc\nfg")
        #expect(session.document.buffer.text == "abcd\nefgh\nijkl")
        #expect(session.selection == .caret(at: 1))
    }

    @Test("visual block delete removes selected columns line by line and returns normal")
    func visualBlockDeleteRemovesSelectedColumns() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd\nefgh\nijkl"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\u{16}"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "bc\nfg")
        #expect(session.document.buffer.text == "ad\neh\nijkl")
        #expect(session.selection == .caret(at: 1))
    }

    @Test("dot repeats a visual block delete from the current caret")
    func dotRepeatsVisualBlockDeleteFromCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd\nefgh\nijkl\nmnop"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\u{16}"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(session.document.buffer.text == "ad\neh\nijkl\nmnop")

        session.setSelection(.caret(at: 7))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "ad\neh\nil\nmp")
        #expect(session.selection == .caret(at: 7))
        #expect(controller.unnamedRegister == "jk\nno")
    }

    @Test("R enters replace mode and overwrites existing characters until escape")
    func replaceModeOverwritesUntilEscape() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("R"), session: &session).handled)
        #expect(controller.mode == .replace)

        #expect(controller.handle(.character("X"), session: &session).handled)
        #expect(controller.handle(.character("Y"), session: &session).handled)

        #expect(session.document.buffer.text == "aXYd")
        #expect(session.selection == .caret(at: 3))

        #expect(controller.handle(.escape, session: &session).handled)
        #expect(controller.mode == .normal)
    }

    @Test("dot repeats replace mode text at the current caret")
    func dotRepeatsReplaceModeTextAtCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "abcde"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("R"), session: &session).handled)
        #expect(controller.handle(.text("XY"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "aXYde")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "aXYXY")
        #expect(session.selection == .caret(at: 5))
    }

    @Test("r replaces one character and returns to normal")
    func singleReplaceReplacesOneCharacter() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("r"), session: &session).handled)
        #expect(controller.handle(.character("X"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(session.document.buffer.text == "aXcd")
        #expect(session.selection == .caret(at: 2))
    }

    @Test("count before r repeats the replacement over existing characters")
    func countBeforeSingleReplaceRepeatsReplacement() {
        var session = EditorSession(
            document: EditorDocument(text: "abcdef"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("3"), session: &session).handled)
        #expect(controller.handle(.character("r"), session: &session).handled)
        #expect(controller.handle(.character("X"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(session.document.buffer.text == "aXXXef")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("dot repeats a single-character replace at the current caret")
    func dotRepeatsSingleCharacterReplaceAtCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("r"), session: &session).handled)
        #expect(controller.handle(.character("X"), session: &session).handled)
        #expect(session.document.buffer.text == "aXcd")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "aXXd")
        #expect(session.selection == .caret(at: 3))
    }

    @Test("dot repeats a counted single-character replace")
    func dotRepeatsCountedSingleCharacterReplace() {
        var session = EditorSession(
            document: EditorDocument(text: "abcdefghi"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("3"), session: &session).handled)
        #expect(controller.handle(.character("r"), session: &session).handled)
        #expect(controller.handle(.character("X"), session: &session).handled)
        #expect(session.document.buffer.text == "aXXXefghi")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "aXXXXXXhi")
        #expect(session.selection == .caret(at: 7))
    }

    @Test(": enters command-line mode and escape cancels without mutating text")
    func commandLineModeBuffersAndCancels() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.mode == .commandLine)
        #expect(controller.commandLineText == "")

        #expect(controller.handle(.text("write"), session: &session).handled)
        #expect(controller.commandLineText == "write")
        #expect(controller.handle(.deleteBackward, session: &session).handled)
        #expect(controller.commandLineText == "writ")

        #expect(controller.handle(.escape, session: &session).handled)
        #expect(controller.mode == .normal)
        #expect(controller.commandLineText == nil)
        #expect(session.document.buffer.text == "alpha beta")
    }

    @Test(":w emits a write command without mutating the document")
    func commandLineWriteEmitsCommand() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(result.exCommand == .write)
        #expect(controller.mode == .normal)
        #expect(controller.commandLineText == nil)
        #expect(session.document.buffer.text == "alpha beta")
    }

    @Test(":q emits a quit command without mutating the document")
    func commandLineQuitEmitsCommand() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.character("q"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(result.exCommand == .quit)
        #expect(controller.mode == .normal)
        #expect(controller.commandLineText == nil)
        #expect(session.document.buffer.text == "alpha beta")
    }

    @Test(":wq emits a write-quit command without mutating the document")
    func commandLineWriteQuitEmitsCommand() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.text("wq"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(result.exCommand == .writeQuit)
        #expect(controller.mode == .normal)
        #expect(controller.commandLineText == nil)
        #expect(session.document.buffer.text == "alpha beta")
    }

    @Test(":nohl emits a clear-search-highlight command without mutating the document")
    func commandLineNoHighlightEmitsCommand() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.text("nohl"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(result.exCommand == .clearSearchHighlights)
        #expect(controller.mode == .normal)
        #expect(controller.commandLineText == nil)
        #expect(session.document.buffer.text == "alpha beta")
    }

    @Test("u emits an undo edit command without mutating text")
    func normalModeUEmitsUndoEditCommand() {
        var session = EditorSession(
            document: EditorDocument(text: "abc"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        let result = controller.handle(.character("u"), session: &session)

        #expect(result.handled)
        #expect(result.editCommand == .undo)
        #expect(controller.mode == .normal)
        #expect(session.document.buffer.text == "abc")
        #expect(session.selection == .caret(at: 1))
    }

    @Test("control-r emits a redo edit command without entering replace")
    func controlREmitsRedoEditCommand() {
        var session = EditorSession(
            document: EditorDocument(text: "abc"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        let result = controller.handle(.character("\u{12}"), session: &session)

        #expect(result.handled)
        #expect(result.editCommand == .redo)
        #expect(controller.mode == .normal)
        #expect(session.document.buffer.text == "abc")
        #expect(session.selection == .caret(at: 1))
    }

    @Test(":%s performs literal global substitution across the document")
    func commandLineSubstituteGlobalReplacesDocumentText() {
        var session = EditorSession(
            document: EditorDocument(text: "foo one\nfoo two\nnope foo\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.text("%s/foo/bar/g"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(result.exCommand == nil)
        #expect(controller.mode == .normal)
        #expect(session.document.buffer.text == "bar one\nbar two\nnope bar\n")
        #expect(session.selection == .caret(at: 0))
    }

    @Test(":s substitutes only the current line")
    func commandLineSubstituteReplacesCurrentLineOnly() {
        var session = EditorSession(
            document: EditorDocument(text: "foo one\nfoo two\nfoo three\n"),
            selection: .caret(at: 8)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.text("s/foo/bar/"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(result.exCommand == nil)
        #expect(controller.mode == .normal)
        #expect(session.document.buffer.text == "foo one\nbar two\nfoo three\n")
        #expect(session.selection == .caret(at: 8))
    }

    @Test(":s without g replaces only the first current-line match")
    func commandLineSubstituteWithoutGlobalFlagReplacesFirstCurrentLineMatch() {
        var session = EditorSession(
            document: EditorDocument(text: "foo foo\nfoo foo\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.text("s/foo/bar/"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(session.document.buffer.text == "bar foo\nfoo foo\n")
        #expect(session.selection == .caret(at: 0))
    }

    @Test(":s with g replaces every current-line match")
    func commandLineSubstituteWithGlobalFlagReplacesAllCurrentLineMatches() {
        var session = EditorSession(
            document: EditorDocument(text: "foo foo\nfoo foo\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character(":"), session: &session).handled)
        #expect(controller.handle(.text("s/foo/bar/g"), session: &session).handled)
        let result = controller.handle(.enter, session: &session)

        #expect(result.handled)
        #expect(session.document.buffer.text == "bar bar\nfoo foo\n")
        #expect(session.selection == .caret(at: 0))
    }

    @Test("/ searches forward, wraps, and n/N repeat the last query")
    func searchForwardWrapsAndRepeats() {
        var session = EditorSession(
            document: EditorDocument(text: "one two\nthree two\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("/"), session: &session).handled)
        #expect(controller.mode == .searchForward)
        #expect(controller.searchLineText == "")
        #expect(controller.handle(.text("two"), session: &session).handled)
        #expect(controller.searchLineText == "two")
        #expect(controller.handle(.enter, session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.character("n"), session: &session).handled)
        #expect(session.selection == .caret(at: 14))

        #expect(controller.handle(.character("n"), session: &session).handled)
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.character("N"), session: &session).handled)
        #expect(session.selection == .caret(at: 14))
    }

    @Test("? searches backward and N reverses the last search direction")
    func searchBackwardAndReverseRepeat() {
        var session = EditorSession(
            document: EditorDocument(text: "one two\nthree two\n"),
            selection: .caret(at: 17)
        )
        var controller = VimController()

        #expect(controller.handle(.character("?"), session: &session).handled)
        #expect(controller.mode == .searchBackward)
        #expect(controller.handle(.text("two"), session: &session).handled)
        #expect(controller.handle(.enter, session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(session.selection == .caret(at: 14))

        #expect(controller.handle(.character("n"), session: &session).handled)
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.character("N"), session: &session).handled)
        #expect(session.selection == .caret(at: 14))
    }

    @Test("escape cancels search input without replacing the last successful search")
    func escapeCancelsSearchInput() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta beta"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("/"), session: &session).handled)
        #expect(controller.handle(.text("beta"), session: &session).handled)
        #expect(controller.handle(.enter, session: &session).handled)
        #expect(session.selection == .caret(at: 6))

        #expect(controller.handle(.character("/"), session: &session).handled)
        #expect(controller.handle(.text("missing"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(controller.mode == .normal)
        #expect(controller.searchLineText == nil)

        #expect(controller.handle(.character("n"), session: &session).handled)
        #expect(session.selection == .caret(at: 11))
        #expect(session.document.buffer.text == "alpha beta beta")
    }

    @Test("escape exits visual mode and restores a caret")
    func escapeExitsVisualModeAndRestoresCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.handle(.character("l"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(session.selection == .caret(at: 4))
    }

    @Test("counts repeat motions")
    func countsRepeatMotions() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three\nfour five six"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("2"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)
        #expect(session.selection == .caret(at: 8))

        #expect(controller.handle(.character("3"), session: &session).handled)
        #expect(controller.handle(.character("h"), session: &session).handled)
        #expect(session.selection == .caret(at: 5))
    }

    @Test("dd deletes whole lines and stores them in the unnamed register")
    func ddDeletesWholeLinesAndStoresThemInUnnamedRegister() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(session.document.buffer.text == "one\nthree\n")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "two\n")
    }

    @Test("counts before dd delete multiple whole lines")
    func countsBeforeDDDeleteMultipleWholeLines() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\nfive\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("3"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(session.document.buffer.text == "one\nfive\n")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "two\nthree\nfour\n")
    }

    @Test("dw deletes to the next word start and stores the deleted text")
    func dwDeletesToNextWordStart() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)

        #expect(session.document.buffer.text == "one three")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "two ")
    }

    @Test("cw changes a word without consuming the following separator")
    func cwChangesWordWithoutConsumingFollowingSeparator() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha beta gamma"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)

        #expect(controller.mode == .insert)
        #expect(controller.unnamedRegister == "alpha")
        #expect(session.document.buffer.text == " beta gamma")
        #expect(session.selection == .caret(at: 0))

        #expect(controller.handle(.text("BETA"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "BETA beta gamma")
    }

    @Test("X deletes backward and dot repeats from the current caret")
    func xUppercaseDeletesBackwardAndDotRepeats() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 2)
        )
        var controller = VimController()

        #expect(controller.handle(.character("X"), session: &session).handled)
        #expect(session.document.buffer.text == "acd")
        #expect(session.selection == .caret(at: 1))
        #expect(controller.unnamedRegister == "b")

        session.setSelection(.caret(at: 2))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "ad")
        #expect(session.selection == .caret(at: 1))
        #expect(controller.unnamedRegister == "c")
    }

    @Test("dW deletes to the next WORD start and stores punctuation")
    func dWDeletesToNextWORDStart() {
        var session = EditorSession(
            document: EditorDocument(text: "one foo.bar baz"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("W"), session: &session).handled)

        #expect(session.document.buffer.text == "one baz")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "foo.bar ")
    }

    @Test("df deletes through the found character")
    func dfDeletesThroughFoundCharacter() {
        var session = EditorSession(
            document: EditorDocument(text: "abxcd"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("f"), session: &session).handled)
        #expect(controller.handle(.character("x"), session: &session).handled)

        #expect(session.document.buffer.text == "cd")
        #expect(session.selection == .caret(at: 0))
        #expect(controller.unnamedRegister == "abx")
    }

    @Test("d% deletes through the matching delimiter")
    func dPercentDeletesThroughMatchingDelimiter() {
        var session = EditorSession(
            document: EditorDocument(text: "func(a[bc]) tail"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("%"), session: &session).handled)

        #expect(session.document.buffer.text == "func tail")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "(a[bc])")
    }

    @Test("y% yanks through the matching delimiter without mutating text")
    func yPercentYanksThroughMatchingDelimiterWithoutMutatingText() {
        var session = EditorSession(
            document: EditorDocument(text: "func(a[bc]) tail"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("%"), session: &session).handled)

        #expect(session.document.buffer.text == "func(a[bc]) tail")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "(a[bc])")
    }

    @Test("c% changes through the matching delimiter and dot repeats")
    func cPercentChangesThroughMatchingDelimiterAndDotRepeats() {
        let text = "one(a)\ntwo(b)"
        var session = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: (text as NSString).range(of: "(").location)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("%"), session: &session).handled)
        #expect(controller.mode == .insert)
        #expect(controller.handle(.text("x"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "onex\ntwo(b)")

        let secondOpen = (session.document.buffer.text as NSString).range(of: "(").location
        session.setSelection(.caret(at: secondOpen))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "onex\ntwox")
    }

    @Test("visual percent extends to the matching delimiter before delete")
    func visualPercentExtendsToMatchingDelimiterBeforeDelete() {
        var session = EditorSession(
            document: EditorDocument(text: "func(a) tail"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.handle(.character("%"), session: &session).handled)
        #expect(session.selection.primaryRange == EditorTextRange(location: 4, length: 3))

        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(session.document.buffer.text == "func tail")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "(a)")
    }

    @Test("visual find extends the selection before delete")
    func visualFindExtendsSelectionBeforeDelete() {
        var session = EditorSession(
            document: EditorDocument(text: "abcde"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("v"), session: &session).handled)
        #expect(controller.handle(.character("f"), session: &session).handled)
        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(session.selection.primaryRange == EditorTextRange(location: 0, length: 3))

        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(session.document.buffer.text == "de")
        #expect(session.selection == .caret(at: 0))
        #expect(controller.unnamedRegister == "abc")
    }

    @Test("ct changes until the target and dot repeats the same find change")
    func ctChangesUntilTargetAndDotRepeats() {
        var session = EditorSession(
            document: EditorDocument(text: "abcx defx"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("t"), session: &session).handled)
        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(controller.handle(.text("Z"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "Zx defx")

        session.setSelection(.caret(at: 3))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "Zx Zx")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "def")
    }

    @Test("ciw changes the current word and enters insert mode")
    func ciwChangesCurrentWordAndEntersInsertMode() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 5)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)

        #expect(controller.mode == .insert)
        #expect(controller.unnamedRegister == "two")
        #expect(session.document.buffer.text == "one  three")
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.text("\"new\""), session: &session).handled)
        #expect(session.document.buffer.text == "one \"new\" three")
    }

    @Test("daw deletes the current word and adjacent whitespace")
    func dawDeletesCurrentWordAndAdjacentWhitespace() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 5)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "two ")
        #expect(session.document.buffer.text == "one three")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("dip deletes the current paragraph without the separator blank line")
    func dipDeletesCurrentParagraphWithoutSeparatorBlankLine() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha\nbeta\n\nsecond\nthird\n\nlast\n"),
            selection: .caret(at: 7)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "alpha\nbeta\n")
        #expect(session.document.buffer.text == "\nsecond\nthird\n\nlast\n")
        #expect(session.selection == .caret(at: 0))
    }

    @Test("dap deletes the current paragraph and following blank separator")
    func dapDeletesCurrentParagraphAndFollowingBlankSeparator() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha\nbeta\n\nsecond\nthird\n\nlast\n"),
            selection: .caret(at: 15)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "second\nthird\n\n")
        #expect(session.document.buffer.text == "alpha\nbeta\n\nlast\n")
        #expect(session.selection == .caret(at: 12))
    }

    @Test("dap on the last paragraph deletes the preceding blank separator")
    func dapOnLastParagraphDeletesPrecedingBlankSeparator() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha\nbeta\n\nlast\n"),
            selection: .caret(at: 14)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "\nlast\n")
        #expect(session.document.buffer.text == "alpha\nbeta\n")
        #expect(session.selection == .caret(at: 11))
    }

    @Test("paragraph text objects honor counts across adjacent paragraphs")
    func paragraphTextObjectsHonorCountsAcrossAdjacentParagraphs() {
        var session = EditorSession(
            document: EditorDocument(text: "alpha\nbeta\n\nsecond\nthird\n\nlast\n"),
            selection: .caret(at: 2)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("2"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "alpha\nbeta\n\nsecond\nthird\n")
        #expect(session.document.buffer.text == "\nlast\n")
        #expect(session.selection == .caret(at: 0))
    }

    @Test("yi double quote yanks text inside the enclosing quotes")
    func yiDoubleQuoteYanksInsideEnclosingQuotes() {
        var session = EditorSession(
            document: EditorDocument(text: "let value = \"hello world\""),
            selection: .caret(at: 15)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("\""), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "hello world")
        #expect(session.document.buffer.text == "let value = \"hello world\"")
    }

    @Test("yi double quote works when the caret is on the closing quote")
    func yiDoubleQuoteYanksWhenCaretIsOnClosingQuote() {
        var session = EditorSession(
            document: EditorDocument(text: "let value = \"hello world\""),
            selection: .caret(at: 24)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("\""), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "hello world")
        #expect(session.document.buffer.text == "let value = \"hello world\"")
        #expect(session.selection == .caret(at: 13))
    }

    @Test("ca single quote works when the caret is on the closing quote")
    func caSingleQuoteChangesWhenCaretIsOnClosingQuote() {
        var session = EditorSession(
            document: EditorDocument(text: "let value = 'hello world'"),
            selection: .caret(at: 24)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("'"), session: &session).handled)

        #expect(controller.mode == .insert)
        #expect(controller.unnamedRegister == "'hello world'")
        #expect(session.document.buffer.text == "let value = ")
        #expect(session.selection == .caret(at: 12))
    }

    @Test("quote text object ignores escaped delimiters inside the string")
    func quoteTextObjectIgnoresEscapedDelimiters() {
        let text = "let value = \"hello \\\"world\\\" tail\""
        let offset = (text as NSString).range(of: "world").location
        var session = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: offset)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("\""), session: &session).handled)

        #expect(controller.mode == .normal)
        #expect(controller.unnamedRegister == "hello \\\"world\\\" tail")
        #expect(session.document.buffer.text == text)
        #expect(session.selection == .caret(at: 13))
    }

    @Test("ci double quote enters insert mode inside empty quotes")
    func ciDoubleQuoteEntersInsertModeInsideEmptyQuotes() {
        var session = EditorSession(
            document: EditorDocument(text: "let value = \"\""),
            selection: .caret(at: 12)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("\""), session: &session).handled)

        #expect(controller.mode == .insert)
        #expect(controller.unnamedRegister == "")
        #expect(session.document.buffer.text == "let value = \"\"")
        #expect(session.selection == .caret(at: 13))

        #expect(controller.handle(.text("hello"), session: &session).handled)
        #expect(session.document.buffer.text == "let value = \"hello\"")
    }

    @Test("dot repeats change inside an empty quote text object")
    func dotRepeatsChangeInsideEmptyQuoteTextObject() {
        let text = "first = \"\"\nsecond = \"\""
        var session = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: (text as NSString).range(of: "\"\"").location)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.text("x"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "first = \"x\"\nsecond = \"\"")

        let secondQuote = (session.document.buffer.text as NSString).range(of: "\"\"", options: [], range: NSRange(location: 12, length: 11)).location
        session.setSelection(.caret(at: secondQuote))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "first = \"x\"\nsecond = \"x\"")
        #expect(session.selection == .caret(at: secondQuote + 2))
    }

    @Test("ca paren changes the enclosing parentheses and enters insert mode")
    func caParenChangesEnclosingParenthesesAndEntersInsertMode() {
        var session = EditorSession(
            document: EditorDocument(text: "call(foo, bar) tail"),
            selection: .caret(at: 6)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("("), session: &session).handled)

        #expect(controller.mode == .insert)
        #expect(controller.unnamedRegister == "(foo, bar)")
        #expect(session.document.buffer.text == "call tail")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("ci paren enters insert mode inside empty parentheses")
    func ciParenEntersInsertModeInsideEmptyParentheses() {
        var session = EditorSession(
            document: EditorDocument(text: "call() tail"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("("), session: &session).handled)

        #expect(controller.mode == .insert)
        #expect(controller.unnamedRegister == "")
        #expect(session.document.buffer.text == "call() tail")
        #expect(session.selection == .caret(at: 5))

        #expect(controller.handle(.text("arg"), session: &session).handled)
        #expect(session.document.buffer.text == "call(arg) tail")
    }

    @Test("dot repeats change inside an empty paren text object")
    func dotRepeatsChangeInsideEmptyParenTextObject() {
        let text = "first()\nsecond()"
        var session = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: (text as NSString).range(of: "()").location)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("("), session: &session).handled)
        #expect(controller.handle(.text("x"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "first(x)\nsecond()")

        let secondParen = (session.document.buffer.text as NSString).range(
            of: "()",
            options: [],
            range: NSRange(location: 9, length: 8)
        ).location
        session.setSelection(.caret(at: secondParen))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "first(x)\nsecond(x)")
        #expect(session.selection == .caret(at: secondParen + 2))
    }

    @Test("named register yanks and pastes linewise text")
    func namedRegisterYanksAndPastesLinewiseText() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        #expect(controller.unnamedRegister == "two\n")

        session.setSelection(.caret(at: 10))
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\nthree\ntwo\n")
        #expect(session.selection == .caret(at: 14))
    }

    @Test("named register line delete can be pasted later")
    func namedRegisterLineDeleteCanBePastedLater() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("b"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(controller.unnamedRegister == "two\n")
        #expect(session.document.buffer.text == "one\nthree\n")

        session.setSelection(.caret(at: 4))
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("b"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\nthree\ntwo\n")
    }

    @Test("black hole register deletes and pastes without replacing unnamed text")
    func blackHoleRegisterDeletesAndPastesWithoutReplacingUnnamedText() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.unnamedRegister == "one\n")

        session.setSelection(.caret(at: 4))
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("_"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(session.document.buffer.text == "one\n")
        #expect(controller.unnamedRegister == "one\n")

        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("_"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)
        #expect(session.document.buffer.text == "one\n")
    }

    @Test("uppercase named register appends to its lowercase register")
    func uppercaseNamedRegisterAppendsToLowercaseRegister() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        session.setSelection(.caret(at: 4))
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("A"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        #expect(controller.unnamedRegister == "two\n")

        session.setSelection(.caret(at: 8))
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\nthree\none\ntwo\n")
    }

    @Test("register zero preserves the last line yank after later deletes")
    func registerZeroPreservesLastLineYankAfterDeletes() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        session.setSelection(.caret(at: 8))
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.unnamedRegister == "three\n")

        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("0"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\ntwo\n")
    }

    @Test("line deletes rotate through numbered registers one and two")
    func lineDeletesRotateThroughNumberedRegistersOneAndTwo() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)

        #expect(session.document.buffer.text == "one\nfour\n")
        #expect(controller.unnamedRegister == "three\n")

        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("1"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)
        #expect(controller.handle(.character("\""), session: &session).handled)
        #expect(controller.handle(.character("2"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\nfour\nthree\ntwo\n")
    }

    @Test("macro recording captures normal commands and replays them from the current caret")
    func macroRecordingCapturesNormalCommandsAndReplaysThem() {
        var session = EditorSession(
            document: EditorDocument(text: "abc\ndef\nghi\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("q"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("q"), session: &session).handled)

        #expect(session.document.buffer.text == "bc\ndef\nghi\n")
        #expect(session.selection == .caret(at: 3))

        #expect(controller.handle(.character("@"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        #expect(session.document.buffer.text == "bc\nef\nghi\n")
        #expect(session.selection == .caret(at: 6))
    }

    @Test("macro replay count repeats the recorded macro")
    func macroReplayCountRepeatsRecordedMacro() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("q"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(controller.handle(.character("q"), session: &session).handled)
        #expect(session.document.buffer.text == "bcd")

        session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 0)
        )
        #expect(controller.handle(.character("2"), session: &session).handled)
        #expect(controller.handle(.character("@"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        #expect(session.document.buffer.text == "cd")
        #expect(session.selection == .caret(at: 0))
    }

    @Test("@@ replays the last replayed macro")
    func atAtReplaysLastReplayedMacro() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("q"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(controller.handle(.character("q"), session: &session).handled)

        session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 0)
        )
        #expect(controller.handle(.character("@"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("@"), session: &session).handled)
        #expect(controller.handle(.character("@"), session: &session).handled)

        #expect(session.document.buffer.text == "cd")
        #expect(session.selection == .caret(at: 0))
    }

    @Test("local mark jumps with backtick restore the exact stored offset")
    func localMarkBacktickJumpsToExactStoredOffset() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 6)
        )
        var controller = VimController()

        #expect(controller.handle(.character("m"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("`"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        #expect(session.selection == .caret(at: 6))
        #expect(session.document.buffer.text == "one\ntwo\nthree\n")
    }

    @Test("local mark jumps with apostrophe land on the first nonblank of the marked line")
    func localMarkApostropheJumpsToFirstNonblankOnMarkedLine() {
        var session = EditorSession(
            document: EditorDocument(text: "root\n  child\nlast\n"),
            selection: .caret(at: 10)
        )
        var controller = VimController()

        #expect(controller.handle(.character("m"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("'"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        #expect(session.selection == .caret(at: 7))
        #expect(session.document.buffer.text == "root\n  child\nlast\n")
    }

    @Test("special backtick mark returns to the exact previous jump offset")
    func specialBacktickMarkReturnsToExactPreviousJumpOffset() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 6)
        )
        var controller = VimController()

        #expect(controller.handle(.character("m"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("`"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(session.selection == .caret(at: 6))

        #expect(controller.handle(.character("`"), session: &session).handled)
        #expect(controller.handle(.character("`"), session: &session).handled)
        #expect(session.selection == .caret(at: 0))
    }

    @Test("special apostrophe mark returns to first nonblank on the previous jump line")
    func specialApostropheMarkReturnsToPreviousJumpLine() {
        var session = EditorSession(
            document: EditorDocument(text: "root\n  child\nlast\n"),
            selection: .caret(at: 10)
        )
        var controller = VimController()

        #expect(controller.handle(.character("m"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("'"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(session.selection == .caret(at: 7))

        #expect(controller.handle(.character("'"), session: &session).handled)
        #expect(controller.handle(.character("'"), session: &session).handled)
        #expect(session.selection == .caret(at: 0))
    }

    @Test("visual yank stores start and end marks for apostrophe jumps")
    func visualYankStoresStartAndEndMarksForApostropheJumps() {
        let text = "root\n  child\n  leaf\nlast\n"
        let childOffset = (text as NSString).range(of: "child").location
        let leafOffset = (text as NSString).range(of: "leaf").location
        var session = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: childOffset)
        )
        var controller = VimController()

        #expect(controller.handle(.character("V"), session: &session).handled)
        #expect(controller.handle(.character("j"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("'"), session: &session).handled)
        #expect(controller.handle(.character("<"), session: &session).handled)
        #expect(session.selection == .caret(at: childOffset))

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("'"), session: &session).handled)
        #expect(controller.handle(.character(">"), session: &session).handled)
        #expect(session.selection == .caret(at: leafOffset))
    }

    @Test("uppercase marks jump within the same file-backed editor document")
    func uppercaseMarksJumpWithinTheSameFileBackedDocument() {
        let fileURL = URL(fileURLWithPath: "/tmp/cocxy-vim-mark-same.swift")
        var session = EditorSession(
            document: EditorDocument(fileURL: fileURL, text: "one\ntwo\nthree\n"),
            selection: .caret(at: 6)
        )
        var controller = VimController()

        #expect(controller.handle(.character("m"), session: &session).handled)
        #expect(controller.handle(.character("A"), session: &session).handled)

        session.setSelection(.caret(at: 0))
        #expect(controller.handle(.character("`"), session: &session).handled)
        #expect(controller.handle(.character("A"), session: &session).handled)

        #expect(session.selection == .caret(at: 6))
    }

    @Test("uppercase marks emit an open-file command across file-backed documents")
    func uppercaseMarksEmitOpenFileCommandAcrossDocuments() {
        let firstURL = URL(fileURLWithPath: "/tmp/cocxy-vim-mark-first.swift")
        var firstSession = EditorSession(
            document: EditorDocument(fileURL: firstURL, text: "one\ntwo\nthree\n"),
            selection: .caret(at: 6)
        )
        var controller = VimController()

        #expect(controller.handle(.character("m"), session: &firstSession).handled)
        #expect(controller.handle(.character("A"), session: &firstSession).handled)

        let secondURL = URL(fileURLWithPath: "/tmp/cocxy-vim-mark-second.swift")
        var secondSession = EditorSession(
            document: EditorDocument(fileURL: secondURL, text: "alpha\nbeta\n"),
            selection: .caret(at: 0)
        )

        #expect(controller.handle(.character("`"), session: &secondSession).handled)
        let result = controller.handle(.character("A"), session: &secondSession)

        #expect(result.handled)
        #expect(result.fileCommand == .openFileAtMark(url: firstURL, offset: 6, lineWise: false))
        #expect(secondSession.selection == .caret(at: 0))
        #expect(secondSession.document.fileURL == secondURL)
    }

    @Test("line yanks paste after the current line")
    func lineYanksPasteAfterCurrentLine() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.unnamedRegister == "two\n")

        session.setSelection(.caret(at: 10))
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\nthree\ntwo\n")
        #expect(session.selection == .caret(at: 14))
    }

    @Test("line yanks paste before the current line with uppercase P")
    func lineYanksPasteBeforeCurrentLineWithUppercaseP() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.unnamedRegister == "two\n")

        session.setSelection(.caret(at: 8))
        #expect(controller.handle(.character("P"), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\ntwo\nthree\n")
        #expect(session.selection == .caret(at: 8))
    }

    @Test("character delete pastes after the current character with p")
    func characterDeletePastesAfterCurrentCharacterWithP() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(session.document.buffer.text == "acd")
        #expect(controller.unnamedRegister == "b")

        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "acbd")
        #expect(session.selection == .caret(at: 2))
    }

    @Test("character delete pastes before the current character with P")
    func characterDeletePastesBeforeCurrentCharacterWithP() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(session.document.buffer.text == "acd")
        #expect(controller.unnamedRegister == "b")

        #expect(controller.handle(.character("P"), session: &session).handled)

        #expect(session.document.buffer.text == "abcd")
        #expect(session.selection == .caret(at: 1))
    }

    @Test("dot repeats the last characterwise paste")
    func dotRepeatsLastCharacterwisePaste() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)
        #expect(session.document.buffer.text == "acbd")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "acbbd")
        #expect(session.selection == .caret(at: 3))
    }

    @Test("dot repeats the last character delete")
    func dotRepeatsLastCharacterDelete() {
        var session = EditorSession(
            document: EditorDocument(text: "abcd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("x"), session: &session).handled)
        #expect(session.document.buffer.text == "acd")
        #expect(controller.unnamedRegister == "b")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "ad")
        #expect(session.selection == .caret(at: 1))
        #expect(controller.unnamedRegister == "c")
    }

    @Test("dot repeats the last line delete at the current line")
    func dotRepeatsLastLineDeleteAtCurrentLine() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(session.document.buffer.text == "one\nthree\nfour\n")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "one\nfour\n")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "three\n")
    }

    @Test("dot repeats the last delete motion at the current caret")
    func dotRepeatsLastDeleteMotionAtCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three four"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)
        #expect(session.document.buffer.text == "one three four")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "one four")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "three ")
    }

    @Test("dot repeats the last delete text object at the current caret")
    func dotRepeatsLastDeleteTextObjectAtCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three four"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("d"), session: &session).handled)
        #expect(controller.handle(.character("a"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)
        #expect(session.document.buffer.text == "one three four")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "one four")
        #expect(session.selection == .caret(at: 4))
        #expect(controller.unnamedRegister == "three ")
    }

    @Test("dot repeats the last simple insert at the current caret")
    func dotRepeatsLastSimpleInsertAtCurrentCaret() {
        var session = EditorSession(
            document: EditorDocument(text: "ab\ncd"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.text("X"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "aXb\ncd")

        session.setSelection(.caret(at: 4))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "aXb\nXcd")
        #expect(session.selection == .caret(at: 5))
    }

    @Test("dot repeats the last change text object with inserted text")
    func dotRepeatsLastChangeTextObjectWithInsertedText() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("i"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)
        #expect(controller.handle(.text("alpha"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "alpha two three")

        session.setSelection(.caret(at: 6))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "alpha alpha three")
        #expect(session.selection == .caret(at: 11))
    }

    @Test("dot repeats the last change motion with inserted text")
    func dotRepeatsLastChangeMotionWithInsertedText() {
        var session = EditorSession(
            document: EditorDocument(text: "one two three"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("c"), session: &session).handled)
        #expect(controller.handle(.character("w"), session: &session).handled)
        #expect(controller.handle(.text("X"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "X two three")

        session.setSelection(.caret(at: 2))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "X X three")
        #expect(session.selection == .caret(at: 3))
    }

    @Test("system clipboard register writes yanks and reads pastes through injected access")
    func systemClipboardRegisterWritesYanksAndReadsPastesThroughInjectedAccess() {
        var systemRegisters: [VimSystemRegister: String] = [:]
        let access = VimSystemRegisterAccess(
            read: { systemRegisters[$0] },
            write: { text, register in systemRegisters[register] = text }
        )
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\n"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\""), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("+"), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("y"), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("y"), session: &session, systemRegisters: access).handled)

        #expect(systemRegisters[.clipboard] == "one\n")
        #expect(systemRegisters[.primarySelection] == nil)
        #expect(controller.unnamedRegister == "one\n")

        systemRegisters[.clipboard] = "clip\n"
        #expect(controller.handle(.character("\""), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("+"), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("p"), session: &session, systemRegisters: access).handled)

        #expect(session.document.buffer.text == "one\nclip\ntwo\n")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("primary selection register is separate from the system clipboard register")
    func primarySelectionRegisterIsSeparateFromSystemClipboardRegister() {
        var systemRegisters: [VimSystemRegister: String] = [.clipboard: "clipboard\n"]
        let access = VimSystemRegisterAccess(
            read: { systemRegisters[$0] },
            write: { text, register in systemRegisters[register] = text }
        )
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("\""), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("*"), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("y"), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("y"), session: &session, systemRegisters: access).handled)

        #expect(systemRegisters[.clipboard] == "clipboard\n")
        #expect(systemRegisters[.primarySelection] == "two\n")

        session.setSelection(.caret(at: 0))
        systemRegisters[.primarySelection] = "primary\n"
        #expect(controller.handle(.character("\""), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("*"), session: &session, systemRegisters: access).handled)
        #expect(controller.handle(.character("p"), session: &session, systemRegisters: access).handled)

        #expect(session.document.buffer.text == "one\nprimary\ntwo\n")
    }

    @Test("count before p repeats linewise paste")
    func countBeforePRepeatsLinewisePaste() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("y"), session: &session).handled)
        #expect(controller.handle(.character("3"), session: &session).handled)
        #expect(controller.handle(.character("p"), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\ntwo\ntwo\ntwo\nthree\n")
        #expect(session.selection == .caret(at: 8))
    }

    @Test("open line commands create an empty insert line without leaving normal mode text behind")
    func openLineCommandsCreateEmptyInsertLines() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo"),
            selection: .caret(at: 0)
        )
        var controller = VimController()

        #expect(controller.handle(.character("o"), session: &session).handled)
        #expect(controller.mode == .insert)
        #expect(session.document.buffer.text == "one\n\ntwo")
        #expect(session.selection == .caret(at: 4))

        #expect(controller.handle(.escape, session: &session).handled)
        #expect(controller.handle(.character("O"), session: &session).handled)
        #expect(session.document.buffer.text == "one\n\n\ntwo")
        #expect(session.selection == .caret(at: 4))
    }

    @Test("dot repeats open line below with inserted text")
    func dotRepeatsOpenLineBelowWithInsertedText() {
        var session = EditorSession(
            document: EditorDocument(text: "one\nthree\n"),
            selection: .caret(at: 1)
        )
        var controller = VimController()

        #expect(controller.handle(.character("o"), session: &session).handled)
        #expect(controller.handle(.text("two"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "one\ntwo\nthree\n")

        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\ntwo\nthree\n")
    }

    @Test("dot repeats open line above with inserted text")
    func dotRepeatsOpenLineAboveWithInsertedText() {
        var session = EditorSession(
            document: EditorDocument(text: "one\nthree\n"),
            selection: .caret(at: 5)
        )
        var controller = VimController()

        #expect(controller.handle(.character("O"), session: &session).handled)
        #expect(controller.handle(.text("two"), session: &session).handled)
        #expect(controller.handle(.escape, session: &session).handled)
        #expect(session.document.buffer.text == "one\ntwo\nthree\n")

        session.setSelection(.caret(at: 12))
        #expect(controller.handle(.character("."), session: &session).handled)

        #expect(session.document.buffer.text == "one\ntwo\ntwo\nthree\n")
    }

    @Test("gg and G jump to document boundaries")
    func ggAndGJumpToDocumentBoundaries() {
        var session = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree"),
            selection: .caret(at: 4)
        )
        var controller = VimController()

        #expect(controller.handle(.character("G"), session: &session).handled)
        #expect(session.selection == .caret(at: 8))

        #expect(controller.handle(.character("g"), session: &session).handled)
        #expect(controller.handle(.character("g"), session: &session).handled)
        #expect(session.selection == .caret(at: 0))
    }

    @Test("operators with G and gg use linewise ranges")
    func operatorsWithGAndGgUseLinewiseRanges() {
        var deleteSession = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\nfour\n"),
            selection: .caret(at: 4)
        )
        var deleteController = VimController()

        #expect(deleteController.handle(.character("d"), session: &deleteSession).handled)
        #expect(deleteController.handle(.character("G"), session: &deleteSession).handled)

        #expect(deleteSession.document.buffer.text == "one\n")
        #expect(deleteController.unnamedRegister == "two\nthree\nfour\n")
        #expect(deleteSession.selection == .caret(at: 4))

        var yankSession = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 8)
        )
        var yankController = VimController()

        #expect(yankController.handle(.character("y"), session: &yankSession).handled)
        #expect(yankController.handle(.character("g"), session: &yankSession).handled)
        #expect(yankController.handle(.character("g"), session: &yankSession).handled)

        #expect(yankSession.document.buffer.text == "one\ntwo\nthree\n")
        #expect(yankController.unnamedRegister == "one\ntwo\nthree\n")
        #expect(yankSession.selection == .caret(at: 0))

        var changeSession = EditorSession(
            document: EditorDocument(text: "one\ntwo\nthree\n"),
            selection: .caret(at: 8)
        )
        var changeController = VimController()

        #expect(changeController.handle(.character("c"), session: &changeSession).handled)
        #expect(changeController.handle(.character("g"), session: &changeSession).handled)
        #expect(changeController.handle(.character("g"), session: &changeSession).handled)

        #expect(changeController.mode == .insert)
        #expect(changeSession.document.buffer.text == "")
        #expect(changeController.unnamedRegister == "one\ntwo\nthree\n")
        #expect(changeSession.selection == .caret(at: 0))
    }

    @Test("operators with brace block motions use linewise ranges")
    func operatorsWithBraceBlockMotionsUseLinewiseRanges() {
        let text = "func outer() {\n  if ready {\n    call()\n  }\n  done()\n}\nafter\n"
        let callOffset = (text as NSString).range(of: "call").location
        var deleteSession = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: callOffset)
        )
        var deleteController = VimController()

        #expect(deleteController.handle(.character("d"), session: &deleteSession).handled)
        #expect(deleteController.handle(.character("]"), session: &deleteSession).handled)
        #expect(deleteController.handle(.character("}"), session: &deleteSession).handled)

        #expect(deleteSession.document.buffer.text == "func outer() {\n  if ready {\n  done()\n}\nafter\n")
        #expect(deleteController.unnamedRegister == "    call()\n  }\n")
        #expect(deleteSession.selection == .caret(at: (text as NSString).range(of: "    call()").location))

        var yankSession = EditorSession(
            document: EditorDocument(text: text),
            selection: .caret(at: callOffset)
        )
        var yankController = VimController()

        #expect(yankController.handle(.character("y"), session: &yankSession).handled)
        #expect(yankController.handle(.character("["), session: &yankSession).handled)
        #expect(yankController.handle(.character("{"), session: &yankSession).handled)

        #expect(yankSession.document.buffer.text == text)
        #expect(yankController.unnamedRegister == "  if ready {\n    call()\n")
        #expect(yankSession.selection == .caret(at: (text as NSString).range(of: "  if ready").location))
    }
}
