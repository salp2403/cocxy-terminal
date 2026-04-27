// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `BrowserDOMGrabPayloadInjection.wrap`, the pure
/// helper that decides whether a formatted DOM-grab payload should be
/// surrounded by the bracketed-paste markers (`CSI 200~ ... CSI 201~`)
/// before it reaches `CocxyCoreBridge.sendText`.
///
/// The contract mirrors the canonical paste path in
/// `CocxyCoreView.handlePaste`:
///   * When the underlying terminal has bracketed paste mode active —
///     every modern shell, every AI-agent CLI prompter — the markers
///     wrap the payload so multiline blocks survive a shell focus
///     without being interpreted as separate commands.
///   * When the mode is inactive — recently launched shell, TUIs that
///     opt out, edge cases — the helper returns the payload untouched
///     so the markers do not surface as visible escape sequences in
///     the terminal.
///
/// Without this guard the previous implementation always wrapped, and
/// the markers leaked as raw `[200~` / `[201~` characters to the user
/// in the inactive case.
@Suite("BrowserDOMGrabPayloadInjection.wrap")
struct BrowserDOMGrabPayloadInjectionSwiftTestingTests {

    // MARK: - Bracketed paste active

    @Test("bracketed paste mode active produces a CSI 200~ ... CSI 201~ wrapped payload")
    func activeModeWrapsWithBracketedPasteMarkers() {
        let formatted = "--- Browser DOM grab ---\nPage: Example\n---\n"

        let result = BrowserDOMGrabPayloadInjection.wrap(
            formatted,
            bracketedPasteActive: true
        )

        #expect(result == "\u{1B}[200~--- Browser DOM grab ---\nPage: Example\n---\n\u{1B}[201~")
    }

    @Test("active mode wraps even an empty payload because the receiving prompter still expects markers")
    func activeModeWrapsEvenEmptyPayload() {
        let result = BrowserDOMGrabPayloadInjection.wrap(
            "",
            bracketedPasteActive: true
        )

        #expect(result == "\u{1B}[200~\u{1B}[201~")
    }

    // MARK: - Bracketed paste inactive

    @Test("bracketed paste mode inactive returns the payload untouched so markers do not leak as visible characters")
    func inactiveModeReturnsPayloadUntouched() {
        let formatted = "--- Browser DOM grab ---\nPage: Example\n---\n"

        let result = BrowserDOMGrabPayloadInjection.wrap(
            formatted,
            bracketedPasteActive: false
        )

        #expect(result == formatted)
    }

    @Test("inactive mode passes empty input through as the empty string")
    func inactiveModeEmptyInputStaysEmpty() {
        let result = BrowserDOMGrabPayloadInjection.wrap(
            "",
            bracketedPasteActive: false
        )

        #expect(result == "")
    }

    // MARK: - Edge: payload that already starts with the marker

    @Test("active mode does not strip a literal CSI 200~ that was already part of the payload — wrapping is a single, mechanical operation")
    func activeModeWrapsPayloadEvenIfItContainsMarkers() {
        // The helper is a pure wrap. It does not de-duplicate. If the
        // payload itself happens to contain marker-like bytes — only
        // possible when the content embedded an escape sequence from
        // somewhere upstream — the wrap is still a single layer added
        // around it. This pins the contract so future readers do not
        // assume "smart" stripping behaviour.
        let formatted = "\u{1B}[200~prefix\u{1B}[201~"

        let result = BrowserDOMGrabPayloadInjection.wrap(
            formatted,
            bracketedPasteActive: true
        )

        #expect(result == "\u{1B}[200~\u{1B}[200~prefix\u{1B}[201~\u{1B}[201~")
    }
}
