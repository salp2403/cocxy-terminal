// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyThemeConfigBuilderTests.swift - Tests for ghostty config generation from ThemePalette.

import XCTest
@testable import CocxyTerminal

// MARK: - Ghostty Theme Config Builder Tests

/// Tests that `GhosttyThemeConfigBuilder` generates valid ghostty config
/// from a `ThemePalette` and writes it to disk correctly.
final class GhosttyThemeConfigBuilderTests: XCTestCase {

    // MARK: - Config String Generation

    func testBuildConfigStringContainsBackgroundColor() {
        let palette = makeTestPalette(background: "#1e1e2e")
        let result = GhosttyThemeConfigBuilder.buildConfigString(from: palette)

        XCTAssertTrue(
            result.contains("background = 1e1e2e"),
            "El config debe contener el color de fondo sin '#'"
        )
    }

    func testBuildConfigStringContainsForegroundColor() {
        let palette = makeTestPalette(foreground: "#cdd6f4")
        let result = GhosttyThemeConfigBuilder.buildConfigString(from: palette)

        XCTAssertTrue(
            result.contains("foreground = cdd6f4"),
            "El config debe contener el color de texto sin '#'"
        )
    }

    func testBuildConfigStringContainsCursorColor() {
        let palette = makeTestPalette(cursor: "#f5e0dc")
        let result = GhosttyThemeConfigBuilder.buildConfigString(from: palette)

        XCTAssertTrue(
            result.contains("cursor-color = f5e0dc"),
            "El config debe contener el color del cursor"
        )
    }

    func testBuildConfigStringContainsSelectionColors() {
        let palette = makeTestPalette(
            selectionBackground: "#585b70",
            selectionForeground: "#cdd6f4"
        )
        let result = GhosttyThemeConfigBuilder.buildConfigString(from: palette)

        XCTAssertTrue(result.contains("selection-background = 585b70"))
        XCTAssertTrue(result.contains("selection-foreground = cdd6f4"))
    }

    func testBuildConfigStringContainsAnsiPalette() {
        let ansiColors = [
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
            "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"
        ]
        let palette = makeTestPalette(ansiColors: ansiColors)
        let result = GhosttyThemeConfigBuilder.buildConfigString(from: palette)

        // Check first and last ANSI color entries
        XCTAssertTrue(
            result.contains("palette = 0=45475a"),
            "El config debe contener la entrada de paleta 0"
        )
        XCTAssertTrue(
            result.contains("palette = 15=a6adc8"),
            "El config debe contener la entrada de paleta 15"
        )
    }

    func testBuildConfigStringHasCorrectLineCount() {
        let palette = makeTestPalette()
        let result = GhosttyThemeConfigBuilder.buildConfigString(from: palette)
        let lines = result.split(separator: "\n", omittingEmptySubsequences: true)

        // 5 base colors + 16 ANSI palette = 21 lines
        // (term is set once in GhosttyBridge.loadGhosttyConfig, not here)
        XCTAssertEqual(
            lines.count, 21,
            "Config should have 21 lines (5 base + 16 ANSI)"
        )
    }

    // MARK: - File Writing

    func testWriteTemporaryConfigFileReturnsValidPath() {
        let content = "background = 1e1e2e\n"
        let path = GhosttyThemeConfigBuilder.writeTemporaryConfigFile(content)

        XCTAssertNotNil(path, "Debe devolver un path valido")

        if let path = path {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path),
                "El archivo debe existir en disco"
            )
            // Cleanup
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func testWrittenFileContainsExpectedContent() {
        let content = "background = 1e1e2e\nforeground = cdd6f4\n"
        guard let path = GhosttyThemeConfigBuilder.writeTemporaryConfigFile(content) else {
            XCTFail("No se pudo escribir el archivo")
            return
        }

        let readContent = try? String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(
            readContent, content,
            "El contenido leido debe coincidir con lo escrito"
        )

        // Cleanup
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Helpers

    private func makeTestPalette(
        background: String = "#1e1e2e",
        foreground: String = "#cdd6f4",
        cursor: String = "#f5e0dc",
        selectionBackground: String = "#585b70",
        selectionForeground: String = "#cdd6f4",
        ansiColors: [String] = [
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
            "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"
        ]
    ) -> ThemePalette {
        ThemePalette(
            background: background,
            foreground: foreground,
            cursor: cursor,
            selectionBackground: selectionBackground,
            selectionForeground: selectionForeground,
            tabActiveBackground: "#1e1e2e",
            tabActiveForeground: "#cdd6f4",
            tabInactiveBackground: "#181825",
            tabInactiveForeground: "#6c7086",
            badgeAttention: "#f9e2af",
            badgeCompleted: "#a6e3a1",
            badgeError: "#f38ba8",
            badgeWorking: "#89b4fa",
            ansiColors: ansiColors
        )
    }
}
