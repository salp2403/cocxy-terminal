// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodableColorTests.swift - Tests for hex color parsing and conversion.

import XCTest
@testable import CocxyTerminal

// MARK: - CodableColor Tests

/// Tests for `CodableColor` hex parsing and NSColor conversion.
///
/// Covers:
/// - Valid hex parsing (#RRGGBB)
/// - Valid hex parsing with alpha (#RRGGBBAA)
/// - Invalid hex graceful handling
/// - NSColor conversion round-trip
/// - Edge cases (lowercase, uppercase, missing hash)
final class CodableColorTests: XCTestCase {

    // MARK: - Hex Parsing

    func testValidSixDigitHexParsesCorrectly() {
        let color = CodableColor(hex: "#ff0000")

        XCTAssertEqual(color.hex, "#ff0000")
        XCTAssertNotNil(color.nsColor)
    }

    func testValidEightDigitHexWithAlphaParsesCorrectly() {
        let color = CodableColor(hex: "#ff000080")

        XCTAssertEqual(color.hex, "#ff000080")
        XCTAssertNotNil(color.nsColor)
    }

    func testUppercaseHexParsesCorrectly() {
        let color = CodableColor(hex: "#FF0000")

        XCTAssertNotNil(color.nsColor)
    }

    func testMixedCaseHexParsesCorrectly() {
        let color = CodableColor(hex: "#fF00aA")

        XCTAssertNotNil(color.nsColor)
    }

    func testHexWithoutHashParsesGracefully() {
        let color = CodableColor(hex: "ff0000")

        // Should still produce a valid color by tolerating missing hash
        XCTAssertNotNil(color.nsColor)
    }

    // MARK: - NSColor Conversion

    func testRedHexConvertsToCorrectNSColor() {
        let color = CodableColor(hex: "#ff0000")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testGreenHexConvertsToCorrectNSColor() {
        let color = CodableColor(hex: "#00ff00")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0.0, accuracy: 0.01)
    }

    func testBlueHexConvertsToCorrectNSColor() {
        let color = CodableColor(hex: "#0000ff")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 1.0, accuracy: 0.01)
    }

    func testBlackHexConvertsToCorrectNSColor() {
        let color = CodableColor(hex: "#000000")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0.0, accuracy: 0.01)
    }

    func testWhiteHexConvertsToCorrectNSColor() {
        let color = CodableColor(hex: "#ffffff")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 1.0, accuracy: 0.01)
    }

    func testAlphaChannelInEightDigitHex() {
        let color = CodableColor(hex: "#ff000080")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.alphaComponent, 128.0 / 255.0, accuracy: 0.01)
    }

    // MARK: - Invalid Hex Handling

    func testInvalidHexDefaultsToBlack() {
        let color = CodableColor(hex: "#zzzzzz")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0.0, accuracy: 0.01)
    }

    func testEmptyHexDefaultsToBlack() {
        let color = CodableColor(hex: "")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0.0, accuracy: 0.01)
    }

    func testTooShortHexDefaultsToBlack() {
        let color = CodableColor(hex: "#ff0")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0.0, accuracy: 0.01)
    }

    // MARK: - NSColor to CodableColor

    func testInitFromNSColorProducesValidHex() {
        let nsColor = NSColor(srgbRed: 1.0, green: 0.0, blue: 0.5, alpha: 1.0)
        let codableColor = CodableColor(nsColor: nsColor)

        XCTAssertTrue(codableColor.hex.hasPrefix("#"))
        XCTAssertEqual(codableColor.hex.count, 7, "6-digit hex + hash = 7 chars")
    }

    func testNSColorRoundTripPreservesComponents() {
        let original = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        let codableColor = CodableColor(nsColor: original)
        let restored = codableColor.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(restored.redComponent, 0.2, accuracy: 0.01)
        XCTAssertEqual(restored.greenComponent, 0.4, accuracy: 0.01)
        XCTAssertEqual(restored.blueComponent, 0.6, accuracy: 0.01)
    }

    func testNSColorWithAlphaProducesEightDigitHex() {
        let nsColor = NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)
        let codableColor = CodableColor(nsColor: nsColor)

        XCTAssertEqual(codableColor.hex.count, 9, "8-digit hex + hash = 9 chars")
    }

    func testNSColorFullAlphaProducesSixDigitHex() {
        let nsColor = NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let codableColor = CodableColor(nsColor: nsColor)

        XCTAssertEqual(codableColor.hex.count, 7, "Full alpha omits alpha channel")
    }

    // MARK: - Catppuccin Mocha Specific Colors

    func testCatppuccinMochaBackgroundParsesCorrectly() {
        let color = CodableColor(hex: "#1e1e2e")
        let nsColor = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(nsColor.redComponent, 30.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 30.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 46.0 / 255.0, accuracy: 0.01)
    }
}
