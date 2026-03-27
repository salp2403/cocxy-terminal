// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeTomlParser.swift - Parses theme TOML files into Theme objects.

import Foundation

// MARK: - Theme TOML Parser

/// Parses TOML theme files into `Theme` objects.
///
/// Expected TOML format:
/// ```toml
/// [metadata]
/// name = "Theme Name"
/// author = "Author"     # optional
/// variant = "dark"      # "dark" or "light"
///
/// [colors]
/// foreground = "#cdd6f4"
/// background = "#1e1e2e"
/// cursor = "#f5e0dc"
/// selection = "#585b70"
///
/// [colors.normal]       # 8 standard ANSI colors
/// black = "#45475a"
/// ...
///
/// [colors.bright]       # 8 bright ANSI colors
/// black = "#585b70"
/// ...
///
/// [ui]                  # optional, derived if absent
/// tab-bar-background = "#181825"
/// ...
/// ```
///
/// The TOMLParser treats `[colors.normal]` and `[colors.bright]` as table
/// names with literal dots. This parser handles that format.
///
/// - SeeAlso: ADR-007 (Theme system)
enum ThemeTomlParser {

    // MARK: - Public API

    /// Parses a TOML string into a `Theme`.
    ///
    /// - Parameter tomlContent: The raw TOML content of a theme file.
    /// - Returns: A fully resolved `Theme` with metadata and palette.
    /// - Throws: `ThemeError.parseFailed` if required fields are missing or invalid.
    static func parse(_ tomlContent: String) throws -> Theme {
        let parser = TOMLParser()
        let parsed: [String: TOMLValue]

        do {
            parsed = try parser.parse(tomlContent)
        } catch {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Invalid TOML: \(error)"
            )
        }

        let metadata = try parseMetadata(from: parsed)
        let palette = try parsePalette(from: parsed)

