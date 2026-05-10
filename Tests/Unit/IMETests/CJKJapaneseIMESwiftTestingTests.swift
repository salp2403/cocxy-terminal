// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CJK Japanese IME", .serialized)
@MainActor
struct CJKJapaneseIMESwiftTestingTests {

    @Test("romaji marked text tracks the draft")
    func romajiMarkedTextTracksTheDraft() {
        var state = TextCompositionState()

        state.setMarkedText("konnichiha", selectedRange: NSRange(location: 10, length: 0))

        #expect(state.hasMarkedText == true)
        #expect(state.markedText == "konnichiha")
        #expect(state.markedRange == NSRange(location: 0, length: 10))
    }

    @Test("hiragana marked text tracks conversion")
    func hiraganaMarkedTextTracksConversion() {
        var state = TextCompositionState()

        state.setMarkedText("こんにちは", selectedRange: NSRange(location: 5, length: 0))

        #expect(state.markedText == "こんにちは")
        #expect(state.markedRange == NSRange(location: 0, length: 5))
        #expect(state.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test("kanji conversion selection is retained")
    func kanjiConversionSelectionIsRetained() {
        var state = TextCompositionState()

        state.setMarkedText("今日は", selectedRange: NSRange(location: 0, length: 2))

        #expect(state.markedText == "今日は")
        #expect(state.markedRange == NSRange(location: 0, length: 3))
        #expect(state.selectedRange == NSRange(location: 0, length: 2))
    }

    @Test("terminal preedit updates from kana to kanji")
    func terminalPreeditUpdatesFromKanaToKanji() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "こんにちは",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.setMarkedText(
            "今日は",
            selectedRange: NSRange(location: 0, length: 2),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(cocxycore_terminal_preedit_active(state.terminal) == true)
        #expect(readPreedit(from: state.terminal) == "今日は")
        #expect(harness.view.markedRange() == NSRange(location: 0, length: 3))
    }

    @Test("committing kanji clears marked state and sends text")
    func committingKanjiClearsMarkedStateAndSendsText() async throws {
        let harness = try makeIMEViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.setMarkedText(
            "こんにちは",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.insertText("今日は\n", replacementRange: NSRange(location: NSNotFound, length: 0))

        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("今日は") == true
        }
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }

    @Test("marked attributes support Japanese underline feedback")
    func markedAttributesSupportJapaneseUnderlineFeedback() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        harness.view.setMarkedText(
            NSAttributedString(string: "候補"),
            selectedRange: NSRange(location: 0, length: 2),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(harness.view.hasMarkedText() == true)
        #expect(harness.view.validAttributesForMarkedText().contains(.underlineStyle))
        #expect(harness.view.validAttributesForMarkedText().contains(.foregroundColor))
    }
}
