// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RecursiveSplitTests.swift - Tests for recursive split pane support.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Recursive Split Tests

/// Tests for recursive split pane support in `SplitManager`.
///
/// Verifies that:
/// - First split creates 2 panes (baseline).
/// - Second split on the focused pane creates 3 panes.
/// - Third split creates 4 panes (maximum).
/// - Fourth split attempt is rejected (max 4 panes enforced).
/// - Closing a pane in a 3-pane layout leaves 2 panes.
/// - Navigation works across 3+ panes.
@MainActor
final class RecursiveSplitTests: XCTestCase {

    // MARK: - Recursive Splitting

    func testFirstSplitCreatesTwo() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 2)
    }

    func testSecondSplitCreatesThree() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        // Focus is on the new pane. Split it again.
        _ = manager.splitFocused(direction: .vertical)

        XCTAssertEqual(manager.rootNode.leafCount, 3)
    }

    func testThirdSplitCreatesFour() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)
        // Navigate to a different pane and split it.
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)
        _ = manager.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 4)
    }

    func testMaxFourPanesEnforced() {
        let manager = SplitManager()

        // Create 4 panes.
        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)
        _ = manager.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 4)

        // Try to create a 5th -- should stay at 4 because tree depth is limited.
        _ = manager.splitFocused(direction: .vertical)

        XCTAssertLessThanOrEqual(manager.rootNode.leafCount, 4,
                                  "Must not exceed 4 panes")
    }

    // MARK: - Close In Recursive Layout

    func testCloseInThreePaneLayoutLeavesTwo() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)

        XCTAssertEqual(manager.rootNode.leafCount, 3)

        manager.closeFocused()

        XCTAssertEqual(manager.rootNode.leafCount, 2)
    }

    func testCloseInFourPaneLayoutLeavesThree() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)
        let firstLeaf = manager.rootNode.allLeafIDs().first!
        manager.focusLeaf(id: firstLeaf.leafID)
        _ = manager.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 4)

        manager.closeFocused()

        XCTAssertEqual(manager.rootNode.leafCount, 3)
    }

    // MARK: - Navigation Across 3+ Panes

    func testNavigationCyclesThroughAllPanesInThreePaneLayout() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)

        let allLeafIDs = manager.rootNode.allLeafIDs().map { $0.leafID }
        XCTAssertEqual(allLeafIDs.count, 3)

        var visitedIDs: Set<UUID> = [manager.focusedLeafID!]

        // Navigate through all panes.
        for _ in 0..<3 {
            manager.navigateToNextLeaf()
            visitedIDs.insert(manager.focusedLeafID!)
        }

        XCTAssertEqual(visitedIDs.count, 3,
                       "Navigation should visit all 3 panes")
    }

    // MARK: - SplitNode Model Supports Recursion

    func testSplitNodeTreeDepthAfterThreeSplits() {
        let manager = SplitManager()

        _ = manager.splitFocused(direction: .horizontal)
        _ = manager.splitFocused(direction: .vertical)

        // Root is a split containing a leaf and another split.
        XCTAssertEqual(manager.rootNode.depth, 2,
                       "Three panes should produce a tree of depth 2")
    }
}
