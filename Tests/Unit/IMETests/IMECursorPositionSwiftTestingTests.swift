// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("IME cursor position", .serialized)
@MainActor
struct IMECursorPositionSwiftTestingTests {

    @Test("cursor rect remains usable after Chinese commit")
    func cursorRectRemainsUsableAfterChineseCommit() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        harness.view.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))

        let rect = harness.view.firstRect(
            forCharacterRange: NSRange(location: 0, length: 0),
            actualRange: nil
        )
        #expect(rect.width > 0)
        #expect(rect.height > 0)
    }

    @Test("marked range resets after Japanese commit")
    func markedRangeResetsAfterJapaneseCommit() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.insertText("仮名", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(harness.view.markedRange() == NSRange(location: NSNotFound, length: 0))
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }
}
