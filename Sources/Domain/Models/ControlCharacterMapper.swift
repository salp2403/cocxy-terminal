// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ControlCharacterMapper.swift - Maps Ctrl+letter to ASCII control characters.

import Foundation

// MARK: - Control Character Mapper

/// Maps Ctrl+letter combinations to their corresponding ASCII control characters.
///
/// In terminal emulation, Ctrl+letter produces a control character computed as:
/// `letter_ascii_value - 64` (for uppercase) or `letter_ascii_value - 96` (for lowercase).
/// This yields values 0x01 (Ctrl+A) through 0x1A (Ctrl+Z).
///
/// Common control characters:
/// - Ctrl+C → ETX (0x03) — interrupt (SIGINT)
/// - Ctrl+D → EOT (0x04) — end of file
/// - Ctrl+Z → SUB (0x1A) — suspend (SIGTSTP)
/// - Ctrl+A → SOH (0x01) — beginning of line
/// - Ctrl+E → ENQ (0x05) — end of line
/// - Ctrl+L → FF  (0x0C) — clear screen
///
/// This mapper is stateless and all methods are static.
enum ControlCharacterMapper {

    /// Returns the ASCII control character code for the given letter when combined with Ctrl.
    ///
    /// - Parameter letter: A single letter character (a-z or A-Z).
    /// - Returns: The control character byte value (0x01-0x1A), or `nil` if the input
    ///   is not a single ASCII letter.
    static func controlCharacter(forLetter letter: String) -> UInt8? {
        guard letter.count == 1,
              let scalar = letter.unicodeScalars.first else {
            return nil
        }

        let value = scalar.value

        // Uppercase A-Z: 65-90, control char = value - 64
        if value >= 65, value <= 90 {
            return UInt8(value - 64)
        }

        // Lowercase a-z: 97-122, control char = value - 96
        if value >= 97, value <= 122 {
            return UInt8(value - 96)
        }

        return nil
    }

    /// Returns a single-character string containing the control character for Ctrl+letter.
    ///
    /// This is convenient for passing to terminal APIs that expect a text string
    /// rather than a raw byte value.
    ///
    /// - Parameter letter: A single letter character (a-z or A-Z).
    /// - Returns: A string containing the single control character, or `nil` if the
    ///   input is not a single ASCII letter.
    static func controlCharacterText(forLetter letter: String) -> String? {
        guard let byte = controlCharacter(forLetter: letter) else {
            return nil
        }
        return String(Unicode.Scalar(byte))
    }
}
