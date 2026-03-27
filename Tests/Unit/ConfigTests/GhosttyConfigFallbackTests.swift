// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyConfigFallbackTests.swift - Tests for Ghostty config fallback parsing.

import XCTest
@testable import CocxyTerminal

final class GhosttyConfigFallbackTests: XCTestCase {

    // MARK: - File Not Found

    func testReadReturnsNilForMissingFile() {
        let result = GhosttyConfigFallback.read(from: "/nonexistent/path/config")
        XCTAssertNil(result)
    }

    // MARK: - Parsing via read() with temp file

    func testReadParsesValidConfig() throws {
        let content = """
        font-family = "JetBrains Mono"
        font-size = 14
        theme = catppuccin-mocha
        cursor-style = block
        """
        let result = try readFromTempFile(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fontFamily, "JetBrains Mono")
        XCTAssertEqual(result?.fontSize, 14.0)
        XCTAssertEqual(result?.theme, "catppuccin-mocha")
        XCTAssertEqual(result?.cursorStyle, "block")
    }

    func testReadSkipsCommentLines() throws {
        let content = """
        # This is a comment
        font-size = 16
        # Another comment
        theme = dracula
        """
        let result = try readFromTempFile(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fontSize, 16.0)
        XCTAssertEqual(result?.theme, "dracula")
        XCTAssertNil(result?.fontFamily)
    }

    func testReadSkipsBlankLines() throws {
        let content = """

        font-size = 12

        theme = one-dark

        """
        let result = try readFromTempFile(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fontSize, 12.0)
        XCTAssertEqual(result?.theme, "one-dark")
    }

    func testReadHandlesInlineComments() throws {
        let content = """
        font-size = 18 # my preferred size
        theme = solarized # classic theme
        """
        let result = try readFromTempFile(content)
        XCTAssertEqual(result?.fontSize, 18.0)
        XCTAssertEqual(result?.theme, "solarized")
    }

    func testReadHandlesQuotedValuesWithHash() throws {
        let content = """
        font-family = "Fira Code # Retina"
        """
        let result = try readFromTempFile(content)
        XCTAssertNotNil(result)
        // Quoted values should preserve the # inside quotes.
        XCTAssertEqual(result?.fontFamily, "Fira Code # Retina")
    }

    func testReadIgnoresUnknownKeys() throws {
        let content = """
        window-decoration = false
        font-size = 13
        background-opacity = 0.95
        """
        let result = try readFromTempFile(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fontSize, 13.0)
        XCTAssertNil(result?.fontFamily)
    }

    func testReadReturnsNilForEmptyContent() throws {
        let result = try readFromTempFile("")
        XCTAssertNil(result)
    }

    func testReadReturnsNilForOnlyComments() throws {
        let content = """
        # Just comments
        # No actual config
        """
        let result = try readFromTempFile(content)
        XCTAssertNil(result)
    }

    func testReadHandlesNoSpacesAroundEquals() throws {
        let content = "font-size=16\ntheme=mocha"
        let result = try readFromTempFile(content)
        XCTAssertEqual(result?.fontSize, 16.0)
        XCTAssertEqual(result?.theme, "mocha")
    }

    func testReadHandlesExtraSpaces() throws {
        let content = "  font-size  =  20  "
        let result = try readFromTempFile(content)
        XCTAssertEqual(result?.fontSize, 20.0)
    }

    // MARK: - FallbackValues

    func testFallbackValuesIsEmptyWhenAllNil() {
        let values = GhosttyConfigFallback.FallbackValues()
        XCTAssertTrue(values.isEmpty)
    }

    func testFallbackValuesNotEmptyWithFontSize() {
        var values = GhosttyConfigFallback.FallbackValues()
        values.fontSize = 14
        XCTAssertFalse(values.isEmpty)
    }

    // MARK: - Apply to Defaults

    func testApplyToDefaultsOverridesFontSize() {
        var fallback = GhosttyConfigFallback.FallbackValues()
        fallback.fontSize = 18
        let config = GhosttyConfigFallback.applyToDefaults(fallback)
        XCTAssertEqual(config.appearance.fontSize, 18.0)
    }

    func testApplyToDefaultsClampsFontSize() {
        var fallback = GhosttyConfigFallback.FallbackValues()
        fallback.fontSize = 200
        let config = GhosttyConfigFallback.applyToDefaults(fallback)
        XCTAssertEqual(config.appearance.fontSize, 72.0)
    }

    func testApplyToDefaultsClampsTooSmallFontSize() {
        var fallback = GhosttyConfigFallback.FallbackValues()
        fallback.fontSize = 2
        let config = GhosttyConfigFallback.applyToDefaults(fallback)
        XCTAssertEqual(config.appearance.fontSize, 6.0)
    }

    func testApplyToDefaultsKeepsUnsetAtDefault() {
        let fallback = GhosttyConfigFallback.FallbackValues()
        let config = GhosttyConfigFallback.applyToDefaults(fallback)
        let defaults = CocxyConfig.defaults
        XCTAssertEqual(config.appearance.fontFamily, defaults.appearance.fontFamily)
        XCTAssertEqual(config.appearance.fontSize, defaults.appearance.fontSize)
    }

    // MARK: - Helpers

    private func readFromTempFile(_ content: String) throws -> GhosttyConfigFallback.FallbackValues? {
        let tempDir = NSTemporaryDirectory()
        let path = (tempDir as NSString).appendingPathComponent("test-ghostty-config-\(UUID().uuidString)")
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return GhosttyConfigFallback.read(from: path)
    }
}
