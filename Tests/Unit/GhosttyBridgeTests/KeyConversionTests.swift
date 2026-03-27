// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeyConversionTests.swift - Tests for keyboard event conversion to ghostty types.

import XCTest
import GhosttyKit
@testable import CocxyTerminal

// MARK: - Key Modifier Conversion Tests

/// Tests that verify correct conversion from `KeyModifiers` to `ghostty_input_mods_e`.
///
/// These are pure conversion tests that do not require the ghostty runtime.
/// Each modifier flag must map to the correct ghostty bit position.
final class KeyModifierConversionTests: XCTestCase {

    // MARK: - Individual modifier flags

    func testShiftModifierMapsToGhosttyShift() {
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: .shift)
        XCTAssertEqual(
            ghosttyMods.rawValue & GHOSTTY_MODS_SHIFT.rawValue,
            GHOSTTY_MODS_SHIFT.rawValue,
            "KeyModifiers.shift must map to GHOSTTY_MODS_SHIFT"
        )
    }

    func testControlModifierMapsToGhosttyCtrl() {
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: .control)
        XCTAssertEqual(
            ghosttyMods.rawValue & GHOSTTY_MODS_CTRL.rawValue,
            GHOSTTY_MODS_CTRL.rawValue,
            "KeyModifiers.control must map to GHOSTTY_MODS_CTRL"
        )
    }

    func testOptionModifierMapsToGhosttyAlt() {
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: .option)
        XCTAssertEqual(
            ghosttyMods.rawValue & GHOSTTY_MODS_ALT.rawValue,
            GHOSTTY_MODS_ALT.rawValue,
            "KeyModifiers.option must map to GHOSTTY_MODS_ALT"
        )
    }

    func testCommandModifierMapsToGhosttySuper() {
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: .command)
        XCTAssertEqual(
            ghosttyMods.rawValue & GHOSTTY_MODS_SUPER.rawValue,
            GHOSTTY_MODS_SUPER.rawValue,
            "KeyModifiers.command must map to GHOSTTY_MODS_SUPER"
        )
    }

    // MARK: - No modifiers

    func testEmptyModifiersMapsToNone() {
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: KeyModifiers())
        XCTAssertEqual(
            ghosttyMods.rawValue,
            GHOSTTY_MODS_NONE.rawValue,
            "Empty KeyModifiers must map to GHOSTTY_MODS_NONE"
        )
    }

    // MARK: - Combined modifiers

    func testCombinedShiftControlMapsCorrectly() {
        let combined: KeyModifiers = [.shift, .control]
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: combined)
        let expected = GHOSTTY_MODS_SHIFT.rawValue | GHOSTTY_MODS_CTRL.rawValue
        XCTAssertEqual(
            ghosttyMods.rawValue,
            expected,
            "shift+control must produce SHIFT|CTRL bitmask"
        )
    }

    func testAllModifiersCombined() {
        let allMods: KeyModifiers = [.shift, .control, .option, .command]
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: allMods)
        let expected = GHOSTTY_MODS_SHIFT.rawValue
            | GHOSTTY_MODS_CTRL.rawValue
            | GHOSTTY_MODS_ALT.rawValue
            | GHOSTTY_MODS_SUPER.rawValue
        XCTAssertEqual(
            ghosttyMods.rawValue,
            expected,
            "All four modifiers must produce the correct combined bitmask"
        )
    }
}

// MARK: - Key Event Conversion Tests

/// Tests that verify correct conversion from `KeyEvent` to `ghostty_input_key_s`.
final class KeyEventConversionTests: XCTestCase {

