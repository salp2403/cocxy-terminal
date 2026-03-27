// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyThemeImporterTests.swift - Tests for Ghostty theme format import.

import XCTest
@testable import CocxyTerminal

// MARK: - Ghostty Theme Importer Tests

/// Tests for `GhosttyThemeImporter` covering parsing of Ghostty's
/// key=value theme format and conversion to Cocxy `Theme` objects.
///
/// Ghostty theme format:
/// ```
/// background = #1e1e2e
/// foreground = #cdd6f4
/// palette = 0=#45475a
/// palette = 1=#f38ba8
/// ...
/// palette = 15=#a6adc8
/// cursor-color = #f5e0dc
/// selection-background = #585b70
/// ```
///
/// Covers:
/// - Full palette parsing
/// - Palette index mapping (0=black, 1=red, ..., 15=brightWhite)
/// - Import produces valid Theme
/// - Missing colors use defaults
/// - Invalid hex values are skipped
/// - Background/foreground extraction
/// - Cursor and selection colors
/// - Theme name derivation from filename
final class GhosttyThemeImporterTests: XCTestCase {

    func testParseGhosttyThemeFormatExtractsBackgroundAndForeground() throws {
        let content = """
        background = #1e1e2e
        foreground = #cdd6f4
        cursor-color = #f5e0dc
        selection-background = #585b70
        palette = 0=#45475a
        palette = 1=#f38ba8
        palette = 2=#a6e3a1
        palette = 3=#f9e2af
        palette = 4=#89b4fa
        palette = 5=#f5c2e7
        palette = 6=#94e2d5
        palette = 7=#bac2de
        palette = 8=#585b70
        palette = 9=#f38ba8
        palette = 10=#a6e3a1
        palette = 11=#f9e2af
        palette = 12=#89b4fa
        palette = 13=#f5c2e7
        palette = 14=#94e2d5
        palette = 15=#a6adc8
        """

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "catppuccin-mocha"
        )

        XCTAssertEqual(theme.palette.background, "#1e1e2e")
        XCTAssertEqual(theme.palette.foreground, "#cdd6f4")
    }

    func testPaletteMappingIndexZeroIsBlack() throws {
        let content = makeMinimalGhosttyTheme(overrides: [
            "palette = 0=#45475a"
        ])

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "test"
        )

        XCTAssertEqual(theme.palette.ansiColors[0], "#45475a")
    }

    func testPaletteMappingIndex1IsRed() throws {
        let content = makeMinimalGhosttyTheme(overrides: [
            "palette = 1=#f38ba8"
        ])

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "test"
        )

        XCTAssertEqual(theme.palette.ansiColors[1], "#f38ba8")
    }

    func testPaletteMappingIndex15IsBrightWhite() throws {
        let content = makeMinimalGhosttyTheme(overrides: [
            "palette = 15=#a6adc8"
        ])

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "test"
        )

        XCTAssertEqual(theme.palette.ansiColors[15], "#a6adc8")
    }

    func testImportProducesValidThemeWithAllFields() throws {
        let content = makeFullGhosttyTheme()

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "my-ghostty-theme"
        )

        XCTAssertEqual(theme.metadata.name, "my-ghostty-theme")
        XCTAssertEqual(theme.metadata.source, .ghosttyImport)
        XCTAssertEqual(theme.palette.ansiColors.count, 16)
        XCTAssertFalse(theme.palette.background.isEmpty)
        XCTAssertFalse(theme.palette.foreground.isEmpty)
        XCTAssertFalse(theme.palette.cursor.isEmpty)
    }

    func testMissingColorsUseDefaults() throws {
        // Only background and foreground, no palette
        let content = """
        background = #000000
        foreground = #ffffff
        """

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "sparse"
        )

        XCTAssertEqual(theme.palette.background, "#000000")
        XCTAssertEqual(theme.palette.foreground, "#ffffff")
        // Missing palette colors should have defaults
        XCTAssertEqual(theme.palette.ansiColors.count, 16)
        for color in theme.palette.ansiColors {
            XCTAssertFalse(color.isEmpty, "Default ANSI colors must not be empty")
        }
    }

    func testInvalidHexValuesAreSkipped() throws {
        let content = """
        background = #1e1e2e
        foreground = #cdd6f4
        palette = 0=#INVALID
        palette = 1=#f38ba8
        """

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "invalid-hex"
        )

        // Index 0 should use default since hex was invalid
        XCTAssertNotEqual(theme.palette.ansiColors[0], "#INVALID")
        // Index 1 should be parsed correctly
        XCTAssertEqual(theme.palette.ansiColors[1], "#f38ba8")
    }

    func testCursorColorExtraction() throws {
        let content = makeMinimalGhosttyTheme(overrides: [
            "cursor-color = #f5e0dc"
        ])

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "test"
        )

        XCTAssertEqual(theme.palette.cursor, "#f5e0dc")
    }

    func testSelectionBackgroundExtraction() throws {
        let content = makeMinimalGhosttyTheme(overrides: [
            "selection-background = #585b70"
        ])

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "test"
        )

        XCTAssertEqual(theme.palette.selectionBackground, "#585b70")
    }

    func testThemeNameDerivedFromFilename() throws {
        let content = makeMinimalGhosttyTheme()

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "catppuccin-mocha"
        )

        XCTAssertEqual(theme.metadata.name, "catppuccin-mocha")
    }

    func testCommentsAndEmptyLinesAreIgnored() throws {
        let content = """
        # This is a comment
        background = #1e1e2e

        # Another comment
        foreground = #cdd6f4

        palette = 0=#45475a
        palette = 1=#f38ba8
        palette = 2=#a6e3a1
        palette = 3=#f9e2af
        palette = 4=#89b4fa
        palette = 5=#f5c2e7
        palette = 6=#94e2d5
        palette = 7=#bac2de
        palette = 8=#585b70
        palette = 9=#f38ba8
        palette = 10=#a6e3a1
        palette = 11=#f9e2af
        palette = 12=#89b4fa
        palette = 13=#f5c2e7
        palette = 14=#94e2d5
        palette = 15=#a6adc8
        """

        let theme = try GhosttyThemeImporter.importFromContent(
            content,
            themeName: "with-comments"
        )

        XCTAssertEqual(theme.palette.background, "#1e1e2e")
        XCTAssertEqual(theme.palette.foreground, "#cdd6f4")
    }

    // MARK: - Test Helpers

    private func makeMinimalGhosttyTheme(overrides: [String] = []) -> String {
        var lines = [
            "background = #000000",
            "foreground = #ffffff"
        ]
        for i in 0...15 {
            lines.append("palette = \(i)=#\(String(format: "%02x%02x%02x", i * 16, i * 16, i * 16))")
        }
        lines.append(contentsOf: overrides)
        return lines.joined(separator: "\n")
    }

    private func makeFullGhosttyTheme() -> String {
        """
        background = #1e1e2e
        foreground = #cdd6f4
        cursor-color = #f5e0dc
        selection-background = #585b70
        palette = 0=#45475a
        palette = 1=#f38ba8
        palette = 2=#a6e3a1
        palette = 3=#f9e2af
        palette = 4=#89b4fa
        palette = 5=#f5c2e7
        palette = 6=#94e2d5
        palette = 7=#bac2de
        palette = 8=#585b70
        palette = 9=#f38ba8
        palette = 10=#a6e3a1
        palette = 11=#f9e2af
        palette = 12=#89b4fa
        palette = 13=#f5c2e7
        palette = 14=#94e2d5
        palette = 15=#a6adc8
        """
    }
}
