// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VimSmokeGateSwiftTestingTests.swift - Programmatic smoke gate for common Vim commands.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Vim smoke gate")
struct VimSmokeGateSwiftTestingTests {
    @Test("55 common Vim commands stay wired")
    func fiftyFiveCommonVimCommandsStayWired() {
        var commandCount = 0

        func smoke(_ name: String, _ body: () -> Void) {
            commandCount += 1
            body()
        }

        smoke("i inserts text") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("i", controller: &controller, session: &session).handled)
            #expect(type("X", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "aXbc")
            #expect(controller.mode == .insert)
        }

        smoke("a appends text after the caret") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("a", controller: &controller, session: &session).handled)
            #expect(type("X", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "aXbc")
        }

        smoke("o opens a line below") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("o", controller: &controller, session: &session).handled)
            #expect(type("two", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "one\ntwo")
        }

        smoke("O opens a line above") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("O", controller: &controller, session: &session).handled)
            #expect(type("zero", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "zero\none")
        }

        smoke("h moves left") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 2))
            var controller = VimController()
            #expect(press("h", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 1))
        }

        smoke("l moves right") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("l", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 2))
        }

        smoke("0 moves to line start") {
            var session = EditorSession(document: EditorDocument(text: "abc\ndef"), selection: .caret(at: 6))
            var controller = VimController()
            #expect(press("0", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 4))
        }

        smoke("$ moves to line end") {
            var session = EditorSession(document: EditorDocument(text: "abc\ndef"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("$", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 6))
        }

        smoke("w moves to next word") {
            var session = EditorSession(document: EditorDocument(text: "one two"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("w", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 4))
        }

        smoke("b moves to previous word") {
            var session = EditorSession(document: EditorDocument(text: "one two"), selection: .caret(at: 6))
            var controller = VimController()
            #expect(press("b", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 4))
        }

        smoke("j moves down") {
            var session = EditorSession(document: EditorDocument(text: "ab\ncd"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("j", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 4))
        }

        smoke("k moves up") {
            var session = EditorSession(document: EditorDocument(text: "ab\ncd"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("k", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 1))
        }

        smoke("gg moves to document start") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo"), selection: .caret(at: 5))
            var controller = VimController()
            #expect(press("g", controller: &controller, session: &session).handled)
            #expect(press("g", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 0))
        }

        smoke("G moves to last line") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("G", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 4))
        }

        smoke("% jumps to matching delimiter") {
            var session = EditorSession(document: EditorDocument(text: "func(a[bc])"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("%", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 10))
        }

        smoke("[{ jumps to containing brace") {
            let text = "{\n  call()\n}\n"
            let callOffset = (text as NSString).range(of: "call").location
            var session = EditorSession(document: EditorDocument(text: text), selection: .caret(at: callOffset))
            var controller = VimController()
            #expect(press("[", controller: &controller, session: &session).handled)
            #expect(press("{", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 0))
        }

        smoke("]} jumps to closing brace") {
            let text = "{\n  call()\n}\n"
            let callOffset = (text as NSString).range(of: "call").location
            let closeOffset = (text as NSString).range(of: "}").location
            var session = EditorSession(document: EditorDocument(text: text), selection: .caret(at: callOffset))
            var controller = VimController()
            #expect(press("]", controller: &controller, session: &session).handled)
            #expect(press("}", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: closeOffset))
        }

        smoke("x deletes a character") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("x", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "ac")
        }

        smoke("dd deletes one line") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "two\n")
        }

        smoke("3dd deletes three lines") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\nthree\nfour\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("3", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "four\n")
        }

        smoke("dw deletes to the next word") {
            var session = EditorSession(document: EditorDocument(text: "one two"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("w", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "two")
        }

        smoke("yy followed by p pastes a yanked line") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(press("p", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "one\none\ntwo\n")
        }

        smoke("yy3p pastes a yanked line three times") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(press("3", controller: &controller, session: &session).handled)
            #expect(press("p", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "one\none\none\none\ntwo\n")
        }

        smoke("black-hole register deletes without replacing unnamed") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            session.setSelection(.caret(at: 4))
            #expect(press("\"", controller: &controller, session: &session).handled)
            #expect(press("_", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "one\n")
            #expect(controller.unnamedRegister == "one\n")
        }

        smoke("ciw changes a word") {
            var session = EditorSession(document: EditorDocument(text: "one two"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("c", controller: &controller, session: &session).handled)
            #expect(press("i", controller: &controller, session: &session).handled)
            #expect(press("w", controller: &controller, session: &session).handled)
            #expect(type("three", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "one three")
        }

        smoke("daw deletes around a word") {
            var session = EditorSession(document: EditorDocument(text: "one two three"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("a", controller: &controller, session: &session).handled)
            #expect(press("w", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "one three")
        }

        smoke("dip deletes inner paragraph") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\n\nthree\n"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("i", controller: &controller, session: &session).handled)
            #expect(press("p", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "\nthree\n")
        }

        smoke("dap deletes around paragraph") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\n\nthree\n"), selection: .caret(at: 4))
            var controller = VimController()
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(press("a", controller: &controller, session: &session).handled)
            #expect(press("p", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "three\n")
        }

        smoke("yi double quote yanks quoted contents") {
            var session = EditorSession(document: EditorDocument(text: "let x = \"value\""), selection: .caret(at: 10))
            var controller = VimController()
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(press("i", controller: &controller, session: &session).handled)
            #expect(press("\"", controller: &controller, session: &session).handled)
            #expect(controller.unnamedRegister == "value")
        }

        smoke("ca single quote changes quoted contents") {
            var session = EditorSession(document: EditorDocument(text: "let x = 'old'"), selection: .caret(at: 9))
            var controller = VimController()
            #expect(press("c", controller: &controller, session: &session).handled)
            #expect(press("a", controller: &controller, session: &session).handled)
            #expect(press("'", controller: &controller, session: &session).handled)
            #expect(type("new", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "let x = new")
        }

        smoke("dot repeats x") {
            var session = EditorSession(document: EditorDocument(text: "abcd"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("x", controller: &controller, session: &session).handled)
            #expect(press(".", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "ad")
        }

        smoke("dot repeats ciw with inserted text") {
            var session = EditorSession(document: EditorDocument(text: "one two"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("c", controller: &controller, session: &session).handled)
            #expect(press("i", controller: &controller, session: &session).handled)
            #expect(press("w", controller: &controller, session: &session).handled)
            #expect(type("1", controller: &controller, session: &session).handled)
            #expect(escape(controller: &controller, session: &session).handled)
            session.setSelection(.caret(at: 4))
            #expect(press(".", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "1 1")
        }

        smoke("u emits undo") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("u", controller: &controller, session: &session).editCommand == .undo)
        }

        smoke("control-r emits redo") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("\u{12}", controller: &controller, session: &session).editCommand == .redo)
        }

        smoke("visual y yanks selected text") {
            var session = EditorSession(document: EditorDocument(text: "abcd"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("v", controller: &controller, session: &session).handled)
            #expect(press("l", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(controller.unnamedRegister == "bc")
        }

        smoke("visual d deletes selected text") {
            var session = EditorSession(document: EditorDocument(text: "abcd"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("v", controller: &controller, session: &session).handled)
            #expect(press("l", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "ad")
        }

        smoke("visual line y yanks lines") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\nthree\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("V", controller: &controller, session: &session).handled)
            #expect(press("j", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(controller.unnamedRegister == "one\ntwo\n")
        }

        smoke("visual marks jump to the last visual selection") {
            let text = "one\n  two\n  three\n"
            let twoOffset = (text as NSString).range(of: "two").location
            let threeOffset = (text as NSString).range(of: "three").location
            var session = EditorSession(document: EditorDocument(text: text), selection: .caret(at: twoOffset))
            var controller = VimController()
            #expect(press("V", controller: &controller, session: &session).handled)
            #expect(press("j", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            session.setSelection(.caret(at: 0))
            #expect(press("'", controller: &controller, session: &session).handled)
            #expect(press(">", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: threeOffset))
        }

        smoke("visual line d deletes lines") {
            var session = EditorSession(document: EditorDocument(text: "one\ntwo\nthree\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(press("V", controller: &controller, session: &session).handled)
            #expect(press("j", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "three\n")
        }

        smoke("visual block y yanks columns") {
            var session = EditorSession(document: EditorDocument(text: "abcd\nefgh"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("\u{16}", controller: &controller, session: &session).handled)
            #expect(press("j", controller: &controller, session: &session).handled)
            #expect(press("l", controller: &controller, session: &session).handled)
            #expect(press("y", controller: &controller, session: &session).handled)
            #expect(controller.unnamedRegister == "bc\nfg")
        }

        smoke("visual block d deletes columns") {
            var session = EditorSession(document: EditorDocument(text: "abcd\nefgh"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("\u{16}", controller: &controller, session: &session).handled)
            #expect(press("j", controller: &controller, session: &session).handled)
            #expect(press("l", controller: &controller, session: &session).handled)
            #expect(press("d", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "ad\neh")
        }

        smoke("R overwrites text") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("R", controller: &controller, session: &session).handled)
            #expect(type("X", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "aXc")
        }

        smoke("r replaces one character") {
            var session = EditorSession(document: EditorDocument(text: "abc"), selection: .caret(at: 1))
            var controller = VimController()
            #expect(press("r", controller: &controller, session: &session).handled)
            #expect(press("X", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "aXc")
        }

        smoke("/ searches forward") {
            var session = EditorSession(document: EditorDocument(text: "one two one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(search("/", "one", controller: &controller, session: &session).searchHighlightQuery == "one")
            #expect(session.selection == .caret(at: 8))
        }

        smoke("? searches backward") {
            var session = EditorSession(document: EditorDocument(text: "one two one"), selection: .caret(at: 11))
            var controller = VimController()
            #expect(search("?", "one", controller: &controller, session: &session).searchHighlightQuery == "one")
            #expect(session.selection == .caret(at: 8))
        }

        smoke("n repeats search direction") {
            var session = EditorSession(document: EditorDocument(text: "one two one"), selection: .caret(at: 0))
            var controller = VimController()
            _ = search("/", "one", controller: &controller, session: &session)
            #expect(press("n", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 0))
        }

        smoke("N reverses search direction") {
            var session = EditorSession(document: EditorDocument(text: "one two one"), selection: .caret(at: 0))
            var controller = VimController()
            _ = search("/", "one", controller: &controller, session: &session)
            #expect(press("N", controller: &controller, session: &session).handled)
            #expect(session.selection == .caret(at: 0))
        }

        smoke(":s substitutes first match on current line") {
            var session = EditorSession(document: EditorDocument(text: "one one\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("s/one/two/", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "two one\n")
        }

        smoke(":s g substitutes all matches on current line") {
            var session = EditorSession(document: EditorDocument(text: "one one\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("s/one/two/g", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "two two\n")
        }

        smoke(":%s substitutes all matches in the document") {
            var session = EditorSession(document: EditorDocument(text: "one\none\n"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("%s/one/two/g", controller: &controller, session: &session).handled)
            #expect(session.document.buffer.text == "two\ntwo\n")
        }

        smoke(":w emits write") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("w", controller: &controller, session: &session).exCommand == .write)
        }

        smoke(":q emits quit") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("q", controller: &controller, session: &session).exCommand == .quit)
        }

        smoke(":wq emits write quit") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("wq", controller: &controller, session: &session).exCommand == .writeQuit)
        }

        smoke(":nohl emits clear highlights") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("nohl", controller: &controller, session: &session).exCommand == .clearSearchHighlights)
        }

        smoke(":set wrap? emits wrap status") {
            var session = EditorSession(document: EditorDocument(text: "one"), selection: .caret(at: 0))
            var controller = VimController()
            #expect(ex("set wrap?", controller: &controller, session: &session).exCommand == .reportSoftWrap)
        }

        #expect(commandCount == 55)
    }

    @discardableResult
    private func press(
        _ character: String,
        controller: inout VimController,
        session: inout EditorSession
    ) -> VimHandleResult {
        controller.handle(.character(character), session: &session)
    }

    @discardableResult
    private func type(
        _ text: String,
        controller: inout VimController,
        session: inout EditorSession
    ) -> VimHandleResult {
        controller.handle(.text(text), session: &session)
    }

    @discardableResult
    private func escape(
        controller: inout VimController,
        session: inout EditorSession
    ) -> VimHandleResult {
        controller.handle(.escape, session: &session)
    }

    @discardableResult
    private func search(
        _ prefix: String,
        _ query: String,
        controller: inout VimController,
        session: inout EditorSession
    ) -> VimHandleResult {
        _ = press(prefix, controller: &controller, session: &session)
        for character in query {
            _ = press(String(character), controller: &controller, session: &session)
        }
        return controller.handle(.enter, session: &session)
    }

    @discardableResult
    private func ex(
        _ command: String,
        controller: inout VimController,
        session: inout EditorSession
    ) -> VimHandleResult {
        _ = press(":", controller: &controller, session: &session)
        for character in command {
            _ = press(String(character), controller: &controller, session: &session)
        }
        return controller.handle(.enter, session: &session)
    }
}
