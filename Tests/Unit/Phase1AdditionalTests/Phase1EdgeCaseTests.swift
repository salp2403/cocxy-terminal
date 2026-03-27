// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase1EdgeCaseTests.swift - Additional edge case tests to close Phase 1 coverage gaps.
//
// This file is El Rompe-cosas' contribution: 25 tests targeting the exact edge
// cases that the happy-path suite left uncovered. Written after systematic code
// review of all Phase 1 source files.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - T1: TOMLParser Unicode & Exotic Strings

/// Edge cases: Unicode, emoji, hash-inside-string, equals-sign in value,
/// multiline Windows line endings, zero-length table name, empty value.
final class TOMLParserEdgeCaseTests: XCTestCase {

    private var parser: TOMLParser!

    override func setUp() {
        super.setUp()
        parser = TOMLParser()
    }

    // TEST 1: Hash (#) inside a quoted string must NOT be treated as a comment.
    //
    // Reason: stripComment iterates char-by-char and toggles insideQuote on ".
    // A naive implementation breaks when the # appears before the closing quote.
    func testHashInsideQuotedStringIsNotTreatedAsComment() throws {
        // Build the TOML string without raw-string literals to avoid Swift parser
        // ambiguity with the embedded # character.
        let toml = "color = \"" + "#FF00FF" + "\""
        let result = try parser.parse(toml)
        XCTAssertEqual(
            result["color"],
            .string("#FF00FF"),
            "A # inside a quoted string must not be stripped as a comment"
        )
    }

