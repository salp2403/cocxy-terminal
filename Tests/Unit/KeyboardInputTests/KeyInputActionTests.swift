// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeyInputActionTests.swift - Tests for keyboard action classification.

import XCTest
@testable import CocxyTerminal

// MARK: - Key Input Action Classification Tests

/// Tests that keyboard combinations are classified into the correct action type.
///
/// The action classifier determines what happens when a key is pressed:
/// - Terminal input: characters and control sequences sent to the PTY
/// - Application commands: copy, paste, select all, clear screen
/// - Passthrough: events forwarded to libghostty without interception
final class KeyInputActionTests: XCTestCase {

    // MARK: - Cmd+C = Copy (not Ctrl+C)

    func testCmdCClassifiesAsCopy() {
        let action = KeyInputAction.classify(
            keyCode: 0x08,  // 'c' key
            modifiers: .command,
            characters: "c"
        )
        XCTAssertEqual(action, .copy, "Cmd+C must classify as copy")
    }

    // MARK: - Cmd+V = Paste

    func testCmdVClassifiesAsPaste() {
        let action = KeyInputAction.classify(
            keyCode: 0x09,  // 'v' key
            modifiers: .command,
            characters: "v"
        )
        XCTAssertEqual(action, .paste, "Cmd+V must classify as paste")
    }

    // MARK: - Cmd+A = Select All

    func testCmdAClassifiesAsSelectAll() {
        let action = KeyInputAction.classify(
            keyCode: 0x00,  // 'a' key
            modifiers: .command,
            characters: "a"
        )
        XCTAssertEqual(action, .selectAll, "Cmd+A must classify as select all")
    }

    // MARK: - Cmd+K = Clear Screen

    func testCmdKClassifiesAsClearScreen() {
        let action = KeyInputAction.classify(
            keyCode: 0x28,  // 'k' key
            modifiers: .command,
            characters: "k"
        )
        XCTAssertEqual(action, .clearScreen, "Cmd+K must classify as clear screen")
    }

    // MARK: - Ctrl+C = Send to Terminal (not application copy)

    func testCtrlCClassifiesAsTerminalInput() {
        let action = KeyInputAction.classify(
            keyCode: 0x08,  // 'c' key
            modifiers: .control,
            characters: "\u{03}"
        )
        XCTAssertEqual(action, .sendToTerminal, "Ctrl+C must be sent to terminal as control char")
    }

    // MARK: - Regular Characters = Send to Terminal

    func testRegularCharacterClassifiesAsSendToTerminal() {
        let action = KeyInputAction.classify(
            keyCode: 0x00,  // 'a' key
            modifiers: KeyModifiers(),
            characters: "a"
        )
        XCTAssertEqual(action, .sendToTerminal, "Regular characters must be sent to terminal")
    }

    // MARK: - Option+Key = Send to Terminal (for tmux/vim)

    func testOptionKeyClassifiesAsSendToTerminal() {
        let action = KeyInputAction.classify(
            keyCode: 0x00,  // 'a' key
            modifiers: .option,
            characters: "a"
        )
        XCTAssertEqual(action, .sendToTerminal, "Option+key must be sent to terminal")
    }

    // MARK: - Cmd+Shift combinations do not interfere

    func testCmdShiftCDoesNotClassifyAsCopy() {
        let action = KeyInputAction.classify(
            keyCode: 0x08,  // 'c' key
            modifiers: [.command, .shift],
            characters: "C"
        )
        // Cmd+Shift+C is not a recognized app shortcut, should pass through
        XCTAssertEqual(action, .sendToTerminal,
                       "Cmd+Shift+C must not be classified as copy (it might be a different shortcut)")
    }
}

// MARK: - KeyInputAction Equatable Tests

/// Tests that KeyInputAction enum cases are properly equatable.
final class KeyInputActionEquatableTests: XCTestCase {

    func testCopyEqualsCopy() {
        XCTAssertEqual(KeyInputAction.copy, KeyInputAction.copy)
    }

    func testCopyDoesNotEqualPaste() {
        XCTAssertNotEqual(KeyInputAction.copy, KeyInputAction.paste)
    }

    func testSendToTerminalEqualsSendToTerminal() {
        XCTAssertEqual(KeyInputAction.sendToTerminal, KeyInputAction.sendToTerminal)
    }
}
