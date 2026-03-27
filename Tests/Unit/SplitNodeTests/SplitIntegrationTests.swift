// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitIntegrationTests.swift - Tests for SplitManager-TabManager integration
// and focus indicator behavior.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Split Integration Tests

/// Tests for the integration between SplitManager and TabManager,
/// focus indicators, and keyboard shortcut dispatch.
///
/// Covers:
/// - Each tab having its own SplitManager via TabSplitCoordinator.
/// - Split state isolated per tab.
/// - Focus indicator updates on directional navigation.
/// - SplitKeyboardAction dispatch through SplitManager.
/// - Closing a split via keyboard action.
@MainActor
final class SplitIntegrationTests: XCTestCase {

    // MARK: - TabSplitCoordinator: Per-Tab SplitManager

    func testCoordinatorCreatesDefaultSplitManagerForNewTab() {
        let coordinator = TabSplitCoordinator()
        let tabID = TabID()

        let splitManager = coordinator.splitManager(for: tabID)

        XCTAssertEqual(splitManager.rootNode.leafCount, 1,
                        "A new tab's SplitManager should start with a single leaf")
    }

    func testCoordinatorReturnsSameSplitManagerForSameTab() {
        let coordinator = TabSplitCoordinator()
        let tabID = TabID()

        let first = coordinator.splitManager(for: tabID)
        let second = coordinator.splitManager(for: tabID)

        XCTAssertTrue(first === second,
                       "Same tab ID should return the same SplitManager instance")
    }

    func testCoordinatorReturnsDifferentSplitManagersForDifferentTabs() {
        let coordinator = TabSplitCoordinator()
        let tabID1 = TabID()
        let tabID2 = TabID()

        let manager1 = coordinator.splitManager(for: tabID1)
        let manager2 = coordinator.splitManager(for: tabID2)

        XCTAssertTrue(manager1 !== manager2,
                       "Different tab IDs should return different SplitManagers")
    }

    func testCoordinatorSplitStateIsIsolatedPerTab() {
        let coordinator = TabSplitCoordinator()
        let tabID1 = TabID()
        let tabID2 = TabID()

        let manager1 = coordinator.splitManager(for: tabID1)
        let manager2 = coordinator.splitManager(for: tabID2)

        // Split tab 1 but not tab 2.
        _ = manager1.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager1.rootNode.leafCount, 2,
                        "Tab 1 should have 2 leaves after splitting")
        XCTAssertEqual(manager2.rootNode.leafCount, 1,
                        "Tab 2 should still have 1 leaf (unaffected)")
    }

    func testCoordinatorRemovesSplitManagerWhenTabClosed() {
        let coordinator = TabSplitCoordinator()
        let tabID = TabID()

        // Create and use a SplitManager.
        let manager = coordinator.splitManager(for: tabID)
        _ = manager.splitFocused(direction: .horizontal)

        // Remove it.
        coordinator.removeSplitManager(for: tabID)

        // Getting a SplitManager for the same tab ID should create a new one.
        let newManager = coordinator.splitManager(for: tabID)
        XCTAssertEqual(newManager.rootNode.leafCount, 1,
                        "After removal, a new SplitManager should be created")
        XCTAssertTrue(manager !== newManager,
                       "After removal, a different instance should be returned")
    }

    // MARK: - Focus Indicator: Published Property Updates

    func testFocusedLeafIDPublishesOnDirectionalNavigation() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        var receivedFocusIDs: [UUID?] = []
        let cancellable = manager.$focusedLeafID
            .sink { receivedFocusIDs.append($0) }

        manager.navigateInDirection(.left)

        // Initial value + after navigate.
        XCTAssertGreaterThanOrEqual(receivedFocusIDs.count, 2,
                                     "focusedLeafID should publish when navigating")

        cancellable.cancel()
    }

    // MARK: - SplitKeyboardAction Dispatch

    func testHandleSplitActionSplitHorizontal() {
        let manager = SplitManager()

        manager.handleSplitAction(.splitHorizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 2,
                        "splitHorizontal action should split the focused pane")
    }

    func testHandleSplitActionSplitVertical() {
        let manager = SplitManager()

        manager.handleSplitAction(.splitVertical)

        XCTAssertEqual(manager.rootNode.leafCount, 2,
                        "splitVertical action should split the focused pane")
    }

    func testHandleSplitActionNavigateLeft() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        let allLeaves = manager.rootNode.allLeafIDs()
        let firstLeafID = allLeaves[0].leafID

        // Focus is on the second (right) leaf. Navigate left.
        manager.handleSplitAction(.navigateLeft)

        XCTAssertEqual(manager.focusedLeafID, firstLeafID)
    }

    func testHandleSplitActionNavigateRight() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        let allLeaves = manager.rootNode.allLeafIDs()
        let firstLeafID = allLeaves[0].leafID
        let secondLeafID = allLeaves[1].leafID

        // Move focus to the first leaf, then navigate right.
        manager.focusLeaf(id: firstLeafID)
        manager.handleSplitAction(.navigateRight)

        XCTAssertEqual(manager.focusedLeafID, secondLeafID)
    }

    func testHandleSplitActionNavigateUp() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .vertical)

        let allLeaves = manager.rootNode.allLeafIDs()
        let topLeafID = allLeaves[0].leafID

        // Focus is on the bottom leaf. Navigate up.
        manager.handleSplitAction(.navigateUp)

        XCTAssertEqual(manager.focusedLeafID, topLeafID)
    }

    func testHandleSplitActionNavigateDown() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .vertical)

        let allLeaves = manager.rootNode.allLeafIDs()
        let topLeafID = allLeaves[0].leafID
        let bottomLeafID = allLeaves[1].leafID

        // Move focus to top, then navigate down.
        manager.focusLeaf(id: topLeafID)
        manager.handleSplitAction(.navigateDown)

        XCTAssertEqual(manager.focusedLeafID, bottomLeafID)
    }

    func testHandleSplitActionCloseActiveSplit() {
        let manager = SplitManager()
        _ = manager.splitFocused(direction: .horizontal)

        XCTAssertEqual(manager.rootNode.leafCount, 2)

        manager.handleSplitAction(.closeActiveSplit)

        XCTAssertEqual(manager.rootNode.leafCount, 1,
                        "closeActiveSplit should close the focused pane")
    }

    func testHandleSplitActionCloseActiveSplitWithSinglePaneIsNoOp() {
        let manager = SplitManager()

        manager.handleSplitAction(.closeActiveSplit)

        XCTAssertEqual(manager.rootNode.leafCount, 1,
                        "Cannot close the only pane")
    }

    // MARK: - Focus Border State

    func testSplitContainerFocusedLeafIDDidSet() {
        // Verify that SplitContainer's focusedLeafID property can be set.
        // (The visual rendering is tested visually; here we verify state.)
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())
        let container = SplitContainer(
            node: node,
            terminalViewProvider: { _ in NSView() }
        )

        container.focusedLeafID = leafID

        XCTAssertEqual(container.focusedLeafID, leafID)
    }
}
