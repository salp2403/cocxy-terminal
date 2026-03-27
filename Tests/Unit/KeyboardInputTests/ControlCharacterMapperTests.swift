// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ControlCharacterMapperTests.swift - Tests for Ctrl+key to control character mapping.

import XCTest
@testable import CocxyTerminal

// MARK: - Control Character Mapper Tests

/// Tests that Ctrl+letter combinations produce the correct ASCII control characters.
///
/// Control characters are fundamental to terminal interaction:
/// - Ctrl+C (ETX, 0x03) sends interrupt signal (SIGINT)
/// - Ctrl+D (EOT, 0x04) sends end-of-file
/// - Ctrl+Z (SUB, 0x1A) sends suspend signal (SIGTSTP)
///
/// The mapping follows the standard ASCII control character convention:
/// Ctrl+A = 0x01, Ctrl+B = 0x02, ..., Ctrl+Z = 0x1A
final class ControlCharacterMapperTests: XCTestCase {

    // MARK: - Signal Control Characters

    func testCtrlCProducesETX() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "c")
        XCTAssertEqual(result, 0x03, "Ctrl+C must produce ETX (0x03) for interrupt")
    }

    func testCtrlDProducesEOT() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "d")
        XCTAssertEqual(result, 0x04, "Ctrl+D must produce EOT (0x04) for EOF")
    }

    func testCtrlZProducesSUB() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "z")
        XCTAssertEqual(result, 0x1A, "Ctrl+Z must produce SUB (0x1A) for suspend")
    }

    // MARK: - Line Editing Control Characters

    func testCtrlAProducesSOH() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "a")
        XCTAssertEqual(result, 0x01, "Ctrl+A must produce SOH (0x01) for beginning of line")
    }

    func testCtrlEProducesENQ() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "e")
        XCTAssertEqual(result, 0x05, "Ctrl+E must produce ENQ (0x05) for end of line")
    }

    func testCtrlLProducesFF() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "l")
        XCTAssertEqual(result, 0x0C, "Ctrl+L must produce FF (0x0C) for clear screen")
    }

    // MARK: - Uppercase Letters Produce Same Result

    func testCtrlUppercaseCProducesETX() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "C")
        XCTAssertEqual(result, 0x03, "Ctrl+C (uppercase) must also produce ETX (0x03)")
    }

    func testCtrlUppercaseAProducesSOH() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "A")
        XCTAssertEqual(result, 0x01, "Ctrl+A (uppercase) must also produce SOH (0x01)")
    }

    // MARK: - Full Range A-Z

    func testCtrlBProducesSTX() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "b")
        XCTAssertEqual(result, 0x02, "Ctrl+B must produce STX (0x02)")
    }

    func testCtrlKProducesVT() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "k")
        XCTAssertEqual(result, 0x0B, "Ctrl+K must produce VT (0x0B)")
    }

    func testCtrlRProducesDC2() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "r")
        XCTAssertEqual(result, 0x12, "Ctrl+R must produce DC2 (0x12) for reverse search")
    }

    // MARK: - Non-Letter Characters Return Nil

    func testNonLetterReturnsNil() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "1")
        XCTAssertNil(result, "Non-letter character must return nil")
    }

    func testEmptyStringReturnsNil() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "")
        XCTAssertNil(result, "Empty string must return nil")
    }

    func testSpecialCharacterReturnsNil() {
        let result = ControlCharacterMapper.controlCharacter(forLetter: "@")
        XCTAssertNil(result, "Special character must return nil")
    }

    // MARK: - Text Representation

    func testControlCharacterTextForCtrlC() {
        let text = ControlCharacterMapper.controlCharacterText(forLetter: "c")
        XCTAssertNotNil(text, "Ctrl+C must produce a text representation")
        XCTAssertEqual(text?.utf8.count, 1, "Control character text must be 1 byte")
        XCTAssertEqual(text?.utf8.first, 0x03, "Text must contain ETX byte")
    }

    func testControlCharacterTextForNonLetter() {
        let text = ControlCharacterMapper.controlCharacterText(forLetter: "1")
        XCTAssertNil(text, "Non-letter must not produce control character text")
    }
}
