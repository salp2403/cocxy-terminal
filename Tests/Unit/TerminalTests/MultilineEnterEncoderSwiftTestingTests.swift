// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `MultilineEnterEncoder`, the pure helper that
/// classifies a key-down event as either "Shift+Return for an agent
/// prompter that wants a multiline continuation" or "any other key —
/// fall through to the regular dispatch path".
///
/// The encoder owns exactly two outputs:
///   - `CSI 13;2u` when the kitty keyboard protocol is active. AI-agent
///     CLI prompters (claude-code, codex, gemini, aider) opt into the
///     protocol during init, and they expect this exact report for the
///     Shift+Return chord.
///   - `LF` (`\n`) when the protocol is inactive. Plain Return arrives as
///     `CR`, so a standalone `LF` is the canonical legacy distinction
///     between "extend the prompt" and "submit".
///
/// Anything else (plain Return, other keys, additional modifiers) must
/// return `nil` so the caller's existing dispatch chain is preserved.
@Suite("MultilineEnterEncoder")
struct MultilineEnterEncoderSwiftTestingTests {

    // macOS hardware key codes. Pinned here so the assertions read as
    // intent rather than as magic numbers.
    private static let mainReturnKeyCode: UInt16 = 0x24
    private static let tabKeyCode: UInt16 = 0x30
    private static let aKeyCode: UInt16 = 0x00

    // MARK: - Pure Shift+Return

    @Test("Shift+Return with kitty keyboard active emits the CSI 13;2u kitty report")
    func shiftReturnWithKittyEmitsCSIu() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.mainReturnKeyCode,
            modifiers: [.shift],
            kittyKeyboardActive: true
        )

        // ESC `[` `1` `3` `;` `2` `u`
        #expect(bytes == [0x1B, 0x5B, 0x31, 0x33, 0x3B, 0x32, 0x75])
    }

    @Test("Shift+Return with kitty keyboard inactive falls back to a single LF")
    func shiftReturnWithoutKittyEmitsLF() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.mainReturnKeyCode,
            modifiers: [.shift],
            kittyKeyboardActive: false
        )

        #expect(bytes == [0x0A])
    }

    // MARK: - Plain Return passes through

    @Test("plain Return without any modifier returns nil so the default Enter dispatch runs")
    func plainReturnReturnsNil() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.mainReturnKeyCode,
            modifiers: [],
            kittyKeyboardActive: true
        )

        #expect(bytes == nil)
    }

    // MARK: - Other modifier combinations defer to the regular dispatch

    @Test("Cmd+Shift+Return returns nil so menu shortcuts and macOS conventions stay intact")
    func cmdShiftReturnReturnsNil() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.mainReturnKeyCode,
            modifiers: [.shift, .command],
            kittyKeyboardActive: false
        )

        #expect(bytes == nil)
    }

    @Test("Ctrl+Shift+Return returns nil so terminal control sequences stay intact")
    func ctrlShiftReturnReturnsNil() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.mainReturnKeyCode,
            modifiers: [.shift, .control],
            kittyKeyboardActive: false
        )

        #expect(bytes == nil)
    }

    @Test("Option+Shift+Return returns nil so dead-key composition and special chars stay intact")
    func optionShiftReturnReturnsNil() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.mainReturnKeyCode,
            modifiers: [.shift, .option],
            kittyKeyboardActive: false
        )

        #expect(bytes == nil)
    }

    // MARK: - Other keys never match

    @Test("Shift+Tab returns nil — only the main Return key triggers the multiline encoder")
    func shiftTabReturnsNil() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.tabKeyCode,
            modifiers: [.shift],
            kittyKeyboardActive: false
        )

        #expect(bytes == nil)
    }

    @Test("Shift+A returns nil — printable character production must follow the regular path")
    func shiftLetterReturnsNil() {
        let bytes = MultilineEnterEncoder.bytes(
            keyCode: Self.aKeyCode,
            modifiers: [.shift],
            kittyKeyboardActive: false
        )

        #expect(bytes == nil)
    }
}
