// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("IME cancel and commit", .serialized)
@MainActor
struct IMECancelCommitSwiftTestingTests {

    @Test("unmark cancels Chinese composition state")
    func unmarkCancelsChineseCompositionState() {
        var state = TextCompositionState()

        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.unmarkText()

        #expect(state.hasMarkedText == false)
        #expect(state.markedText.isEmpty)
        #expect(state.markedRange == NSRange(location: NSNotFound, length: 0))
    }

    @Test("view unmark clears Japanese preedit")
    func viewUnmarkClearsJapanesePreedit() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.unmarkText()

        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
        #expect(readPreedit(from: state.terminal).isEmpty)
    }

    @Test("insertText commits Korean composition and clears preedit")
    func insertTextCommitsKoreanCompositionAndClearsPreedit() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "ㅎ",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.insertText("하", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
        #expect(readPreedit(from: state.terminal).isEmpty)
    }
}
