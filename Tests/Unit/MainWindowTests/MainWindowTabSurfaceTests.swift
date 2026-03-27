// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowTabSurfaceTests.swift - Tests for tab-to-surface mapping (multi-tab fix).

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Tab Surface Mapping Tests

/// Tests that MainWindowController correctly maps each tab to its own terminal surface.
///
/// These tests verify:
/// 1. The initial tab is registered in the surface mapping.
/// 2. Creating a new tab creates a new surface and stores the mapping.
/// 3. Switching tabs changes the visible terminal surface view.
/// 4. Closing a tab destroys its surface and removes the mapping.
@MainActor
final class TabSurfaceMappingTests: XCTestCase {

    // MARK: - Initial Tab Registration

    func testInitialTabHasSurfaceViewMapping() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        // The first tab should already have a surface view in the mapping.
        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab on creation")
            return
        }

        XCTAssertNotNil(
            controller.surfaceViewForTab(firstTabID),
            "The initial tab must have a registered surface view"
        )
    }

    func testInitialTabSurfaceViewIsTheCurrentTerminalSurface() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab on creation")
            return
        }

        let mappedSurfaceView = controller.surfaceViewForTab(firstTabID)
        XCTAssertTrue(
            mappedSurfaceView === controller.terminalSurfaceView,
            "The initial tab's surface view must be the active terminal surface view"
        )
    }

    func testInitialTabHasViewModelMapping() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab on creation")
            return
        }

        XCTAssertNotNil(
            controller.viewModelForTab(firstTabID),
            "The initial tab must have a registered ViewModel"
        )
    }

    // MARK: - New Tab Creates Surface

    func testNewTabActionCreatesSurfaceViewMapping() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        let tabCountBefore = controller.tabManager.tabs.count
        controller.newTabAction(nil)
        let tabCountAfter = controller.tabManager.tabs.count

        XCTAssertEqual(
            tabCountAfter,
            tabCountBefore + 1,
            "newTabAction must create a new tab"
        )

        guard let newTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        XCTAssertNotNil(
            controller.surfaceViewForTab(newTabID),
            "The new tab must have a registered surface view"
        )
    }

    func testNewTabActionCreatesDistinctSurfaceView() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        controller.newTabAction(nil)

        guard let secondTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }
        let secondSurfaceView = controller.surfaceViewForTab(secondTabID)

        XCTAssertFalse(
            firstSurfaceView === secondSurfaceView,
            "Each tab must have its own distinct TerminalSurfaceView"
        )
    }

    func testNewTabActionCreatesViewModel() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.newTabAction(nil)

        guard let newTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        XCTAssertNotNil(
            controller.viewModelForTab(newTabID),
            "The new tab must have a registered ViewModel"
        )
    }

    // MARK: - Tab Switching Changes Terminal View

    func testSwitchingTabChangesActiveTerminalSurfaceView() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        controller.newTabAction(nil)
        guard let secondTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        // Now switch back to the first tab.
        controller.tabManager.setActive(id: firstTabID)
        // Give Combine time to propagate (synchronous on main actor).
        controller.handleTabSwitch(to: firstTabID)

        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "After switching to a tab, the terminal surface view must be that tab's surface"
        )
    }

    func testSwitchingTabUpdatesContainerSubview() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        // Create a second tab.
        controller.newTabAction(nil)
        guard let secondTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }
        let secondSurfaceView = controller.surfaceViewForTab(secondTabID)

        // The second tab's surface view should be in the container.
        XCTAssertTrue(
            controller.terminalSurfaceView === secondSurfaceView,
            "After creating a new tab, the active surface must be the new tab's surface"
        )
    }

    // MARK: - Close Tab Cleanup

    func testCloseTabRemovesSurfaceViewMapping() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        // Create second tab so we can close one.
        controller.newTabAction(nil)
        guard let secondTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        // Close the second tab.
        controller.closeTabAction(nil)

        XCTAssertNil(
            controller.surfaceViewForTab(secondTabID),
            "After closing a tab, its surface view mapping must be removed"
        )
    }

    func testCloseTabRemovesViewModelMapping() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.newTabAction(nil)
        guard let secondTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        controller.closeTabAction(nil)

        XCTAssertNil(
            controller.viewModelForTab(secondTabID),
            "After closing a tab, its ViewModel mapping must be removed"
        )
    }

    func testCloseTabSwitchesToRemainingTab() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        controller.newTabAction(nil)
        controller.closeTabAction(nil)

        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "After closing the active tab, the remaining tab's surface must become active"
        )
    }

    // MARK: - Tab Count Consistency

    func testSurfaceViewCountMatchesTabCount() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        // Start with 1 tab = 1 surface mapping.
        XCTAssertEqual(controller.surfaceViewCount, 1)

        controller.newTabAction(nil)
        XCTAssertEqual(controller.surfaceViewCount, 2)

        controller.newTabAction(nil)
        XCTAssertEqual(controller.surfaceViewCount, 3)

        controller.closeTabAction(nil)
        XCTAssertEqual(controller.surfaceViewCount, 2)
    }
}

// MARK: - Tab Navigation Surface Switching Tests

/// Tests that tab navigation actions (Cmd+Shift+]/[, Cmd+1-9) correctly switch the terminal surface.
@MainActor
final class TabNavigationSurfaceSwitchTests: XCTestCase {

    func testNextTabActionSwitchesTerminalSurface() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        controller.newTabAction(nil)
        guard let secondTabID = controller.tabManager.activeTabID else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }
        let secondSurfaceView = controller.surfaceViewForTab(secondTabID)

        // Switch back to first via nextTab (wraps around with 2 tabs).
        controller.nextTabAction(nil)
        controller.handleTabSwitch(to: controller.tabManager.activeTabID!)

        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "nextTabAction must switch the terminal surface to the next tab's surface"
        )
    }

    func testPreviousTabActionSwitchesTerminalSurface() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        controller.newTabAction(nil)

        // Switch to previous (first tab).
        controller.previousTabAction(nil)
        controller.handleTabSwitch(to: controller.tabManager.activeTabID!)

        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)
        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "previousTabAction must switch the terminal surface to the previous tab's surface"
        )
    }

    func testGotoTabBySelectorSwitchesTerminalSurface() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        // Create a second tab (now active).
        controller.newTabAction(nil)

        // Go to tab 1 (index 0).
        controller.gotoTab1(nil)
        controller.handleTabSwitch(to: controller.tabManager.activeTabID!)

        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "gotoTab1 must switch the terminal surface to the first tab's surface"
        )
    }
}