    // TEST 2: Unicode characters in string values.
    //
    // Reason: String.count is character-count in Swift but TOML strings are
    // UTF-8. We want to verify the parser returns the unicode string intact.
    func testUnicodeCharactersInStringValue() throws {
        let toml = """
        greeting = "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}"
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(
            result["greeting"],
            .string("こんにちは"),
            "Unicode characters in string values must be preserved"
        )
    }

    // TEST 3: Emoji in string values (multi-scalar Unicode).
    //
    // Reason: Emoji are composed of multiple Unicode scalars (e.g. flag emoji).
    // Swift's String handles them transparently but the parser touches scalars.
    func testEmojiInStringValue() throws {
        // Rocket emoji U+1F680, embedded without raw-string to avoid # issues.
        let emoji = "\u{1F680}"
        let toml = "label = \"" + emoji + "\""
        let result = try parser.parse(toml)
        XCTAssertEqual(
            result["label"],
            .string(emoji),
            "Emoji in string values must be preserved"
        )
    }

    // TEST 4: Equals sign in a string value.
    //
    // Reason: parseKeyValuePair uses firstIndex(of: "=") which splits on the
    // FIRST "=" only. We verify this explicitly.
    func testEqualsSignInStringValue() throws {
        let value = "http://example.com?a=1&b=2"
        let toml = "url = \"" + value + "\""
        let result = try parser.parse(toml)
        XCTAssertEqual(
            result["url"],
            .string(value),
            "Equals signs in string values must not split the key-value pair"
        )
    }

    // TEST 5: Windows-style CRLF line endings.
    //
    // Reason: The parser splits on "\n". A CRLF file would leave "\r" at the
    // end of stripped lines. trimmingCharacters(in: .whitespaces) strips \r,
    // so this should pass -- but worth verifying explicitly.
    func testWindowsLineEndingsAreTolerated() throws {
        let toml = "name = \"hello\"\r\ncount = 42\r\n"
        let result = try parser.parse(toml)
        XCTAssertEqual(result["name"], .string("hello"))
        XCTAssertEqual(result["count"], .integer(42))
    }

    // TEST 6: Empty table name throws invalidTableHeader.
    //
    // Reason: parseTableHeader checks for empty name after stripping brackets.
    func testEmptyTableNameThrowsError() {
        let toml = "[]\nkey = 1"
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.invalidTableHeader = error else {
                XCTFail("Expected invalidTableHeader, got \(error)")
                return
            }
        }
    }

    // TEST 7: Empty value (key = <nothing>) throws invalidValue.
    //
    // Reason: parseValue checks for empty raw string first.
    func testEmptyValueThrowsError() {
        // Build string without a trailing newline so trimmingCharacters strips nothing.
        let toml = "key = "
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.invalidValue = error else {
                XCTFail("Expected invalidValue, got \(error)")
                return
            }
        }
    }

    // TEST 8: Duplicate key within a table section throws duplicateKey.
    //
    // Reason: Covers the second branch of the duplicate-key check
    // (inside a named table, not at root level).
    func testDuplicateKeyInsideTableSectionThrowsError() {
        let toml = """
        [server]
        host = "first"
        host = "second"
        """
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.duplicateKey(let key, _) = error else {
                XCTFail("Expected duplicateKey, got \(error)")
                return
            }
            XCTAssertEqual(key, "host")
        }
    }
}

// MARK: - T2: ControlCharacterMapper Full A-Z Range

/// Verifies the entire Ctrl+A through Ctrl+Z range programmatically.
/// The existing tests only spot-check a handful of letters. This covers all 26.
final class ControlCharacterMapperFullRangeTests: XCTestCase {

    // TEST 9: Ctrl+a-z produces sequential 0x01-0x1A (lowercase).
    func testAllLowercaseLettersProduceCorrectControlCharacters() {
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        for (index, char) in lowercase.enumerated() {
            let expected = UInt8(index + 1) // 0x01 for 'a', 0x02 for 'b', ...
            let result = ControlCharacterMapper.controlCharacter(forLetter: String(char))
            XCTAssertEqual(
                result,
                expected,
                "Ctrl+\(char.uppercased()) must produce 0x\(String(expected, radix: 16))"
            )
        }
    }

    // TEST 10: Ctrl+A-Z produces sequential 0x01-0x1A (uppercase input).
    func testAllUppercaseLettersProduceCorrectControlCharacters() {
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for (index, char) in uppercase.enumerated() {
            let expected = UInt8(index + 1)
            let result = ControlCharacterMapper.controlCharacter(forLetter: String(char))
            XCTAssertEqual(
                result,
                expected,
                "Ctrl+\(char) (uppercase) must produce 0x\(String(expected, radix: 16))"
            )
        }
    }

    // TEST 11: String with multiple characters returns nil.
    //
    // Reason: The guard `letter.count == 1` should catch this.
    func testMultiCharacterStringReturnsNil() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "ab")
        XCTAssertNil(result, "Multi-character string must return nil")
    }

    // TEST 12: controlCharacterText for Ctrl+Z produces a single-byte string (0x1A).
    //
    // Reason: String(Unicode.Scalar(byte)) is the text representation path.
    // Ctrl+Z is the highest code point (0x1A) so is the most important to verify.
    func testControlCharacterTextForCtrlZIsOneByte() {
        let text = ControlCharacterMapper.controlCharacterText(forLetter: "z")
        XCTAssertNotNil(text, "Ctrl+Z must produce a text representation")
        XCTAssertEqual(text?.utf8.count, 1, "Control character text must be exactly 1 byte")
        XCTAssertEqual(text?.utf8.first, 0x1A, "Ctrl+Z must be 0x1A (SUB)")
    }
}

// MARK: - T3: ResizeOverlayState Edge Cases

/// Covers combinations not tested: zero dimensions, re-show without hide,
/// updated displayString after re-show, UInt16 boundary values.
final class ResizeOverlayEdgeCaseTests: XCTestCase {

    // TEST 13: displayString when columns and rows are zero (initial defaults).
    func testDisplayStringWithZeroDimensions() {
        let overlay = ResizeOverlayState()
        // Default columns/rows are 0. displayString is independent of isVisible.
        XCTAssertEqual(
            overlay.displayString, "0x0",
            "Display string for zero dimensions must be '0x0'"
        )
    }

    // TEST 14: Re-show updates columns and rows.
    func testResizeOverlayReShowUpdatesDimensions() {
        var overlay = ResizeOverlayState()
        overlay.show(columns: 80, rows: 24)
        overlay.show(columns: 160, rows: 48)

        XCTAssertEqual(overlay.columns, 160, "Re-show must update columns")
        XCTAssertEqual(overlay.rows, 48, "Re-show must update rows")
        XCTAssertTrue(overlay.isVisible, "Overlay must remain visible after re-show")
    }

    // TEST 15: hide() when already hidden is a safe no-op.
    func testHideWhenAlreadyHiddenIsNoOp() {
        var overlay = ResizeOverlayState()
        overlay.hide() // Was never shown.
        XCTAssertFalse(overlay.isVisible, "Hiding an already hidden overlay must not crash")
    }

    // TEST 16: displayString reflects most recent show() call.
    func testDisplayStringUpdatesAfterReShow() {
        var overlay = ResizeOverlayState()
        overlay.show(columns: 80, rows: 24)
        overlay.show(columns: 100, rows: 30)
        XCTAssertEqual(overlay.displayString, "100x30")
    }

    // TEST 17: UInt16 boundary values (maximum terminal dimensions).
    func testDisplayStringWithMaxDimensions() {
        var overlay = ResizeOverlayState()
        overlay.show(columns: UInt16.max, rows: UInt16.max)
        XCTAssertEqual(
            overlay.displayString,
            "\(UInt16.max)x\(UInt16.max)",
            "Display string must handle UInt16.max dimensions"
        )
    }
}

// MARK: - T4: ConfigService Boundary and Integer Path Tests

/// ConfigService.doubleValue() accepts both .float and .integer TOML values.
/// This is a deliberate design decision (font-size = 14 vs font-size = 14.0).
/// We verify the integer path and several boundary / negative input scenarios.
final class ConfigServiceBoundaryTests: XCTestCase {

    // TEST 18: font-size specified as an integer (not float) is accepted.
    //
    // Reason: doubleValue() has a special .integer case. If someone removes it,
    // this test catches the regression immediately.
    func testFontSizeAsIntegerIsParsed() throws {
        let toml = """
        [appearance]
        font-size = 18
        """
        let provider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.fontSize, 18.0,
            "font-size = 18 (integer) must be parsed as 18.0 (double)"
        )
    }

    // TEST 19: Negative scrollback-lines clamps to 0.
    //
    // Reason: max(0, rawScrollback) -- verify the clamping direction.
    // Tested separately from the existing test at -1 to cover -100 as well.
    func testLargeNegativeScrollbackClampsToZero() throws {
        let toml = """
        [terminal]
        scrollback-lines = -100
        """
        let provider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        XCTAssertEqual(
            service.current.terminal.scrollbackLines, 0,
            "Large negative scrollback-lines must clamp to 0"
        )
    }

    // TEST 20: idleTimeoutSeconds = -5 (negative) clamps to minimum of 1.
    func testNegativeIdleTimeoutClampsToOne() throws {
        let toml = """
        [agent-detection]
        idle-timeout-seconds = -5
        """
        let provider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        XCTAssertEqual(
            service.current.agentDetection.idleTimeoutSeconds, 1,
            "Negative idle-timeout-seconds must clamp to minimum of 1"
        )
    }

    // TEST 21: Window-padding of exactly 0.0 is allowed (boundary value).
    //
    // Reason: max(0.0, rawWindowPadding) -- 0.0 should be accepted, not clamped.
    func testWindowPaddingAtZeroIsAllowed() throws {
        let toml = """
        [appearance]
        window-padding = 0.0
        """
        let provider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.windowPadding, 0.0,
            "window-padding = 0 must be allowed"
        )
    }

    // TEST 22: auto-save-interval = 5 (exact minimum boundary) is not further clamped.
    func testAutoSaveIntervalAtMinimumBoundaryIsAllowed() throws {
        let toml = """
        [sessions]
        auto-save-interval = 5
        """
        let provider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        XCTAssertEqual(
            service.current.sessions.autoSaveInterval, 5,
            "auto-save-interval = 5 (minimum boundary) must be accepted as-is"
        )
    }
}

// MARK: - T5: TerminalViewModel Additional State Coverage

/// Covers ViewModel properties not exercised in the existing suite:
/// autoCopyOnSelect default, lastClickCount default, markRunning idempotency.
@MainActor
final class TerminalViewModelEdgeCaseTests: XCTestCase {

    // TEST 23: autoCopyOnSelect defaults to true (macOS terminal convention).
    func testAutoCopyOnSelectDefaultsToTrue() {
        let viewModel = TerminalViewModel()
        XCTAssertTrue(
            viewModel.autoCopyOnSelect,
            "autoCopyOnSelect must default to true per macOS terminal convention"
        )
    }

    // TEST 24: lastClickCount initializes to 0.
    func testLastClickCountInitializesToZero() {
        let viewModel = TerminalViewModel()
        XCTAssertEqual(
            viewModel.lastClickCount, 0,
            "lastClickCount must initialize to 0 before any mouse events"
        )
    }

    // TEST 25: markRunning called twice without a stop in between replaces the surfaceID.
    //
    // Reason: No guard prevents calling markRunning twice. The ViewModel
    // would silently lose the previous surfaceID reference, which could
    // cause resource leaks if the bridge still holds the old surface.
    // This test documents the current behavior so any future change is deliberate.
    func testMarkRunningTwiceReplacesOldSurfaceID() {
        let viewModel = TerminalViewModel()
        let firstID = SurfaceID()
        let secondID = SurfaceID()

        viewModel.markRunning(surfaceID: firstID)
        viewModel.markRunning(surfaceID: secondID)

        XCTAssertEqual(
            viewModel.surfaceID,
            secondID,
            "markRunning called twice must replace surfaceID with the new ID"
        )
        XCTAssertTrue(viewModel.isRunning, "isRunning must still be true after second markRunning")
    }
}
