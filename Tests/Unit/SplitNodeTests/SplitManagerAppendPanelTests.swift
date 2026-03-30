// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitManagerAppendPanelTests.swift - Panels must append to the end of the tree.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Split Manager Append Panel Tests

/// Verifies that `appendPanel` always places new panels at the rightmost
/// position of the split tree, regardless of where focus currently is.
///
/// Covers:
/// - appendPanel adds to the end with single leaf.
/// - appendPanel adds to the end when focus is on the first leaf.
/// - appendPanel preserves the original focus after insertion.
/// - appendPanel returns nil when at max pane count.
/// - appendPanel registers the panel type correctly.
@MainActor
final class SplitManagerAppendPanelTests: XCTestCase {

    // MARK: - Append Panel Basics

    func testAppendPanelCreatesSecondLeaf() {
        let manager = SplitManager()

        let contentID = manager.appendPanel(panel: .browser())

        XCTAssertNotNil(contentID,
                        "appendPanel should succeed when under max pane count")
        XCTAssertEqual(manager.rootNode.leafCount, 2,
                       "Tree should have 2 leaves after appending a panel")
    }

    func testAppendPanelPlacesNewLeafAtEnd() {
        let manager = SplitManager()
        // Split to create 2 leaves: [A, B]. Focus on B.
        _ = manager.splitFocused(direction: .horizontal)

        // Focus the first leaf (A).
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)

        // Append a browser panel. It should go at the END, not next to A.
        let browserContentID = manager.appendPanel(panel: .browser())

        XCTAssertNotNil(browserContentID)

        let leaves = manager.rootNode.allLeafIDs()
        XCTAssertEqual(leaves.count, 3,
                       "Tree should have 3 leaves")
        XCTAssertEqual(leaves.last?.terminalID, browserContentID,
                       "New panel must be the rightmost (last) leaf")
    }

    func testAppendPanelPreservesFocus() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        // Focus the first leaf.
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)
        let savedFocus = manager.focusedLeafID

        // Append panel.
        _ = manager.appendPanel(panel: .browser())

        XCTAssertEqual(manager.focusedLeafID, savedFocus,
                       "appendPanel must restore focus to where it was before")
    }

    func testAppendPanelReturnsNilAtMaxPaneCount() {
        let manager = SplitManager()
        // Fill up to maxPaneCount (4 by default).
        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)
        // Navigate to first leaf and split again.
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)
        _ = manager.splitFocused(direction: .vertical)

        XCTAssertEqual(manager.rootNode.leafCount, SplitManager.maxPaneCount)

        let result = manager.appendPanel(panel: .browser())

        XCTAssertNil(result,
                     "appendPanel should return nil when at max pane count")
    }

    func testAppendPanelRegistersPanelType() {
        let manager = SplitManager()

        let contentID = manager.appendPanel(panel: .browser())

        XCTAssertNotNil(contentID)
        XCTAssertEqual(manager.panelType(for: contentID!), .browser,
                       "Panel type should be registered as browser")
    }

    func testAppendPanelFocusNewPanelMoveFocusToNewLeaf() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        // Focus the first leaf.
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)
        let savedFocus = manager.focusedLeafID

        // Append panel with focusNewPanel: true.
        let contentID = manager.appendPanel(panel: .browser(), focusNewPanel: true)

        XCTAssertNotNil(contentID)
        XCTAssertNotEqual(manager.focusedLeafID, savedFocus,
                          "focusNewPanel: true must NOT restore original focus")

        // The focused leaf should be the one backing the new panel.
        let leaves = manager.rootNode.allLeafIDs()
        let newLeaf = leaves.first(where: { $0.terminalID == contentID })
        XCTAssertNotNil(newLeaf)
        XCTAssertEqual(manager.focusedLeafID, newLeaf?.leafID,
                       "Focus must be on the newly appended panel leaf")
    }

    func testAppendTerminalPanelDoesNotRegisterType() {
        let manager = SplitManager()

        let contentID = manager.appendPanel(panel: .terminal)

        XCTAssertNotNil(contentID)
        XCTAssertEqual(manager.panelType(for: contentID!), .terminal,
                       "Terminal panels default to .terminal without explicit registration")
    }
}
