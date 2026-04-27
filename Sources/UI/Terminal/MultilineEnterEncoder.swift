// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MultilineEnterEncoder.swift - Pure helper that encodes Shift+Return as
// the byte sequence agent CLI prompters expect for "extend the prompt"
// rather than "submit".

import Foundation

/// Pure key-event classifier that owns exactly one chord — Shift+Return —
/// and turns it into the PTY bytes an AI-agent CLI prompter expects when
/// the user wants a newline that does NOT submit the prompt.
///
/// Other keys, plain Return, and Shift combined with additional modifiers
/// all return `nil` so the caller's regular dispatch (kitty-aware
/// `cocxycore_terminal_encode_key`, `interpretKeyEvents`, NSResponder
/// selectors) is preserved untouched. The encoder only ever produces a
/// byte sequence for the canonical Shift+Return chord.
///
/// ## Why Shift+Return is special
///
/// AI-agent CLIs (claude-code, codex, gemini, aider) draw an in-process
/// prompt that needs to distinguish "submit" from "newline-continue".
/// They follow the de facto convention used by every modern terminal
/// emulator on macOS:
///   * Plain Return is `CR` (`\r`) and submits.
///   * Shift+Return is either the kitty keyboard report `CSI 13;2u`
///     (when the protocol is active) or a literal `LF` (`\n`) as the
///     legacy fallback. Both are interpreted as "newline-continue".
///
/// Without this distinction the prompter only ever sees `CR` and the
/// user can never type a multiline message — exactly the bug Said
/// reported when working with agents inside Cocxy panes.
enum MultilineEnterEncoder {

    /// macOS hardware key code for the main keyboard's Return key.
    /// `0x24` is layout-independent and matches `kVK_Return` in
    /// `<HIToolbox/Events.h>`.
    private static let mainReturnKeyCode: UInt16 = 0x24

    /// Returns the PTY bytes to inject when the event is Shift+Return,
    /// or `nil` for any other event so the caller's existing dispatch
    /// path runs unchanged.
    ///
    /// - Parameters:
    ///   - keyCode: macOS hardware key code from `NSEvent.keyCode`.
    ///   - modifiers: Active modifier flags translated by the view layer.
    ///     The encoder requires the modifier set to be exactly
    ///     `[.shift]`; any extra modifier (Cmd, Ctrl, Option) defers to
    ///     the regular path so menu shortcuts, terminal control codes,
    ///     and dead-key composition stay intact.
    ///   - kittyKeyboardActive: `true` when the underlying terminal has
    ///     the kitty keyboard protocol enabled (read from
    ///     `cocxycore_terminal_mode_kitty_keyboard`). The protocol
    ///     reports each key as `CSI codepoint;modifiers u`; for
    ///     Shift+Return that is `CSI 13;2u`. When the protocol is
    ///     inactive the encoder emits a single `LF` byte instead — the
    ///     canonical legacy distinction between "extend the prompt" and
    ///     "submit" (which arrives as `CR`).
    /// - Returns: The PTY bytes to write via `bridge.writeBytes`, or
    ///   `nil` if the event is not the canonical Shift+Return chord
    ///   the encoder owns.
    static func bytes(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        kittyKeyboardActive: Bool
    ) -> [UInt8]? {
        guard keyCode == mainReturnKeyCode else { return nil }
        // Exact match on the modifier set keeps the encoder out of the
        // way of any compound chord the rest of the dispatch chain
        // wants to handle (Cmd+Shift+Return, Ctrl+Shift+Return, etc.).
        guard modifiers == .shift else { return nil }

        if kittyKeyboardActive {
            // CSI 13;2u — kitty keyboard protocol report for Shift+Return.
            // Bytes spelled out so the assertion in the test suite reads
            // as the wire payload rather than as the source string.
            return [0x1B, 0x5B, 0x31, 0x33, 0x3B, 0x32, 0x75]
        }

        // Legacy fallback: a single line feed. Plain Return arrives as
        // CR, so a standalone LF is the canonical "newline-continue"
        // signal AI-agent prompters interpret as multiline input.
        return [0x0A]
    }
}