    func testKeyDownActionMapsToPress() {
        let event = KeyEvent(
            characters: "a",
            keyCode: 0, // macOS keyCode for 'a'
            modifiers: KeyModifiers(),
            isKeyDown: true
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertEqual(
            ghosttyEvent.action,
            GHOSTTY_ACTION_PRESS,
            "isKeyDown=true must map to GHOSTTY_ACTION_PRESS"
        )
    }

    func testKeyUpActionMapsToRelease() {
        let event = KeyEvent(
            characters: "a",
            keyCode: 0,
            modifiers: KeyModifiers(),
            isKeyDown: false
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertEqual(
            ghosttyEvent.action,
            GHOSTTY_ACTION_RELEASE,
            "isKeyDown=false must map to GHOSTTY_ACTION_RELEASE"
        )
    }

    func testModifiersAreConverted() {
        let event = KeyEvent(
            characters: nil,
            keyCode: 0,
            modifiers: [.shift, .command],
            isKeyDown: true
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        let expectedMods = GHOSTTY_MODS_SHIFT.rawValue | GHOSTTY_MODS_SUPER.rawValue
        XCTAssertEqual(
            ghosttyEvent.mods.rawValue,
            expectedMods,
            "Modifiers must be correctly converted in the key event"
        )
    }

    func testComposingIsFalseByDefault() {
        let event = KeyEvent(
            characters: "a",
            keyCode: 0,
            modifiers: KeyModifiers(),
            isKeyDown: true
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertFalse(
            ghosttyEvent.composing,
            "composing must be false for normal key events"
        )
    }
}

// MARK: - macOS KeyCode to Ghostty Key Conversion Tests

/// Tests that macOS hardware key codes map to the correct ghostty_input_key_e values.
///
/// Key codes are hardware-level identifiers from the macOS HID layer.
/// They are layout-independent (keyCode 0 is always the 'a' physical key,
/// regardless of whether the user is on QWERTY, AZERTY, or Dvorak).
final class KeyCodeConversionTests: XCTestCase {

    func testKeyCodeForAMapsToGhosttyA() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x00)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_A, "macOS keyCode 0x00 = 'a' key")
    }

    func testKeyCodeForSMapsToGhosttyS() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x01)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_S, "macOS keyCode 0x01 = 's' key")
    }

    func testKeyCodeForReturnMapsToGhosttyEnter() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x24)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_ENTER, "macOS keyCode 0x24 = Return key")
    }

    func testKeyCodeForTabMapsToGhosttyTab() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x30)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_TAB, "macOS keyCode 0x30 = Tab key")
    }

    func testKeyCodeForSpaceMapsToGhosttySpace() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x31)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_SPACE, "macOS keyCode 0x31 = Space key")
    }

    func testKeyCodeForEscapeMapsToGhosttyEscape() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x35)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_ESCAPE, "macOS keyCode 0x35 = Escape key")
    }

    func testKeyCodeForDeleteMapsToGhosttyBackspace() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x33)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_BACKSPACE, "macOS keyCode 0x33 = Delete (Backspace) key")
    }

    func testKeyCodeForArrowUpMapsToGhosttyArrowUp() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x7E)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_ARROW_UP, "macOS keyCode 0x7E = Arrow Up key")
    }

    func testKeyCodeForArrowDownMapsToGhosttyArrowDown() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x7D)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_ARROW_DOWN, "macOS keyCode 0x7D = Arrow Down key")
    }

    func testKeyCodeForArrowLeftMapsToGhosttyArrowLeft() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x7B)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_ARROW_LEFT, "macOS keyCode 0x7B = Arrow Left key")
    }

    func testKeyCodeForArrowRightMapsToGhosttyArrowRight() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x7C)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_ARROW_RIGHT, "macOS keyCode 0x7C = Arrow Right key")
    }

    func testUnknownKeyCodeMapsToUnidentified() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0xFF)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_UNIDENTIFIED, "Unknown keyCode must map to UNIDENTIFIED")
    }

    func testKeyCodeForF1MapsToGhosttyF1() {
        let ghosttyKey = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x7A)
        XCTAssertEqual(ghosttyKey, GHOSTTY_KEY_F1, "macOS keyCode 0x7A = F1 key")
    }
}
