// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyKeyConverterExtendedTests.swift - Extended tests for key conversion.

import XCTest
import GhosttyKit
@testable import CocxyTerminal

// MARK: - Function Key Conversion Tests

/// Tests that F1-F12 and beyond map correctly to ghostty key enums.
final class FunctionKeyConversionTests: XCTestCase {

    func testF2MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x78)
        XCTAssertEqual(key, GHOSTTY_KEY_F2, "macOS keyCode 0x78 must map to F2")
    }

    func testF3MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x63)
        XCTAssertEqual(key, GHOSTTY_KEY_F3, "macOS keyCode 0x63 must map to F3")
    }

    func testF4MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x76)
        XCTAssertEqual(key, GHOSTTY_KEY_F4, "macOS keyCode 0x76 must map to F4")
    }

    func testF5MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x60)
        XCTAssertEqual(key, GHOSTTY_KEY_F5, "macOS keyCode 0x60 must map to F5")
    }

    func testF6MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x61)
        XCTAssertEqual(key, GHOSTTY_KEY_F6, "macOS keyCode 0x61 must map to F6")
    }

    func testF7MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x62)
        XCTAssertEqual(key, GHOSTTY_KEY_F7, "macOS keyCode 0x62 must map to F7")
    }

    func testF8MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x64)
        XCTAssertEqual(key, GHOSTTY_KEY_F8, "macOS keyCode 0x64 must map to F8")
    }

    func testF9MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x65)
        XCTAssertEqual(key, GHOSTTY_KEY_F9, "macOS keyCode 0x65 must map to F9")
    }

    func testF10MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x6D)
        XCTAssertEqual(key, GHOSTTY_KEY_F10, "macOS keyCode 0x6D must map to F10")
    }

    func testF11MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x67)
        XCTAssertEqual(key, GHOSTTY_KEY_F11, "macOS keyCode 0x67 must map to F11")
    }

    func testF12MapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x6F)
        XCTAssertEqual(key, GHOSTTY_KEY_F12, "macOS keyCode 0x6F must map to F12")
    }
}

// MARK: - Navigation Key Conversion Tests

/// Tests that Home, End, PageUp, PageDown, and Delete map correctly.
final class NavigationKeyConversionTests: XCTestCase {

    func testHomeMapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x73)
        XCTAssertEqual(key, GHOSTTY_KEY_HOME, "macOS keyCode 0x73 must map to Home")
    }

    func testEndMapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x77)
        XCTAssertEqual(key, GHOSTTY_KEY_END, "macOS keyCode 0x77 must map to End")
    }

    func testPageUpMapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x74)
        XCTAssertEqual(key, GHOSTTY_KEY_PAGE_UP, "macOS keyCode 0x74 must map to PageUp")
    }

    func testPageDownMapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x79)
        XCTAssertEqual(key, GHOSTTY_KEY_PAGE_DOWN, "macOS keyCode 0x79 must map to PageDown")
    }

    func testForwardDeleteMapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x75)
        XCTAssertEqual(key, GHOSTTY_KEY_DELETE, "macOS keyCode 0x75 must map to Delete (forward)")
    }

    func testBackspaceMapsCorrectly() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x33)
        XCTAssertEqual(key, GHOSTTY_KEY_BACKSPACE, "macOS keyCode 0x33 must map to Backspace")
    }
}

// MARK: - Key Repeat Action Tests

/// Tests that key repeat events produce the correct ghostty action.
final class KeyRepeatActionTests: XCTestCase {

    func testKeyRepeatProducesRepeatAction() {
        let event = KeyEvent(
            characters: "a",
            keyCode: 0x00,
            modifiers: KeyModifiers(),
            isKeyDown: true,
            isRepeat: true
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertEqual(
            ghosttyEvent.action,
            GHOSTTY_ACTION_REPEAT,
            "isRepeat=true must map to GHOSTTY_ACTION_REPEAT"
        )
    }

    func testNonRepeatKeyDownProducesPressAction() {
        let event = KeyEvent(
            characters: "a",
            keyCode: 0x00,
            modifiers: KeyModifiers(),
            isKeyDown: true,
            isRepeat: false
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertEqual(
            ghosttyEvent.action,
            GHOSTTY_ACTION_PRESS,
            "isRepeat=false with isKeyDown=true must map to GHOSTTY_ACTION_PRESS"
        )
    }
}

// MARK: - Composing Key Event Tests

/// Tests that composing flag is correctly passed to ghostty.
final class ComposingKeyEventTests: XCTestCase {

    func testComposingFlagPassedToGhosttyEvent() {
        let event = KeyEvent(
            characters: "ni",
            keyCode: 0x00,
            modifiers: KeyModifiers(),
            isKeyDown: true,
            isRepeat: false,
            isComposing: true
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertTrue(
            ghosttyEvent.composing,
            "isComposing=true must set composing=true on ghostty event"
        )
    }

    func testNonComposingEventHasComposingFalse() {
        let event = KeyEvent(
            characters: "a",
            keyCode: 0x00,
            modifiers: KeyModifiers(),
            isKeyDown: true,
            isRepeat: false,
            isComposing: false
        )
        let ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)
        XCTAssertFalse(
            ghosttyEvent.composing,
            "isComposing=false must set composing=false on ghostty event"
        )
    }
}
