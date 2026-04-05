// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitManagerTests.swift - Tests for the SplitManager state service.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - SplitManager Tests

/// Tests for `SplitManager` covering state management for split panes.
///
/// Covers:
/// - Initial state is a single leaf.
/// - Splitting the focused pane horizontally.
/// - Splitting the focused pane vertically.
/// - Closing the focused pane with 2 panes.
/// - Closing with 1 pane (no-op).
/// - Navigation between panes.
/// - Multiple splits (3-4 panes).
/// - Focus tracking after split and close operations.
@MainActor
final class SplitManagerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsSingleLeaf() {
        let manager = SplitManager()

        XCTAssertEqual(manager.rootNode.leafCount, 1)
        XCTAssertNotNil(manager.focusedLeafID)
    }

    func testInitialFocusedLeafMatchesRootLeaf() {
        let manager = SplitManager()

        let leafIDs = manager.rootNode.allLeafIDs()
        XCTAssertEqual(leafIDs.count, 1)
        XCTAssertEqual(manager.focusedLeafID, leafIDs[0].leafID)
    }

    // MARK: - Split Focused Horizontal

    func testSplitFocusedHorizontalCreatesTwoLeaves() {
        let manager = SplitManager()

        let newTerminalID = manager.splitFocused(direction: .horizontal)

        XCTAssertNotNil(newTerminalID, "splitFocused should succeed when under max pane count")
        XCTAssertEqual(manager.rootNode.leafCount, 2)
        let terminalIDs = manager.rootNode.allLeafIDs().map { $0.terminalID }
        XCTAssertTrue(terminalIDs.contains(newTerminalID!))
    }

    func testSplitFocusedHorizontalChangesFocusToNewPane() {
        let manager = SplitManager()
        let originalFocused = manager.focusedLeafID

        _ = manager.splitFocused(direction: .horizontal)

        // Focus should move to the new leaf.
        XCTAssertNotEqual(manager.focusedLeafID, originalFocused)
    }

    func testSplitFocusedHorizontalDirectionIsCorrect() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)

        if case .split(_, let direction, _, _, _) = manager.rootNode {
            XCTAssertEqual(direction, .horizontal)
        } else {
            XCTFail("Expected root to be a split after splitting")
        }
    }

    // MARK: - Split Focused Vertical

    func testSplitFocusedVerticalCreatesTwoLeaves() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .vertical)

        XCTAssertEqual(manager.rootNode.leafCount, 2)
    }

    func testSplitFocusedVerticalDirectionIsCorrect() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .vertical)

        if case .split(_, let direction, _, _, _) = manager.rootNode {
            XCTAssertEqual(direction, .vertical)
        } else {
            XCTFail("Expected root to be a split after splitting")
        }
    }

    // MARK: - Close Focused With 2 Panes

    func testCloseFocusedWithTwoPanesReducesToOne() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 2)

        manager.closeFocused()

        XCTAssertEqual(manager.rootNode.leafCount, 1)
    }

    func testCloseFocusedWithTwoPanesUpdatesFocus() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        manager.closeFocused()

        // Focus should be on the remaining leaf.
        let remainingLeafID = manager.rootNode.allLeafIDs().first!.leafID
        XCTAssertEqual(manager.focusedLeafID, remainingLeafID)
    }

    // MARK: - Close Focused With 1 Pane (No-op)

    func testCloseFocusedWithSinglePaneIsNoOp() {
        let manager = SplitManager()
        let originalLeafCount = manager.rootNode.leafCount
        let originalFocused = manager.focusedLeafID

        manager.closeFocused()

        XCTAssertEqual(manager.rootNode.leafCount, originalLeafCount)
        XCTAssertEqual(manager.focusedLeafID, originalFocused)
    }

    // MARK: - Navigation

    func testNavigateToNextLeaf() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        let allLeafIDs = manager.rootNode.allLeafIDs().map { $0.leafID }
        XCTAssertEqual(allLeafIDs.count, 2)

        // Focus is on the new (second) leaf. Navigate to get back to first.
        let currentFocused = manager.focusedLeafID!
        manager.navigateToNextLeaf()

        XCTAssertNotEqual(manager.focusedLeafID, currentFocused,
                          "Navigation should change focus to a different leaf")
    }

    func testNavigateToPreviousLeaf() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        let currentFocused = manager.focusedLeafID!
        manager.navigateToPreviousLeaf()

        XCTAssertNotEqual(manager.focusedLeafID, currentFocused,
                          "Navigation should change focus to a different leaf")
    }

    func testNavigateWithSinglePaneIsNoOp() {
        let manager = SplitManager()
        let originalFocused = manager.focusedLeafID

        manager.navigateToNextLeaf()

        XCTAssertEqual(manager.focusedLeafID, originalFocused)
    }

    func testNavigateWrapsAround() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        let currentFocused = manager.focusedLeafID!

        // Navigate twice (with 2 panes) should return to original.
        manager.navigateToNextLeaf()
        manager.navigateToNextLeaf()

        XCTAssertEqual(manager.focusedLeafID, currentFocused,
                        "Navigating forward twice with 2 panes should wrap around")
    }

    // MARK: - Multiple Splits

    func testThreePanesAfterTwoSplits() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)

        XCTAssertEqual(manager.rootNode.leafCount, 3)
    }

    func testFourPanesAfterThreeSplits() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        // Focus is on second pane, split vertically.
        _ = manager.splitFocused(direction: .vertical)
        // Navigate back to first pane and split it too.
        // First, navigate to a different leaf.
        let firstLeafID = manager.rootNode.allLeafIDs().first!.leafID
        manager.focusLeaf(id: firstLeafID)
        _ = manager.splitFocused(direction: .vertical)

        XCTAssertEqual(manager.rootNode.leafCount, 4)
    }

    // MARK: - Set Ratio

    func testSetRatioUpdatesNode() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        // Get the split ID (root should be a split now).
        if case .split(let splitID, _, _, _, _) = manager.rootNode {
            manager.setRatio(splitID: splitID, ratio: 0.3)

            if case .split(_, _, _, _, let ratio) = manager.rootNode {
                XCTAssertEqual(ratio, 0.3, accuracy: 0.001)
            } else {
                XCTFail("Root should still be a split")
            }
        } else {
            XCTFail("Root should be a split after splitting")
        }
    }

    // MARK: - Focus Tracking

    func testFocusLeafByID() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        let firstLeafID = manager.rootNode.allLeafIDs().first!.leafID
        manager.focusLeaf(id: firstLeafID)

        XCTAssertEqual(manager.focusedLeafID, firstLeafID)
    }

    func testFocusLeafWithInvalidIDIsNoOp() {
        let manager = SplitManager()
        let originalFocused = manager.focusedLeafID

        manager.focusLeaf(id: UUID()) // Non-existent ID

        XCTAssertEqual(manager.focusedLeafID, originalFocused)
    }

    // MARK: - Published Properties

    func testRootNodeIsPublished() {
        let manager = SplitManager()
        var receivedValues: [SplitNode] = []

        let cancellable = manager.$rootNode
            .sink { receivedValues.append($0) }

        _ = manager.splitFocused(direction: .horizontal)

        // Should have received the initial value + the updated value.
        XCTAssertGreaterThanOrEqual(receivedValues.count, 2)

        cancellable.cancel()
    }

    func testFocusedLeafIDIsPublished() {
        let manager = SplitManager()
        var receivedValues: [UUID?] = []

        let cancellable = manager.$focusedLeafID
            .sink { receivedValues.append($0) }

        _ = manager.splitFocused(direction: .horizontal)

        // Should have received the initial value + the updated value.
        XCTAssertGreaterThanOrEqual(receivedValues.count, 2)

        cancellable.cancel()
    }
}
