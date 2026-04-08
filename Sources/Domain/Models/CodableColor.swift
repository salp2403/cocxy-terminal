// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodableColor.swift - Hex color representation with NSColor conversion.

import AppKit

// MARK: - CodableColor

/// A color represented as a hex string that can be converted to/from NSColor.
///
/// Supports `#RRGGBB` and `#RRGGBBAA` formats. Invalid hex values degrade
/// gracefully to black rather than crashing.
///
/// This type lives in the UI-adjacent layer because it imports AppKit.
/// The domain layer (`ThemePalette`) stores colors as plain `String` hex values.
///
/// - SeeAlso: `ThemePalette` (domain layer, hex strings only)
struct CodableColor: Equatable, Sendable {

    /// The hex string representation (e.g., "#1e1e2e" or "#1e1e2eff").
    let hex: String

    // MARK: - Initialization

    /// Creates a CodableColor from a hex string.
    ///
    /// Accepted formats: `#RRGGBB`, `#RRGGBBAA`, `RRGGBB`, `RRGGBBAA`.
    /// Invalid values are stored as-is; conversion to NSColor will fall back to black.
    ///
    /// - Parameter hex: The hex color string.
    init(hex: String) {
        self.hex = hex
    }

    /// Creates a CodableColor from an NSColor.
    ///
    /// Converts the color to sRGB color space before extracting components.
    /// Colors with full alpha (1.0) produce 6-digit hex; others produce 8-digit.
    ///
    /// - Parameter nsColor: The AppKit color to convert.
    init(nsColor: NSColor) {
        let srgbColor = nsColor.usingColorSpace(.sRGB) ?? nsColor

        let red = Int(round(srgbColor.redComponent * 255))
        let green = Int(round(srgbColor.greenComponent * 255))
        let blue = Int(round(srgbColor.blueComponent * 255))
        let alpha = srgbColor.alphaComponent

        if alpha >= 0.999 {
            self.hex = String(format: "#%02x%02x%02x", red, green, blue)
        } else {
            let alphaInt = Int(round(alpha * 255))
            self.hex = String(format: "#%02x%02x%02x%02x", red, green, blue, alphaInt)
        }
    }

    // MARK: - NSColor Conversion

    /// Converts the hex string to an NSColor in sRGB color space.
    ///
    /// Invalid hex strings produce `NSColor.black` as a safe fallback.
    var nsColor: NSColor {
        let sanitized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex

        guard sanitized.count == 6 || sanitized.count == 8 else {
            return NSColor.black
        }

        guard let hexNumber = UInt64(sanitized, radix: 16) else {
            return NSColor.black
        }

        if sanitized.count == 6 {
            let red = CGFloat((hexNumber & 0xFF0000) >> 16) / 255.0
            let green = CGFloat((hexNumber & 0x00FF00) >> 8) / 255.0
            let blue = CGFloat(hexNumber & 0x0000FF) / 255.0
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
        } else {
            let red = CGFloat((hexNumber & 0xFF000000) >> 24) / 255.0
            let green = CGFloat((hexNumber & 0x00FF0000) >> 16) / 255.0
            let blue = CGFloat((hexNumber & 0x0000FF00) >> 8) / 255.0
            let alpha = CGFloat(hexNumber & 0x000000FF) / 255.0
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
    }

    static func == (lhs: CodableColor, rhs: CodableColor) -> Bool {
        lhs.normalizedHex == rhs.normalizedHex
    }

    private var normalizedHex: String {
        hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
    }
}
