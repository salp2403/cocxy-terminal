// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("IME marked selection", .serialized)
@MainActor
struct IMEMarkedSelectionSwiftTestingTests {

    @Test("Chinese candidate selection range is retained")
    func chineseCandidateSelectionRangeIsRetained() {
        var state = TextCompositionState()

        state.setMarkedText("中文", selectedRange: NSRange(location: 0, length: 1))

        #expect(state.markedRange == NSRange(location: 0, length: 2))
        #expect(state.selectedRange == NSRange(location: 0, length: 1))
    }

    @Test("Japanese conversion selection range is retained")
    func japaneseConversionSelectionRangeIsRetained() {
        var state = TextCompositionState()

        state.setMarkedText("変換候補", selectedRange: NSRange(location: 0, length: 2))

        #expect(state.markedRange == NSRange(location: 0, length: 4))
        #expect(state.selectedRange == NSRange(location: 0, length: 2))
    }

    @Test("Korean composition caret range is retained")
    func koreanCompositionCaretRangeIsRetained() {
        var state = TextCompositionState()

        state.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0))

        #expect(state.markedRange == NSRange(location: 0, length: 1))
        #expect(state.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("view marked range follows current CJK preedit length")
    func viewMarkedRangeFollowsCurrentCJKPreeditLength() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        harness.view.setMarkedText(
            "候補",
            selectedRange: NSRange(location: 0, length: 2),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(harness.view.hasMarkedText() == true)
        #expect(harness.view.markedRange() == NSRange(location: 0, length: 2))
    }
}
