// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TextCompositionStateTests.swift - Tests for IME text composition state tracking.

import XCTest
@testable import CocxyTerminal

// MARK: - Text Composition State Tests

/// Tests that the IME (Input Method Editor) composition state is tracked correctly.
///
/// IME composition allows input of CJK characters and other complex scripts.
/// During composition, the terminal shows "marked text" (underlined preview)
/// until the user confirms the final character(s).
///
/// States:
/// - Idle: No composition in progress. hasMarkedText = false.
/// - Composing: User is composing. hasMarkedText = true, markedText is set.
/// - Committed: User confirmed the composition. Text is sent to terminal.
final class TextCompositionStateTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateHasNoMarkedText() {
        let state = TextCompositionState()
        XCTAssertFalse(state.hasMarkedText, "Initial state must not have marked text")
    }

    func testInitialMarkedTextIsEmpty() {
        let state = TextCompositionState()
        XCTAssertEqual(state.markedText, "", "Initial marked text must be empty")
    }

    func testInitialSelectedRangeIsZero() {
        let state = TextCompositionState()
        XCTAssertEqual(state.selectedRange, NSRange(location: 0, length: 0),
                       "Initial selected range must be zero-length at position 0")
    }

    // MARK: - Setting Marked Text (IME Composition Start)

    func testSetMarkedTextEnablesHasMarkedText() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertTrue(state.hasMarkedText, "Setting marked text must enable hasMarkedText")
    }

    func testSetMarkedTextStoresText() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(state.markedText, "ni", "Marked text must be stored")
    }

    func testSetMarkedTextStoresSelectedRange() {
        var state = TextCompositionState()
        let range = NSRange(location: 2, length: 0)
        state.setMarkedText("ni", selectedRange: range)
        XCTAssertEqual(state.selectedRange, range, "Selected range must be stored")
    }

    // MARK: - Updating Marked Text (IME Composition Update)

    func testUpdateMarkedTextReplacesExisting() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.setMarkedText("nih", selectedRange: NSRange(location: 3, length: 0))
        XCTAssertEqual(state.markedText, "nih", "Updated marked text must replace previous")
    }

    // MARK: - Unmarking Text (IME Composition Cancel)

    func testUnmarkTextClearsMarkedState() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.unmarkText()
        XCTAssertFalse(state.hasMarkedText, "Unmarking must clear hasMarkedText")
    }

    func testUnmarkTextClearsMarkedText() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.unmarkText()
        XCTAssertEqual(state.markedText, "", "Unmarking must clear marked text")
    }

    // MARK: - Marked Range

    func testMarkedRangeWhenNoMarkedText() {
        let state = TextCompositionState()
        XCTAssertEqual(state.markedRange, NSRange(location: NSNotFound, length: 0),
                       "Marked range with no marked text must be NSNotFound")
    }

    func testMarkedRangeWhenHasMarkedText() {
        var state = TextCompositionState()
        state.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0))
        let range = state.markedRange
        XCTAssertEqual(range.location, 0, "Marked range location must be 0")
        XCTAssertEqual(range.length, 5, "Marked range length must match text length")
    }

    // MARK: - Commit

    func testCommitClearsCompositionState() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.commit()
        XCTAssertFalse(state.hasMarkedText, "Commit must clear composition state")
        XCTAssertEqual(state.markedText, "", "Commit must clear marked text")
    }

    // MARK: - Empty Marked Text

    func testSetEmptyMarkedTextIsEquivalentToUnmark() {
        var state = TextCompositionState()
        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        XCTAssertFalse(state.hasMarkedText, "Empty marked text must be equivalent to unmark")
    }
}
