// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CJK Korean IME", .serialized)
@MainActor
struct CJKKoreanIMESwiftTestingTests {

    @Test("jamo marked text tracks initial consonant")
    func jamoMarkedTextTracksInitialConsonant() {
        var state = TextCompositionState()

        state.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0))

        #expect(state.hasMarkedText == true)
        #expect(state.markedText == "ㄴ")
        #expect(state.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("jamo composition updates to a Hangul syllable")
    func jamoCompositionUpdatesToHangulSyllable() {
        var state = TextCompositionState()

        state.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0))
        state.setMarkedText("나", selectedRange: NSRange(location: 1, length: 0))

        #expect(state.markedText == "나")
        #expect(state.markedRange == NSRange(location: 0, length: 1))
        #expect(state.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("Hangul word marked range counts composed syllables")
    func hangulWordMarkedRangeCountsComposedSyllables() {
        var state = TextCompositionState()

        state.setMarkedText("한글", selectedRange: NSRange(location: 2, length: 0))

        #expect(state.markedText == "한글")
        #expect(state.markedRange == NSRange(location: 0, length: 2))
    }

    @Test("terminal preedit accepts Hangul syllables")
    func terminalPreeditAcceptsHangulSyllables() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "한글",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(cocxycore_terminal_preedit_active(state.terminal) == true)
        #expect(readPreedit(from: state.terminal) == "한글")
        #expect(harness.view.markedRange() == NSRange(location: 0, length: 2))
    }

    @Test("committing Hangul clears marked state and sends text")
    func committingHangulClearsMarkedStateAndSendsText() async throws {
        let harness = try makeIMEViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.setMarkedText(
            "ㅎ",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.insertText("하\n", replacementRange: NSRange(location: NSNotFound, length: 0))

        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("하") == true
        }
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }
}