        return Theme(metadata: metadata, palette: palette)
    }

    // MARK: - Metadata Parsing

    /// Extracts theme metadata from the `[metadata]` section.
    private static func parseMetadata(
        from parsed: [String: TOMLValue]
    ) throws -> ThemeMetadata {
        guard case .table(let metadataTable) = parsed["metadata"] else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Missing [metadata] section"
            )
        }

        guard case .string(let name) = metadataTable["name"] else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Missing 'name' in [metadata]"
            )
        }

        guard case .string(let variantString) = metadataTable["variant"],
              let variant = ThemeVariant(rawValue: variantString) else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Missing or invalid 'variant' in [metadata] (must be 'dark' or 'light')"
            )
        }

        let author: String?
        if case .string(let authorValue) = metadataTable["author"] {
            author = authorValue
        } else {
            author = nil
        }

        return ThemeMetadata(
            name: name,
            variant: variant,
            author: author,
            source: .custom(URL(fileURLWithPath: "/custom"))
        )
    }

    // MARK: - Palette Parsing

    /// Extracts the color palette from `[colors]`, `[colors.normal]`,
    /// `[colors.bright]`, and optionally `[ui]` sections.
    private static func parsePalette(
        from parsed: [String: TOMLValue]
    ) throws -> ThemePalette {
        guard case .table(let colorsTable) = parsed["colors"] else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Missing [colors] section"
            )
        }

        // Required base colors
        let foreground = try requiredColor("foreground", from: colorsTable)
        let background = try requiredColor("background", from: colorsTable)
        let cursor = try requiredColor("cursor", from: colorsTable)
        let selection = try requiredColor("selection", from: colorsTable)

        // ANSI normal colors from [colors.normal]
        let normalColors = try parseAnsiColorGroup("colors.normal", from: parsed)

        // ANSI bright colors from [colors.bright]
        let brightColors = try parseAnsiColorGroup("colors.bright", from: parsed)

        // 16 ANSI colors: 8 normal + 8 bright
        let ansiColors = normalColors + brightColors

        // UI colors from [ui] section (optional, derived if absent)
        let uiColors = parseUIColors(from: parsed, foreground: foreground, background: background, ansiColors: ansiColors)

        return ThemePalette(
            background: background,
            foreground: foreground,
            cursor: cursor,
            selectionBackground: selection,
            selectionForeground: foreground,
            tabActiveBackground: uiColors.tabActiveBackground,
            tabActiveForeground: foreground,
            tabInactiveBackground: uiColors.tabInactiveBackground,
            tabInactiveForeground: uiColors.tabInactiveForeground,
            badgeAttention: uiColors.badgeAttention,
            badgeCompleted: uiColors.badgeCompleted,
            badgeError: uiColors.badgeError,
            badgeWorking: uiColors.badgeWorking,
            ansiColors: ansiColors
        )
    }

    // MARK: - ANSI Color Group Parsing

    /// Parses a group of 8 ANSI colors from a named section.
    ///
    /// Colors must be provided in order: black, red, green, yellow,
    /// blue, magenta, cyan, white.
    private static func parseAnsiColorGroup(
        _ sectionName: String,
        from parsed: [String: TOMLValue]
    ) throws -> [String] {
        guard case .table(let colorTable) = parsed[sectionName] else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Missing [\(sectionName)] section"
            )
        }

        let colorNames = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        var colors: [String] = []

        for colorName in colorNames {
            guard case .string(let hex) = colorTable[colorName] else {
                throw ThemeError.parseFailed(
                    path: "<inline>",
                    reason: "Missing '\(colorName)' in [\(sectionName)]"
                )
            }
            colors.append(hex)
        }

        return colors
    }

    // MARK: - UI Color Parsing

    /// Container for parsed UI colors.
    private struct UIColors {
        let tabActiveBackground: String
        let tabInactiveBackground: String
        let tabInactiveForeground: String
        let badgeAttention: String
        let badgeCompleted: String
        let badgeError: String
        let badgeWorking: String
    }

    /// Parses UI colors from the `[ui]` section, or derives them from
    /// the base palette if the section is absent.
    ///
    /// Derivation rules (from ADR-007):
    /// - tab-active-background   = background
    /// - tab-inactive-background = background (darker)
    /// - badge-attention         = ANSI yellow
    /// - badge-completed         = ANSI green
    /// - badge-error             = ANSI red
    /// - badge-working           = ANSI blue
    private static func parseUIColors(
        from parsed: [String: TOMLValue],
        foreground: String,
        background: String,
        ansiColors: [String]
    ) -> UIColors {
        if case .table(let uiTable) = parsed["ui"] {
            return UIColors(
                tabActiveBackground: stringValue(uiTable["tab-active-background"]) ?? background,
                tabInactiveBackground: stringValue(uiTable["tab-inactive-background"]) ?? background,
                tabInactiveForeground: stringValue(uiTable["tab-inactive-foreground"]) ?? foreground,
                badgeAttention: stringValue(uiTable["badge-attention"]) ?? ansiYellow(ansiColors),
                badgeCompleted: stringValue(uiTable["badge-completed"]) ?? ansiGreen(ansiColors),
                badgeError: stringValue(uiTable["badge-error"]) ?? ansiRed(ansiColors),
                badgeWorking: stringValue(uiTable["badge-working"]) ?? ansiBlue(ansiColors)
            )
        }

        // Derive from base palette per ADR-007
        return UIColors(
            tabActiveBackground: background,
            tabInactiveBackground: background,
            tabInactiveForeground: foreground,
            badgeAttention: ansiYellow(ansiColors),
            badgeCompleted: ansiGreen(ansiColors),
            badgeError: ansiRed(ansiColors),
            badgeWorking: ansiBlue(ansiColors)
        )
    }

    // MARK: - Helpers

    /// Extracts a required hex color string from a table.
    /// Regex pattern for valid hex color: #RGB, #RRGGBB, or #RRGGBBAA
    // swiftlint:disable:next force_try
    private static let hexColorPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "^#[0-9a-fA-F]{3}([0-9a-fA-F]{3}([0-9a-fA-F]{2})?)?$"
        )
    }()

    private static func requiredColor(
        _ key: String,
        from table: [String: TOMLValue]
    ) throws -> String {
        guard case .string(let hex) = table[key] else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Missing required color '\(key)' in [colors]"
            )
        }
        let range = NSRange(hex.startIndex..., in: hex)
        guard hexColorPattern.firstMatch(in: hex, range: range) != nil else {
            throw ThemeError.parseFailed(
                path: "<inline>",
                reason: "Invalid hex color '\(hex)' for '\(key)'. Expected #RGB, #RRGGBB, or #RRGGBBAA"
            )
        }
        return hex
    }

    /// Extracts a string from a TOML value.
    private static func stringValue(_ value: TOMLValue?) -> String? {
        guard case .string(let content) = value else { return nil }
        return content
    }

    // ANSI color indices: black=0, red=1, green=2, yellow=3, blue=4, magenta=5, cyan=6, white=7
    private static func ansiRed(_ colors: [String]) -> String { colors.count > 1 ? colors[1] : "#ff0000" }
    private static func ansiGreen(_ colors: [String]) -> String { colors.count > 2 ? colors[2] : "#00ff00" }
    private static func ansiYellow(_ colors: [String]) -> String { colors.count > 3 ? colors[3] : "#ffff00" }
    private static func ansiBlue(_ colors: [String]) -> String { colors.count > 4 ? colors[4] : "#0000ff" }
}
