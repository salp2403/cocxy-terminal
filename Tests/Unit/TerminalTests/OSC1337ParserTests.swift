// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OSC1337ParserTests.swift - Tests for OSC 1337 inline image parsing.

import XCTest
@testable import CocxyTerminal

final class OSC1337ParserTests: XCTestCase {

    // MARK: - Valid Payloads

    func testParsesMinimalInlineImage() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.inline)
        XCTAssertTrue(result!.preserveAspectRatio)
        XCTAssertFalse(result!.imageData.isEmpty)
    }

    func testParsesWidthAndHeightDimensions() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=width=100;height=50;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 100)
        XCTAssertEqual(result?.height, 50)
    }

    func testParsesPixelSuffixDimensions() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=width=200px;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertEqual(result?.width, 200)
    }

    func testAutoDimensionResolvesToNil() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=width=auto;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertNil(result?.width, "auto should resolve to nil so the renderer decides")
    }

    func testPreserveAspectRatioDefaultsToTrue() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertTrue(result?.preserveAspectRatio ?? false)
    }

    func testPreserveAspectRatioExplicitlyFalse() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=preserveAspectRatio=0;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertEqual(result?.preserveAspectRatio, false)
    }

    func testParsesBase64EncodedFilename() {
        let tinyPNG = createTinyPNGBase64()
        let nameBase64 = Data("photo.png".utf8).base64EncodedString()
        let payload = "File=name=\(nameBase64);inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertEqual(result?.filename, "photo.png")
    }

    func testNonInlineImageHasInlineFalse() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=inline=0:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.inline)
    }

    func testDefaultInlineIsFalse() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=size=100:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.inline, "Without explicit inline=1, should default to false")
    }

    func testParsesSizeParameter() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=size=12345;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.inline)
    }

    func testParsesAllParametersTogether() {
        let tinyPNG = createTinyPNGBase64()
        let nameBase64 = Data("test.png".utf8).base64EncodedString()
        let payload = "File=name=\(nameBase64);size=500;width=320;height=240;preserveAspectRatio=1;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.filename, "test.png")
        XCTAssertEqual(result?.width, 320)
        XCTAssertEqual(result?.height, 240)
        XCTAssertTrue(result!.preserveAspectRatio)
        XCTAssertTrue(result!.inline)
    }

    // MARK: - Invalid Payloads

    func testRejectsEmptyPayload() {
        XCTAssertNil(OSC1337Parser.parse(""))
    }

    func testRejectsPayloadWithoutFilePrefix() {
        XCTAssertNil(OSC1337Parser.parse("Something=inline=1:abc"))
    }

    func testRejectsPayloadWithoutColon() {
        XCTAssertNil(OSC1337Parser.parse("File=inline=1"))
    }

    func testRejectsInvalidBase64Data() {
        // Use a string that is definitely not valid base64 even with ignoreUnknownCharacters.
        // A single byte "!" repeated cannot form valid base64 groups.
        XCTAssertNil(OSC1337Parser.parse("File=inline=1:!@#$%"))
    }

    func testRejectsEmptyBase64Data() {
        XCTAssertNil(OSC1337Parser.parse("File=inline=1:"))
    }

    func testRejectsPayloadWithOnlyFileEquals() {
        XCTAssertNil(OSC1337Parser.parse("File="))
    }

    // MARK: - Dimension Parsing Edge Cases

    func testDimensionWithZeroReturnsZero() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=width=0;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertEqual(result?.width, 0)
    }

    func testDimensionWithNonNumericReturnsNil() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=width=abc;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNil(result?.width)
    }

    func testHeightAutoReturnsNil() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=height=auto;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNil(result?.height)
    }

    // MARK: - Filename Edge Cases

    func testMissingFilenameReturnsNil() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNil(result?.filename)
    }

    func testInvalidBase64FilenameReturnsNil() {
        let tinyPNG = createTinyPNGBase64()
        let payload = "File=name=!!!invalid!!!;inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertNil(result?.filename)
    }

    func testFilenameWithSpecialCharacters() {
        let tinyPNG = createTinyPNGBase64()
        let name = "my image (1).png"
        let nameBase64 = Data(name.utf8).base64EncodedString()
        let payload = "File=name=\(nameBase64);inline=1:\(tinyPNG)"

        let result = OSC1337Parser.parse(payload)

        XCTAssertEqual(result?.filename, name)
    }

    // MARK: - Helpers

    /// Creates a minimal valid PNG as a base64 string for testing.
    private func createTinyPNGBase64() -> String {
        // Minimal 1x1 pixel red PNG (67 bytes).
        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // RGB
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, // compressed
            0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, // data
            0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
            0x44, 0xAE, 0x42, 0x60, 0x82,
        ]
        return Data(pngBytes).base64EncodedString()
    }
}
