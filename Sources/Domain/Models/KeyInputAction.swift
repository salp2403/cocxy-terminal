// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeyInputAction.swift - Classifies keyboard input into terminal or application actions.

import Foundation

// MARK: - Key Input Action

/// Classifies a keyboard event into the action the application should take.
///
/// Terminal applications must distinguish between:
/// - **Application commands**: Cmd+C (copy), Cmd+V (paste), Cmd+A (select all)
/// - **Terminal input**: Regular characters, Ctrl+key, Option+key, arrow keys
///
/// The classification depends on modifier keys:
/// - `Cmd` modifier → application command (macOS convention)
/// - `Ctrl` modifier → terminal control character
/// - `Option` modifier → escape sequence for terminal programs (tmux, vim)
/// - No modifier → regular terminal input
enum KeyInputAction: Equatable, Sendable {

    /// Copy selected text to clipboard (Cmd+C).
    case copy

    /// Paste clipboard text into terminal (Cmd+V).
    case paste

    /// Select all text in terminal (Cmd+A).
    case selectAll

    /// Clear the visible screen (Cmd+K).
    case clearScreen

    /// Send the key event to the terminal (regular input, Ctrl+key, Option+key, etc.).
    case sendToTerminal

    // MARK: - Classification

    /// Classifies a key event based on its key code, modifiers, and characters.
    ///
    /// - Parameters:
    ///   - keyCode: The macOS hardware key code.
    ///   - modifiers: Active modifier flags.
    ///   - characters: The character(s) produced by the key event, if any.
    /// - Returns: The action the application should take.
    static func classify(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        characters: String?
    ) -> KeyInputAction {
        // Cmd-only shortcuts (no Shift, no Ctrl, no Option alongside).
        if modifiers == .command {
            switch keyCode {
            case 0x08: return .copy        // Cmd+C
            case 0x09: return .paste       // Cmd+V
            case 0x00: return .selectAll   // Cmd+A
            case 0x28: return .clearScreen // Cmd+K
            default: break
            }
        }

        // Everything else goes to the terminal.
        return .sendToTerminal
    }
}
