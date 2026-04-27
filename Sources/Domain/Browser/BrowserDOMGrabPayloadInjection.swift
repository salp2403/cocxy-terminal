// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDOMGrabPayloadInjection.swift - Pure helper that decides
// whether a formatted DOM-grab payload should be wrapped with the
// terminal's bracketed-paste markers before reaching the bridge.

import Foundation

/// Pure helper that turns the formatted DOM-grab payload into the exact
/// byte sequence the surface lifecycle hands to `CocxyCoreBridge.sendText`.
///
/// The decision is one bit: is bracketed paste mode currently active on
/// the receiving terminal? When yes (every modern shell and many
/// terminal-aware CLI prompters activate the mode at startup), the payload is
/// wrapped with `CSI 200~ ... CSI 201~` so a multi-line block survives
/// being focused on a shell prompt without being interpreted as
/// separate commands. When no, the payload is returned untouched so
/// the markers do not leak as visible `[200~` / `[201~` characters in
/// the terminal — exactly the bug the previous unconditional-wrap
/// implementation could surface.
///
/// Mirrors the wrap logic in `CocxyCoreView.handlePaste(...)` so any
/// future caller that injects text on behalf of the user follows the
/// same contract instead of re-implementing the check inline.
enum BrowserDOMGrabPayloadInjection {

    /// Wraps `formattedPayload` for `CocxyCoreBridge.sendText`.
    ///
    /// - Parameters:
    ///   - formattedPayload: Multi-line text produced by
    ///     `BrowserDOMGrabPayloadFormatter.format`.
    ///   - bracketedPasteActive: `true` when the receiving terminal has
    ///     bracketed paste mode active (`cocxycore_terminal_mode_bracketed_paste`
    ///     returns true). Caller passes the live mode flag from the
    ///     bridge's `surfaceState(for:)`.
    /// - Returns: The exact byte-string to send through the bridge —
    ///   wrapped with the bracketed-paste markers when the mode is
    ///   active, untouched otherwise.
    static func wrap(
        _ formattedPayload: String,
        bracketedPasteActive: Bool
    ) -> String {
        if bracketedPasteActive {
            return "\u{1B}[200~\(formattedPayload)\u{1B}[201~"
        }
        return formattedPayload
    }
}
