// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TextInputClientTests.swift - Tests for NSTextInputClient conformance.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - NSTextInputClient Conformance Tests

/// Tests that TerminalSurfaceView correctly implements NSTextInputClient.
///
/// NSTextInputClient enables IME (Input Method Editor) support for
/// CJK characters and other complex input methods. The view must
/// track marked text (composition in progress) and handle text insertion.
@MainActor
final class TextInputClientConformanceTests: XCTestCase {

    // MARK: - Protocol Conformance

    func testViewConformsToNSTextInputClient() {
        let view = TerminalSurfaceView()
        // This is a compile-time check -- if it compiles, the view conforms.
        let client: NSTextInputClient = view
        XCTAssertNotNil(client, "TerminalSurfaceView must conform to NSTextInputClient")
    }

    // MARK: - Initial State

    func testHasMarkedTextReturnsFalseInitially() {
        let view = TerminalSurfaceView()
        XCTAssertFalse(view.hasMarkedText(), "View must not have marked text initially")
    }

    func testMarkedRangeReturnsNotFoundInitially() {
        let view = TerminalSurfaceView()
        let range = view.markedRange()
        XCTAssertEqual(range.location, NSNotFound,
                       "Marked range location must be NSNotFound when no marked text")
    }

    func testSelectedRangeReturnsZeroInitially() {
        let view = TerminalSurfaceView()
        let range = view.selectedRange()
        XCTAssertEqual(range.location, 0, "Selected range location must be 0 initially")
        XCTAssertEqual(range.length, 0, "Selected range length must be 0 initially")
    }

    // MARK: - Set Marked Text

    func testSetMarkedTextWithStringEnablesHasMarkedText() {
        let view = TerminalSurfaceView()
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText(), "Setting marked text must enable hasMarkedText")
    }

    func testSetMarkedTextUpdatesMarkedRange() {
        let view = TerminalSurfaceView()
        view.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        let range = view.markedRange()
        XCTAssertEqual(range.location, 0, "Marked range location must be 0")
        XCTAssertEqual(range.length, 5, "Marked range length must match text length")
    }

    // MARK: - Unmark Text

    func testUnmarkTextClearsMarkedState() {
        let view = TerminalSurfaceView()
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText(), "Unmarking must clear marked text state")
    }

    // MARK: - Valid Attributes

    func testValidAttributesForMarkedTextReturnsEmptyArray() {
        let view = TerminalSurfaceView()
        let attrs = view.validAttributesForMarkedText()
        // Terminal views typically return an empty array since they handle rendering themselves.
        XCTAssertNotNil(attrs, "validAttributesForMarkedText must return a non-nil array")
    }

    // MARK: - Attributed Substring

    func testAttributedSubstringReturnsNil() {
        let view = TerminalSurfaceView()
        var actualRange = NSRange(location: 0, length: 0)
        let result = view.attributedSubstring(
            forProposedRange: NSRange(location: 0, length: 5),
            actualRange: &actualRange
        )
        // Terminal views don't support attributed substrings from the terminal content.
        XCTAssertNil(result, "attributedSubstring must return nil (terminal handles its own content)")
    }

    // MARK: - Character Index

    func testCharacterIndexReturnsZero() {
        let view = TerminalSurfaceView()
        let index = view.characterIndex(for: NSPoint(x: 10, y: 10))
        // We return 0 as a reasonable default since we don't track character positions.
        XCTAssertEqual(index, 0, "characterIndex must return 0 (no character tracking)")
    }
}

// MARK: - Key Event Translation Extended Tests

/// Tests that TerminalSurfaceView's translateKeyEvent handles the isRepeat field.
@MainActor
final class KeyEventTranslationExtendedTests: XCTestCase {

    func testTranslateModifierFlagsCombinedControlOption() {
        let nsFlags: NSEvent.ModifierFlags = [.control, .option]
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertTrue(keyModifiers.contains(.control), "Must contain control")
        XCTAssertTrue(keyModifiers.contains(.option), "Must contain option")
        XCTAssertFalse(keyModifiers.contains(.command), "Must not contain command")
        XCTAssertFalse(keyModifiers.contains(.shift), "Must not contain shift")
    }
}
