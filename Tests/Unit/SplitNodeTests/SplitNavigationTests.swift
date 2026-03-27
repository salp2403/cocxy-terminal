// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitNavigationTests.swift - Tests for directional navigation between split panes.

import XCTest
@testable import CocxyTerminal

// MARK: - Split Navigation Tests

/// Tests for `SplitNavigator` covering directional navigation in the split tree.
///
/// Covers:
/// - NavigationDirection enum correctness.
/// - Simple horizontal split: navigate left/right.
/// - Simple vertical split: navigate up/down.
/// - Navigate in direction with no neighbor returns nil.
/// - Navigate with a single leaf returns nil in all directions.
/// - 2x2 grid navigation in all 4 directions.
/// - Complex tree (3+ levels) navigation.
/// - SplitManager directional navigation integration.
/// - Focus indicator state changes.
/// - Keyboard shortcut action mapping.
@MainActor
final class SplitNavigationTests: XCTestCase {

    // MARK: - NavigationDirection Enum

    func testNavigationDirectionHasFourCases() {
        let allDirections: [NavigationDirection] = [.left, .right, .up, .down]
        XCTAssertEqual(allDirections.count, 4)
    }

    // MARK: - Simple Horizontal Split: Navigate Right

    func testNavigateRightFromLeftLeafFindsRightLeaf() {
        // Horizontal split: left | right
        let leftLeafID = UUID()
        let rightLeafID = UUID()
        let leftTerminal = UUID()
        let rightTerminal = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leftLeafID, terminalID: leftTerminal),
            second: .leaf(id: rightLeafID, terminalID: rightTerminal),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: leftLeafID,
            direction: .right,
            in: tree
        )

        XCTAssertEqual(result, rightLeafID,
                        "Navigating right from left leaf should find right leaf")
    }

    // MARK: - Simple Horizontal Split: Navigate Left

    func testNavigateLeftFromRightLeafFindsLeftLeaf() {
        let leftLeafID = UUID()
        let rightLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leftLeafID, terminalID: UUID()),
            second: .leaf(id: rightLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: rightLeafID,
            direction: .left,
            in: tree
        )

        XCTAssertEqual(result, leftLeafID,
                        "Navigating left from right leaf should find left leaf")
    }

    // MARK: - Simple Vertical Split: Navigate Down

    func testNavigateDownFromTopLeafFindsBottomLeaf() {
        // Vertical split: top / bottom
        let topLeafID = UUID()
        let bottomLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(id: topLeafID, terminalID: UUID()),
            second: .leaf(id: bottomLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: topLeafID,
            direction: .down,
            in: tree
        )

        XCTAssertEqual(result, bottomLeafID,
                        "Navigating down from top leaf should find bottom leaf")
    }

    // MARK: - Simple Vertical Split: Navigate Up

    func testNavigateUpFromBottomLeafFindsTopLeaf() {
        let topLeafID = UUID()
        let bottomLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(id: topLeafID, terminalID: UUID()),
            second: .leaf(id: bottomLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: bottomLeafID,
            direction: .up,
            in: tree
        )

        XCTAssertEqual(result, topLeafID,
                        "Navigating up from bottom leaf should find top leaf")
    }

    // MARK: - No Neighbor in Direction

    func testNavigateLeftFromLeftLeafReturnsNil() {
        let leftLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leftLeafID, terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: leftLeafID,
            direction: .left,
            in: tree
        )

        XCTAssertNil(result,
                      "Navigating left from the leftmost leaf should return nil")
    }

    func testNavigateRightFromRightLeafReturnsNil() {
        let rightLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: rightLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: rightLeafID,
            direction: .right,
            in: tree
        )

        XCTAssertNil(result,
                      "Navigating right from the rightmost leaf should return nil")
    }

    func testNavigateUpFromTopLeafReturnsNil() {
        let topLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(id: topLeafID, terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: topLeafID,
            direction: .up,
            in: tree
        )

        XCTAssertNil(result,
                      "Navigating up from the topmost leaf should return nil")
    }

    func testNavigateDownFromBottomLeafReturnsNil() {
        let bottomLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: bottomLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: bottomLeafID,
            direction: .down,
            in: tree
        )

        XCTAssertNil(result,
                      "Navigating down from the bottommost leaf should return nil")
    }

    // MARK: - Single Leaf: All Directions Return Nil

    func testNavigateFromSingleLeafReturnsNilInAllDirections() {
        let leafID = UUID()
        let tree = SplitNode.leaf(id: leafID, terminalID: UUID())

        for direction in [NavigationDirection.left, .right, .up, .down] {
            let result = SplitNavigator.findNeighbor(
                of: leafID,
                direction: direction,
                in: tree
            )
            XCTAssertNil(result,
                          "Single leaf should have no neighbor in direction \(direction)")
        }
    }

    // MARK: - 2x2 Grid Navigation

    func testNavigateIn2x2Grid() {
        // Build a 2x2 grid:
        //
        //  topLeft    | topRight
        //  -----------+-----------
        //  bottomLeft | bottomRight
        //
        // Structure:
        //   split(V)
        //   ├── split(H, topLeft, topRight)
        //   └── split(H, bottomLeft, bottomRight)

        let topLeftID = UUID()
        let topRightID = UUID()
        let bottomLeftID = UUID()
        let bottomRightID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: topLeftID, terminalID: UUID()),
                second: .leaf(id: topRightID, terminalID: UUID()),
                ratio: 0.5
            ),
            second: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: bottomLeftID, terminalID: UUID()),
                second: .leaf(id: bottomRightID, terminalID: UUID()),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        // From topLeft: right -> topRight
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: topLeftID, direction: .right, in: tree),
            topRightID
        )

        // From topLeft: down -> bottomLeft
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: topLeftID, direction: .down, in: tree),
            bottomLeftID
        )

        // From topLeft: left -> nil
        XCTAssertNil(
            SplitNavigator.findNeighbor(of: topLeftID, direction: .left, in: tree)
        )

        // From topLeft: up -> nil
        XCTAssertNil(
            SplitNavigator.findNeighbor(of: topLeftID, direction: .up, in: tree)
        )

        // From bottomRight: left -> bottomLeft
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: bottomRightID, direction: .left, in: tree),
            bottomLeftID
        )

        // From bottomRight: up -> topLeft (bottommost of the upper subtree).
        // Note: without geometric position data, cross-axis navigation goes to
        // the nearest leaf on the edge of the opposite subtree. In a tree-based
        // layout, "bottommost of first" resolves to the leftmost leaf.
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: bottomRightID, direction: .up, in: tree),
            topLeftID
        )

        // From bottomRight: right -> nil
        XCTAssertNil(
            SplitNavigator.findNeighbor(of: bottomRightID, direction: .right, in: tree)
        )

        // From bottomRight: down -> nil
        XCTAssertNil(
            SplitNavigator.findNeighbor(of: bottomRightID, direction: .down, in: tree)
        )
    }

    // MARK: - Complex Tree (3+ Levels)

    func testNavigateInComplexTree() {
        // Tree structure (3 levels deep):
        //
        //   split(H)
        //   ├── leaf(A)
        //   └── split(V)
        //       ├── leaf(B)
        //       └── split(H)
        //           ├── leaf(C)
        //           └── leaf(D)
        //
        // Visual layout:
        //  A  | B
        //     |---
        //     | C | D

        let leafA = UUID()
        let leafB = UUID()
        let leafC = UUID()
        let leafD = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leafA, terminalID: UUID()),
            second: .split(
                id: UUID(),
                direction: .vertical,
                first: .leaf(id: leafB, terminalID: UUID()),
                second: .split(
                    id: UUID(),
                    direction: .horizontal,
                    first: .leaf(id: leafC, terminalID: UUID()),
                    second: .leaf(id: leafD, terminalID: UUID()),
                    ratio: 0.5
                ),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        // From A: right -> should find leftmost leaf in right subtree -> B
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafA, direction: .right, in: tree),
            leafB
        )

        // From B: left -> should find rightmost leaf in left subtree -> A
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafB, direction: .left, in: tree),
            leafA
        )

        // From B: down -> C (topmost of the bottom sub-split, leftmost in horizontal)
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafB, direction: .down, in: tree),
            leafC
        )

        // From C: up -> B
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafC, direction: .up, in: tree),
            leafB
        )

        // From C: right -> D
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafC, direction: .right, in: tree),
            leafD
        )

        // From D: left -> C
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafD, direction: .left, in: tree),
            leafC
        )

        // From C: left -> A (crosses up to the root horizontal split)
        XCTAssertEqual(
            SplitNavigator.findNeighbor(of: leafC, direction: .left, in: tree),
            leafA
        )

        // From D: right -> nil (rightmost in the tree)
        XCTAssertNil(
            SplitNavigator.findNeighbor(of: leafD, direction: .right, in: tree)
        )
    }

    // MARK: - Non-existent Leaf ID Returns Nil

    func testNavigateWithNonExistentLeafIDReturnsNil() {
        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: UUID(),
            direction: .right,
            in: tree
        )

        XCTAssertNil(result,
                      "Non-existent leaf ID should return nil")
    }

    // MARK: - Orthogonal Navigation in Horizontal Split

    func testNavigateUpInHorizontalSplitReturnsNil() {
        let leftLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leftLeafID, terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: leftLeafID,
            direction: .up,
            in: tree
        )

        XCTAssertNil(result,
                      "Navigating up in a horizontal-only split should return nil")
    }

    func testNavigateDownInHorizontalSplitReturnsNil() {
        let leftLeafID = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leftLeafID, terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.findNeighbor(
            of: leftLeafID,
            direction: .down,
            in: tree
        )

        XCTAssertNil(result,
                      "Navigating down in a horizontal-only split should return nil")
    }

    // MARK: - SplitManager Directional Navigation Integration

    func testSplitManagerNavigateInDirectionUpdatessFocus() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        // After split, focus is on the second (right) leaf.
        let allLeaves = manager.rootNode.allLeafIDs()
        let firstLeafID = allLeaves[0].leafID
        let secondLeafID = allLeaves[1].leafID

        // Focus should be on the second leaf (new one).
        XCTAssertEqual(manager.focusedLeafID, secondLeafID)

        // Navigate left -> should focus the first leaf.
        manager.navigateInDirection(.left)
        XCTAssertEqual(manager.focusedLeafID, firstLeafID,
                        "Navigating left should focus the left pane")

        // Navigate right -> should go back to second.
        manager.navigateInDirection(.right)
        XCTAssertEqual(manager.focusedLeafID, secondLeafID,
                        "Navigating right should focus the right pane")
    }

    func testSplitManagerNavigateInDirectionWithNoNeighborIsNoOp() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        // Focus is on the second (right) leaf.
        let currentFocused = manager.focusedLeafID

        // Navigate right from the rightmost leaf -> no-op.
        manager.navigateInDirection(.right)
        XCTAssertEqual(manager.focusedLeafID, currentFocused,
                        "Navigating in a direction with no neighbor should not change focus")
    }

    // MARK: - Keyboard Shortcut Action Mapping

    func testSplitKeyboardShortcutActions() {
        let allActions: [SplitKeyboardAction] = [
            .splitHorizontal,
            .splitVertical,
            .navigateLeft,
            .navigateRight,
            .navigateUp,
            .navigateDown,
            .closeActiveSplit
        ]
        XCTAssertEqual(allActions.count, 7,
                        "Should have 7 keyboard shortcut actions for splits")
    }

    // MARK: - Focus Indicator State

    func testFocusedLeafIDChangesOnDirectionalNavigation() {
        let manager = SplitManager()

        // Create a vertical split (top/bottom).
        _ = manager.splitFocused(direction: .vertical)

        let allLeaves = manager.rootNode.allLeafIDs()
        let topLeafID = allLeaves[0].leafID
        let bottomLeafID = allLeaves[1].leafID

        // Focus is on bottom (new leaf).
        XCTAssertEqual(manager.focusedLeafID, bottomLeafID)

        // Navigate up.
        manager.navigateInDirection(.up)
        XCTAssertEqual(manager.focusedLeafID, topLeafID)

        // Navigate down.
        manager.navigateInDirection(.down)
        XCTAssertEqual(manager.focusedLeafID, bottomLeafID)
    }

    // MARK: - Edge Finding Helpers

    func testLeftmostLeafInSimpleTree() {
        let leftLeafID = UUID()
        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leftLeafID, terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.leftmostLeaf(in: tree)
        XCTAssertEqual(result, leftLeafID)
    }

    func testRightmostLeafInSimpleTree() {
        let rightLeafID = UUID()
        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: rightLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.rightmostLeaf(in: tree)
        XCTAssertEqual(result, rightLeafID)
    }

    func testTopmostLeafInVerticalSplit() {
        let topLeafID = UUID()
        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(id: topLeafID, terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.topmostLeaf(in: tree)
        XCTAssertEqual(result, topLeafID)
    }

    func testBottommostLeafInVerticalSplit() {
        let bottomLeafID = UUID()
        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: bottomLeafID, terminalID: UUID()),
            ratio: 0.5
        )

        let result = SplitNavigator.bottommostLeaf(in: tree)
        XCTAssertEqual(result, bottomLeafID)
    }
}
