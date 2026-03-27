// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyThemeImporter.swift - Import themes from Ghostty's key=value format.

import Foundation

// MARK: - Ghostty Theme Importer

/// Imports themes from Ghostty's key=value theme format into Cocxy `Theme` objects.
///
/// Ghostty themes use a simple line-based format:
/// ```
/// background = #1e1e2e
/// foreground = #cdd6f4
/// cursor-color = #f5e0dc
/// selection-background = #585b70
/// palette = 0=#45475a
/// palette = 1=#f38ba8
/// ...
/// palette = 15=#a6adc8
/// ```
///
/// The 16 palette entries map to standard ANSI colors:
/// 0=black, 1=red, 2=green, 3=yellow, 4=blue, 5=magenta, 6=cyan, 7=white,
/// 8-15=bright variants in the same order.
///
/// Missing colors are filled with sensible defaults. Invalid hex values are
/// silently skipped, leaving the default in place.
///
/// - SeeAlso: ADR-007 (Theme system)
enum GhosttyThemeImporter {

    // MARK: - Default ANSI Colors

    /// Default ANSI color palette used when Ghostty theme omits palette entries.
    private static let defaultAnsiColors: [String] = [
        "#000000", "#cc0000", "#4e9a06", "#c4a000",
        "#3465a4", "#75507b", "#06989a", "#d3d7cf",
        "#555753", "#ef2929", "#8ae234", "#fce94f",
        "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
    ]

    /// Default hex for the cursor when not specified by the Ghostty theme.
    private static let defaultCursor = "#ffffff"

    /// Default hex for selection background when not specified.
    private static let defaultSelectionBackground = "#444444"

    // MARK: - Public API

    /// Imports a Ghostty theme from its raw file content.
    ///
    /// - Parameters:
    ///   - content: The raw text content of a Ghostty theme file.
    ///   - themeName: The display name for the imported theme (typically the filename).
    /// - Returns: A fully resolved `Theme` with metadata and palette.
    /// - Throws: Does not throw; missing values are filled with defaults.
    static func importFromContent(
        _ content: String,
        themeName: String
    ) throws -> Theme {
        let parsed = parseGhosttyFormat(content)

        let background = parsed["background"] ?? "#000000"
        let foreground = parsed["foreground"] ?? "#ffffff"
        let cursor = parsed["cursor-color"] ?? defaultCursor
        let selectionBackground = parsed["selection-background"] ?? defaultSelectionBackground

        let ansiColors = buildAnsiColors(from: parsed)

        let palette = ThemePalette(
            background: background,
            foreground: foreground,
            cursor: cursor,
            selectionBackground: selectionBackground,
            selectionForeground: foreground,
            tabActiveBackground: background,
            tabActiveForeground: foreground,
            tabInactiveBackground: background,
            tabInactiveForeground: foreground,
            badgeAttention: ansiColors[3],  // yellow
            badgeCompleted: ansiColors[2],  // green
            badgeError: ansiColors[1],      // red
            badgeWorking: ansiColors[4],    // blue
            ansiColors: ansiColors
        )

        let variant = detectVariant(background: background)

        let metadata = ThemeMetadata(
            name: themeName,
            variant: variant,
            author: nil,
            source: .ghosttyImport
        )

        return Theme(metadata: metadata, palette: palette)
    }

    // MARK: - Parsing

    /// Parses Ghostty's key=value format into a dictionary.
    ///
    /// Palette entries (`palette = N=#hex`) are stored as `palette-N` keys.
    /// Comments (lines starting with `#`) and empty lines are skipped.
    private static func parseGhosttyFormat(_ content: String) -> [String: String] {
        var result: [String: String] = [:]

        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[line.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)

            if key == "palette" {
                // Format: N=#hex
                if let hashIndex = value.firstIndex(of: "=") {
                    let indexString = String(value[value.startIndex..<hashIndex])
                        .trimmingCharacters(in: .whitespaces)
                    let hexValue = String(value[value.index(after: hashIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    result["palette-\(indexString)"] = hexValue
                }
            } else {
                result[key] = value
            }
        }

        return result
    }

    /// Builds the 16-entry ANSI color array from parsed Ghostty palette entries.
    ///
    /// Each palette index (0-15) maps to a specific ANSI color:
    /// 0=black, 1=red, 2=green, 3=yellow, 4=blue, 5=magenta, 6=cyan, 7=white,
    /// 8-15=bright variants.
    ///
    /// Missing or invalid entries use the default ANSI colors.
    private static func buildAnsiColors(from parsed: [String: String]) -> [String] {
        var colors = defaultAnsiColors

        for index in 0...15 {
            if let hexValue = parsed["palette-\(index)"] {
                if isValidHex(hexValue) {
                    colors[index] = hexValue
                }
            }
        }

        return colors
    }

    /// Validates that a string is a valid hex color.
    ///
    /// Accepts `#RRGGBB` and `RRGGBB` formats.
    private static func isValidHex(_ value: String) -> Bool {
        let sanitized = value.hasPrefix("#") ? String(value.dropFirst()) : value

        guard sanitized.count == 6 || sanitized.count == 8 else {
            return false
        }

        return sanitized.allSatisfy { $0.isHexDigit }
    }

    /// Detects whether a theme is dark or light based on its background luminance.
    ///
    /// Uses a simple perceptual luminance formula (ITU-R BT.601).
    private static func detectVariant(background: String) -> ThemeVariant {
        let sanitized = background.hasPrefix("#") ? String(background.dropFirst()) : background

        guard sanitized.count == 6,
              let hexNumber = UInt64(sanitized, radix: 16) else {
            return .dark
        }

        let red = Double((hexNumber & 0xFF0000) >> 16) / 255.0
        let green = Double((hexNumber & 0x00FF00) >> 8) / 255.0
        let blue = Double(hexNumber & 0x0000FF) / 255.0

        // ITU-R BT.601 perceptual luminance
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue

        return luminance > 0.5 ? .light : .dark
    }
}
