// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitNodeTests.swift - Tests for the SplitNode binary tree data structure.

import XCTest
@testable import CocxyTerminal

// MARK: - SplitNode Tests

/// Tests for `SplitNode` covering tree operations, constraints, and traversal.
///
/// Covers:
/// - Leaf creation and identity.
/// - Splitting a leaf into two children.
/// - Recursive splitting (2x2 grid).
/// - Removing a leaf and promoting its sibling.
/// - Removing the last leaf returns nil.
/// - DFS traversal order of leaf IDs.
/// - Leaf count computation.
/// - Depth limit enforcement.
/// - Ratio clamping (< 0.1 -> 0.1, > 0.9 -> 0.9).
/// - Ratio update on a split node.
/// - Finding a leaf by ID.
/// - Equatable conformance.
final class SplitNodeTests: XCTestCase {

    // MARK: - Leaf Creation

    func testLeafCreationHasCorrectID() {
        let leafID = UUID()
        let terminalID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: terminalID)

        XCTAssertEqual(node.id, leafID)
    }

    func testLeafCreationHasCorrectTerminalID() {
        let leafID = UUID()
        let terminalID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: terminalID)

        if case .leaf(_, let tid) = node {
            XCTAssertEqual(tid, terminalID)
        } else {
            XCTFail("Expected leaf node")
        }
    }

    func testLeafCountIsOne() {
        let node = SplitNode.leaf(id: UUID(), terminalID: UUID())
        XCTAssertEqual(node.leafCount, 1)
    }

    func testLeafDepthIsZero() {
        let node = SplitNode.leaf(id: UUID(), terminalID: UUID())
        XCTAssertEqual(node.depth, 0)
    }

    // MARK: - Split a Leaf

    func testSplitLeafCreatesNodeWithTwoLeaves() {
        let leafID = UUID()
        let terminalID = UUID()
        let newTerminalID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: terminalID)

        let result = node.splitLeaf(
            leafID: leafID,
            direction: .horizontal,
            newTerminalID: newTerminalID
        )

        XCTAssertNotNil(result)
        if case .split(_, let direction, let first, let second, let ratio) = result! {
            XCTAssertEqual(direction, .horizontal)
            XCTAssertEqual(ratio, 0.5)

            // First child retains the original terminal ID.
            if case .leaf(_, let tid) = first {
                XCTAssertEqual(tid, terminalID)
            } else {
                XCTFail("Expected first child to be a leaf")
            }

            // Second child has the new terminal ID.
            if case .leaf(_, let tid) = second {
                XCTAssertEqual(tid, newTerminalID)
            } else {
                XCTFail("Expected second child to be a leaf")
            }
        } else {
            XCTFail("Expected split node")
        }
    }

    func testSplitLeafVerticalDirection() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())

        let result = node.splitLeaf(
            leafID: leafID,
            direction: .vertical,
            newTerminalID: UUID()
        )

        if case .split(_, let direction, _, _, _) = result! {
            XCTAssertEqual(direction, .vertical)
        } else {
            XCTFail("Expected split node with vertical direction")
        }
    }

    func testSplitLeafWithNonExistentIDReturnsNil() {
        let node = SplitNode.leaf(id: UUID(), terminalID: UUID())
        let result = node.splitLeaf(
            leafID: UUID(), // Non-existent ID
            direction: .horizontal,
            newTerminalID: UUID()
        )

        XCTAssertNil(result)
    }

    func testSplitLeafIncrementsLeafCount() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())

        let result = node.splitLeaf(
            leafID: leafID,
            direction: .horizontal,
            newTerminalID: UUID()
        )!

        XCTAssertEqual(result.leafCount, 2)
    }

    // MARK: - Recursive Split (2x2 Grid)

    func testDoubleSplitCreatesFourLeaves() {
        // Start with a single leaf, split it, then split one of the children.
        let leafID = UUID()
        let t1 = UUID()
        let t2 = UUID()
        let t3 = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: t1)

        // First split: horizontal
        let afterFirstSplit = node.splitLeaf(
            leafID: leafID,
            direction: .horizontal,
            newTerminalID: t2
        )!

        // Get the ID of the second leaf (t2) to split it.
        let secondLeafID = afterFirstSplit.allLeafIDs().last!.leafID

        // Second split: vertical on the second leaf
        let afterSecondSplit = afterFirstSplit.splitLeaf(
            leafID: secondLeafID,
            direction: .vertical,
            newTerminalID: t3
        )!

        XCTAssertEqual(afterSecondSplit.leafCount, 3)

        // Split the first leaf too for a true 2x2 grid.
        let firstLeafID = afterSecondSplit.allLeafIDs().first!.leafID

        let t4 = UUID()
        let grid = afterSecondSplit.splitLeaf(
            leafID: firstLeafID,
            direction: .vertical,
            newTerminalID: t4
        )!

        XCTAssertEqual(grid.leafCount, 4)
    }

    // MARK: - Remove Leaf

    func testRemoveLeafFromSplitPromotesSibling() {
        let leafID1 = UUID()
        let leafID2 = UUID()
        let t1 = UUID()
        let t2 = UUID()

        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leafID1, terminalID: t1),
            second: .leaf(id: leafID2, terminalID: t2),
            ratio: 0.5
        )

        let result = node.removeLeaf(leafID: leafID1)

        XCTAssertNotNil(result)
        if case .leaf(_, let tid) = result! {
            XCTAssertEqual(tid, t2, "Removing first leaf should promote second")
        } else {
            XCTFail("Expected remaining node to be a leaf")
        }
    }

    func testRemoveSecondLeafFromSplitPromotesFirst() {
        let leafID1 = UUID()
        let leafID2 = UUID()
        let t1 = UUID()
        let t2 = UUID()

        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: leafID1, terminalID: t1),
            second: .leaf(id: leafID2, terminalID: t2),
            ratio: 0.5
        )

        let result = node.removeLeaf(leafID: leafID2)

        XCTAssertNotNil(result)
        if case .leaf(_, let tid) = result! {
            XCTAssertEqual(tid, t1, "Removing second leaf should promote first")
        } else {
            XCTFail("Expected remaining node to be a leaf")
        }
    }

    func testRemoveLastLeafReturnsNil() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())

        let result = node.removeLeaf(leafID: leafID)

        XCTAssertNil(result, "Removing the only leaf should return nil")
    }

    func testRemoveNonExistentLeafReturnsSelf() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())

        // Removing a non-existent leaf from a single leaf should return the leaf unchanged.
        let result = node.removeLeaf(leafID: UUID())

        // Since the leafID doesn't match, the tree is unchanged.
        // For a single leaf with no match, it stays as is.
        XCTAssertNotNil(result)
    }

    // MARK: - allLeafIDs (DFS Order)

    func testAllLeafIDsSingleLeaf() {
        let terminalID = UUID()
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: terminalID)

        let ids = node.allLeafIDs()

        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids[0].terminalID, terminalID)
    }

    func testAllLeafIDsDFSOrder() {
        let t1 = UUID()
        let t2 = UUID()
        let t3 = UUID()

        // Build tree:
        //     split(H)
        //    /        \
        //  leaf(t1)  split(V)
        //            /      \
        //          leaf(t2) leaf(t3)

        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: t1),
            second: .split(
                id: UUID(),
                direction: .vertical,
                first: .leaf(id: UUID(), terminalID: t2),
                second: .leaf(id: UUID(), terminalID: t3),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let ids = node.allLeafIDs()

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids[0].terminalID, t1)
        XCTAssertEqual(ids[1].terminalID, t2)
        XCTAssertEqual(ids[2].terminalID, t3)
    }

    // MARK: - Leaf Count

    func testLeafCountThreeLeaves() {
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .split(
                id: UUID(),
                direction: .vertical,
                first: .leaf(id: UUID(), terminalID: UUID()),
                second: .leaf(id: UUID(), terminalID: UUID()),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        XCTAssertEqual(node.leafCount, 3)
    }

    // MARK: - Depth

    func testDepthOfSingleSplit() {
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        XCTAssertEqual(node.depth, 1)
    }

    func testDepthOfNestedSplit() {
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .split(
                id: UUID(),
                direction: .vertical,
                first: .leaf(id: UUID(), terminalID: UUID()),
                second: .leaf(id: UUID(), terminalID: UUID()),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        XCTAssertEqual(node.depth, 2)
    }

    // MARK: - Depth Limit

    func testSplitRespectsMaxDepthLimit() {
        // Build a tree at maximum depth (4 levels) and try to split further.
        // Max depth = 4 means we can have splits up to depth 4.
        var node = SplitNode.leaf(id: UUID(), terminalID: UUID())

        // Split 4 times to reach depth 4.
        for _ in 0..<4 {
            let leafID = node.allLeafIDs().last!.leafID
            guard let split = node.splitLeaf(
                leafID: leafID,
                direction: .horizontal,
                newTerminalID: UUID()
            ) else {
                break
            }
            node = split
        }

        // Now the deepest leaf should be at depth 4.
        XCTAssertEqual(node.depth, 4)

        // Trying to split the deepest leaf should return nil (depth limit).
        let deepestLeafID = node.allLeafIDs().last!.leafID
        let result = node.splitLeaf(
            leafID: deepestLeafID,
            direction: .horizontal,
            newTerminalID: UUID(),
            maxDepth: 4
        )

        XCTAssertNil(result, "Should not allow splitting beyond max depth of 4")
    }

    // MARK: - Ratio Clamping

    func testClampedSplitClampsBelowMinimum() {
        let node = SplitNode.clampedSplit(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.05 // Below minimum 0.1
        )

        // Verify the ratio is clamped to 0.1.
        if case .split(_, _, _, _, let ratio) = node {
            XCTAssertEqual(ratio, 0.1, accuracy: 0.001)
        } else {
            XCTFail("Expected split node")
        }
    }

    func testClampedSplitClampsAboveMaximum() {
        let node = SplitNode.clampedSplit(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.95 // Above maximum 0.9
        )

        if case .split(_, _, _, _, let ratio) = node {
            XCTAssertEqual(ratio, 0.9, accuracy: 0.001)
        } else {
            XCTFail("Expected split node")
        }
    }

    func testClampedSplitWithinRangeUnchanged() {
        let node = SplitNode.clampedSplit(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.6
        )

        if case .split(_, _, _, _, let ratio) = node {
            XCTAssertEqual(ratio, 0.6, accuracy: 0.001)
        } else {
            XCTFail("Expected split node")
        }
    }

    func testClampRatioStaticMethod() {
        XCTAssertEqual(SplitNode.clampRatio(0.0), 0.1, accuracy: 0.001)
        XCTAssertEqual(SplitNode.clampRatio(0.05), 0.1, accuracy: 0.001)
        XCTAssertEqual(SplitNode.clampRatio(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(SplitNode.clampRatio(0.95), 0.9, accuracy: 0.001)
        XCTAssertEqual(SplitNode.clampRatio(1.0), 0.9, accuracy: 0.001)
    }

    // MARK: - Update Ratio

    func testUpdateRatioOnExistingSplit() {
        let splitID = UUID()
        let node = SplitNode.split(
            id: splitID,
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let updated = node.updateRatio(splitID: splitID, ratio: 0.7)

        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, 0.7, accuracy: 0.001)
        } else {
            XCTFail("Expected split node")
        }
    }

    func testUpdateRatioOnNonExistentSplitReturnsSelf() {
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let updated = node.updateRatio(splitID: UUID(), ratio: 0.7)

        // Should be unchanged.
        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
        } else {
            XCTFail("Expected split node")
        }
    }

    func testUpdateRatioClamps() {
        let splitID = UUID()
        let node = SplitNode.split(
            id: splitID,
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )

        let updated = node.updateRatio(splitID: splitID, ratio: 1.5)

        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, 0.9, accuracy: 0.001)
        } else {
            XCTFail("Expected split node")
        }
    }

    // MARK: - Find Leaf

    func testFindLeafExisting() {
        let targetID = UUID()
        let targetTerminalID = UUID()

        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: targetID, terminalID: targetTerminalID),
            ratio: 0.5
        )

        let found = node.findLeaf(id: targetID)
        XCTAssertNotNil(found)
        if case .leaf(let id, let tid) = found! {
            XCTAssertEqual(id, targetID)
            XCTAssertEqual(tid, targetTerminalID)
        } else {
            XCTFail("Expected leaf")
        }
    }

    func testFindLeafNonExistent() {
        let node = SplitNode.leaf(id: UUID(), terminalID: UUID())
        let found = node.findLeaf(id: UUID())
        XCTAssertNil(found)
    }

    // MARK: - Equatable

    func testEquatableIdenticalLeaves() {
        let id = UUID()
        let tid = UUID()
        let node1 = SplitNode.leaf(id: id, terminalID: tid)
        let node2 = SplitNode.leaf(id: id, terminalID: tid)

        XCTAssertEqual(node1, node2)
    }

    func testEquatableDifferentLeaves() {
        let node1 = SplitNode.leaf(id: UUID(), terminalID: UUID())
        let node2 = SplitNode.leaf(id: UUID(), terminalID: UUID())

        XCTAssertNotEqual(node1, node2)
    }

    func testEquatableIdenticalSplits() {
        let splitID = UUID()
        let leaf1ID = UUID()
        let leaf2ID = UUID()
        let t1 = UUID()
        let t2 = UUID()

        let node1 = SplitNode.split(
            id: splitID,
            direction: .horizontal,
            first: .leaf(id: leaf1ID, terminalID: t1),
            second: .leaf(id: leaf2ID, terminalID: t2),
            ratio: 0.5
        )
        let node2 = SplitNode.split(
            id: splitID,
            direction: .horizontal,
            first: .leaf(id: leaf1ID, terminalID: t1),
            second: .leaf(id: leaf2ID, terminalID: t2),
            ratio: 0.5
        )

        XCTAssertEqual(node1, node2)
    }

    func testEquatableDifferentDirections() {
        let splitID = UUID()
        let leaf1ID = UUID()
        let leaf2ID = UUID()
        let t1 = UUID()
        let t2 = UUID()

        let node1 = SplitNode.split(
            id: splitID,
            direction: .horizontal,
            first: .leaf(id: leaf1ID, terminalID: t1),
            second: .leaf(id: leaf2ID, terminalID: t2),
            ratio: 0.5
        )
        let node2 = SplitNode.split(
            id: splitID,
            direction: .vertical,
            first: .leaf(id: leaf1ID, terminalID: t1),
            second: .leaf(id: leaf2ID, terminalID: t2),
            ratio: 0.5
        )

        XCTAssertNotEqual(node1, node2)
    }

    // MARK: - Identifiable

    func testIdentifiableLeafReturnsCorrectID() {
        let id = UUID()
        let node = SplitNode.leaf(id: id, terminalID: UUID())
        XCTAssertEqual(node.id, id)
    }

    func testIdentifiableSplitReturnsCorrectID() {
        let id = UUID()
        let node = SplitNode.split(
            id: id,
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .leaf(id: UUID(), terminalID: UUID()),
            ratio: 0.5
        )
        XCTAssertEqual(node.id, id)
    }

    // MARK: - Remove Leaf from Nested Tree

    func testRemoveLeafFromNestedTreePreservesStructure() {
        let leafToRemove = UUID()
        let t1 = UUID()
        let t2 = UUID()
        let t3 = UUID()

        // Tree:
        //     split(H)
        //    /         \
        //  leaf(t1)   split(V)
        //            /        \
        //         leaf(t2)  leaf(t3) <-- remove this

        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: t1),
            second: .split(
                id: UUID(),
                direction: .vertical,
                first: .leaf(id: UUID(), terminalID: t2),
                second: .leaf(id: leafToRemove, terminalID: t3),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let result = node.removeLeaf(leafID: leafToRemove)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.leafCount, 2,
                        "After removing one leaf from 3, should have 2")

        let ids = result!.allLeafIDs().map { $0.terminalID }
        XCTAssertTrue(ids.contains(t1))
        XCTAssertTrue(ids.contains(t2))
        XCTAssertFalse(ids.contains(t3))
    }
}
