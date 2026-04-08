// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowTabSurfaceTests.swift - Tests for tab-to-surface mapping (multi-tab fix).

import XCTest
import AppKit
@testable import CocxyTerminal

@MainActor
private final class TrackingTerminalHostView: NSView, TerminalHostingView {
    var terminalViewModel: TerminalViewModel?
    var onFileDrop: (([URL]) -> Bool)?
    var onUserInputSubmitted: (() -> Void)?
    private(set) var syncSizeCallCount = 0
    private(set) var redrawCallCount = 0
    private(set) var updateMetricsCallCount = 0

    func syncSizeWithTerminal() {
        syncSizeCallCount += 1
    }

    func showNotificationRing(color: NSColor) {}
    func hideNotificationRing() {}
    func handleShellPrompt(row: Int, column: Int) {}

    func updateInteractionMetrics() {
        updateMetricsCallCount += 1
    }

    func configureSurfaceIfNeeded(
        bridge: any TerminalEngine,
        surfaceID: SurfaceID
    ) {}

    func requestImmediateRedraw() {
        redrawCallCount += 1
    }
}

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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
            "Each tab must have its own distinct terminal host view"
        )
    }

    func testNewTabActionCreatesViewModel() {
        let bridge = MockTerminalEngine()
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

    func testCreateTabUsesCocxyCoreHostViewWhenBridgeIsCocxyCore() {
        let bridge = CocxyCoreBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.createTab()

        guard let newTabID = controller.tabManager.activeTabID else {
            XCTFail("After createTab, there must be an active tab")
            return
        }

        XCTAssertTrue(
            controller.surfaceViewForTab(newTabID) is CocxyCoreView,
            "Tabs created while CocxyCore is active must use CocxyCoreView host views"
        )
    }

    // MARK: - Tab Switching Changes Terminal View

    func testSwitchingTabChangesActiveTerminalHostView() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        controller.newTabAction(nil)
        guard controller.tabManager.activeTabID != nil else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        // Now switch back to the first tab.
        controller.tabManager.setActive(id: firstTabID)
        // Give Combine time to propagate (synchronous on main actor).
        controller.handleTabSwitch(to: firstTabID)

        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "After switching to a tab, the active terminal host view must be that tab's surface"
        )
    }

    func testSwitchingTabUpdatesContainerSubview() {
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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

    // MARK: - Surface Working Directory Tracking

    func testWorkingDirectoryForSurfacePrefersSurfaceScopedDirectory() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        let tabDirectory = URL(fileURLWithPath: "/tmp/tab-root", isDirectory: true)
        let splitDirectory = URL(fileURLWithPath: "/tmp/tab-root/split-pane", isDirectory: true)
        let surfaceID = SurfaceID()

        controller.tabManager.updateTab(id: firstTabID) { tab in
            tab.workingDirectory = tabDirectory
        }
        controller.tabSurfaceMap[firstTabID] = surfaceID
        controller.surfaceWorkingDirectories[surfaceID] = splitDirectory

        XCTAssertEqual(
            controller.workingDirectory(for: surfaceID),
            splitDirectory,
            "Surface-specific CWD tracking must override the tab-level working directory"
        )
    }
}

// MARK: - Tab Navigation Surface Switching Tests

/// Tests that tab navigation actions (Cmd+Shift+]/[, Cmd+1-9) correctly switch the terminal surface.
@MainActor
final class TabNavigationSurfaceSwitchTests: XCTestCase {

    func testNextTabActionSwitchesTerminalSurface() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        let firstSurfaceView = controller.surfaceViewForTab(firstTabID)

        controller.newTabAction(nil)
        guard controller.tabManager.activeTabID != nil else {
            XCTFail("After newTabAction, there must be an active tab")
            return
        }

        // Switch back to first via nextTab (wraps around with 2 tabs).
        controller.nextTabAction(nil)
        controller.handleTabSwitch(to: controller.tabManager.activeTabID!)

        XCTAssertTrue(
            controller.terminalSurfaceView === firstSurfaceView,
            "nextTabAction must switch the terminal surface to the next tab's surface"
        )
    }

    func testPreviousTabActionSwitchesTerminalSurface() {
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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

    func testHandleTabSwitchRefreshesTargetSurfaceAfterReattach() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        controller.terminalContainerView = container

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        let firstView = TrackingTerminalHostView()
        controller.tabSurfaceViews[firstTabID] = firstView
        controller.terminalSurfaceView = firstView
        controller.displayedTabID = firstTabID
        container.addSubview(firstView)

        let secondTab = controller.tabManager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let secondView = TrackingTerminalHostView()
        controller.tabSurfaceViews[secondTab.id] = secondView

        controller.handleTabSwitch(to: secondTab.id)

        XCTAssertEqual(secondView.updateMetricsCallCount, 1)
        XCTAssertEqual(secondView.redrawCallCount, 1)
        XCTAssertTrue(controller.terminalSurfaceView === secondView)
    }

    func testHandleTabSwitchRefreshesAlreadyDisplayedSurface() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        controller.terminalContainerView = container

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        let firstView = TrackingTerminalHostView()
        controller.tabSurfaceViews[firstTabID] = firstView
        controller.terminalSurfaceView = firstView
        controller.displayedTabID = firstTabID
        container.addSubview(firstView)

        controller.handleTabSwitch(to: firstTabID)

        XCTAssertEqual(firstView.updateMetricsCallCount, 1)
        XCTAssertEqual(firstView.redrawCallCount, 1)
    }

    func testHandleTabSwitchReattachesDisplayedSurfaceWhenHierarchyIsMissing() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        controller.terminalContainerView = container

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        let firstView = TrackingTerminalHostView()
        controller.tabSurfaceViews[firstTabID] = firstView
        controller.terminalSurfaceView = firstView
        controller.displayedTabID = firstTabID

        controller.handleTabSwitch(to: firstTabID)

        XCTAssertTrue(
            firstView.superview === container,
            "Re-selecting the displayed tab must repair a detached hierarchy instead of early-returning"
        )
        XCTAssertEqual(firstView.updateMetricsCallCount, 1)
        XCTAssertEqual(firstView.redrawCallCount, 1)
    }

    func testHandleTabSwitchRefreshesRestoredSplitSurfaces() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        controller.terminalContainerView = container

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        let firstView = TrackingTerminalHostView()
        controller.tabSurfaceViews[firstTabID] = firstView
        controller.terminalSurfaceView = firstView
        controller.displayedTabID = firstTabID
        container.addSubview(firstView)

        let splitTab = controller.tabManager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp/split"))
        let primarySplitView = TrackingTerminalHostView()
        let secondarySplitView = TrackingTerminalHostView()
        let secondarySurfaceID = SurfaceID()
        let splitView = NSSplitView(frame: container.bounds)
        splitView.isVertical = true

        controller.tabSurfaceViews[splitTab.id] = primarySplitView
        controller.savedTabSplitViews[splitTab.id] = splitView
        controller.savedTabSplitSurfaceViews[splitTab.id] = [secondarySurfaceID: secondarySplitView]

        controller.handleTabSwitch(to: splitTab.id)

        XCTAssertEqual(primarySplitView.updateMetricsCallCount, 1)
        XCTAssertEqual(primarySplitView.redrawCallCount, 1)
        XCTAssertEqual(secondarySplitView.updateMetricsCallCount, 1)
        XCTAssertEqual(secondarySplitView.redrawCallCount, 1)
        XCTAssertTrue(controller.activeSplitView === splitView)
    }

    func testWindowDidBecomeKeyRefreshesVisibleTerminalSurfaces() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let primaryView = TrackingTerminalHostView()
        let splitView = TrackingTerminalHostView()
        controller.terminalSurfaceView = primaryView
        controller.splitSurfaceViews[SurfaceID()] = splitView

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        XCTAssertEqual(primaryView.updateMetricsCallCount, 1)
        XCTAssertEqual(primaryView.redrawCallCount, 1)
        XCTAssertEqual(splitView.updateMetricsCallCount, 1)
        XCTAssertEqual(splitView.redrawCallCount, 1)
    }

    func testWindowDidBecomeMainRefreshesVisibleTerminalSurfaces() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let primaryView = TrackingTerminalHostView()
        let splitView = TrackingTerminalHostView()
        controller.terminalSurfaceView = primaryView
        controller.splitSurfaceViews[SurfaceID()] = splitView

        controller.windowDidBecomeMain(Notification(name: NSWindow.didBecomeMainNotification))

        XCTAssertEqual(primaryView.updateMetricsCallCount, 1)
        XCTAssertEqual(primaryView.redrawCallCount, 1)
        XCTAssertEqual(splitView.updateMetricsCallCount, 1)
        XCTAssertEqual(splitView.redrawCallCount, 1)
    }

    func testSpawnSubagentPanelDeduplicatesSameSessionAndSubagent() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        controller.injectedDashboardViewModel = AgentDashboardViewModel()

        controller.spawnSubagentPanel(
            subagentId: "sub-1",
            sessionId: "sess-1",
            agentType: "research"
        )
        let initialPanelCount = controller.panelContentViews.count

        controller.spawnSubagentPanel(
            subagentId: "sub-1",
            sessionId: "sess-1",
            agentType: "research"
        )

        XCTAssertEqual(initialPanelCount, 1)
        XCTAssertEqual(
            controller.panelContentViews.count,
            1,
            "Repeated subagent-start events must not create duplicate loading panels"
        )
    }

    func testSpawnSubagentPanelIgnoresGenericSubprocessAgentType() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        controller.injectedDashboardViewModel = AgentDashboardViewModel()

        controller.spawnSubagentPanel(
            subagentId: "pid-123",
            sessionId: "sess-1",
            agentType: "subprocess"
        )

        XCTAssertTrue(
            controller.panelContentViews.isEmpty,
            "Generic subprocess events must not auto-open subagent panels"
        )
    }

    func testCloseSplitActionPromotesRemainingSplitSurfaceToPrimary() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }

        guard let activeTabID = controller.tabManager.activeTabID,
              let originalPrimaryView = controller.terminalSurfaceView,
              let originalPrimarySurfaceID = controller.tabSurfaceMap[activeTabID] else {
            XCTFail("Expected bootstrap tab and primary surface")
            return
        }

        controller.performVisualSplit(isVertical: true)

        guard let splitManager = controller.activeSplitManager else {
            XCTFail("Expected split manager after creating a split")
            return
        }
        let leaves = splitManager.rootNode.allLeafIDs()
        guard leaves.count == 2,
              let (promotedSurfaceID, promotedSurfaceView) = controller.splitSurfaceViews.first else {
            XCTFail("Expected a secondary split surface")
            return
        }

        splitManager.focusLeaf(id: leaves[0].leafID)
        controller.closeSplitAction(nil)

        XCTAssertNil(controller.activeSplitView, "Closing back to one pane must remove the split hierarchy")
        XCTAssertTrue(
            controller.terminalSurfaceView === promotedSurfaceView,
            "The surviving split surface must become the tab's primary terminal view"
        )
        XCTAssertTrue(
            controller.surfaceViewForTab(activeTabID) === promotedSurfaceView,
            "Tab-to-surface mapping must follow the surviving terminal after collapse"
        )
        XCTAssertEqual(
            controller.tabSurfaceMap[activeTabID],
            promotedSurfaceID,
            "The active tab must now point at the surviving surface ID"
        )
        XCTAssertEqual(
            controller.viewModelForTab(activeTabID)?.surfaceID,
            promotedSurfaceID,
            "The active tab must adopt the surviving view model"
        )
        XCTAssertNil(
            controller.splitSurfaceViews[promotedSurfaceID],
            "The surviving surface must no longer be tracked as a split once it becomes primary"
        )
        XCTAssertFalse(
            controller.terminalSurfaceView === originalPrimaryView,
            "The destroyed primary surface must not remain attached after collapse"
        )
        XCTAssertTrue(
            bridge.destroyedSurfaces.contains(originalPrimarySurfaceID),
            "Closing the focused primary pane must destroy its surface in the engine"
        )
    }

    func testHandleOSCNotificationUpdatesTheSourceTabViewModelTitle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id,
              let firstViewModel = controller.viewModelForTab(firstTabID) else {
            XCTFail("Expected bootstrap tab view model")
            return
        }

        controller.newTabAction(nil)
        guard let secondTabID = controller.tabManager.activeTabID,
              secondTabID != firstTabID,
              let secondViewModel = controller.viewModelForTab(secondTabID) else {
            XCTFail("Expected second tab view model")
            return
        }

        let originalFirstTitle = firstViewModel.title

        controller.handleOSCNotification(
            .titleChange("worker"),
            fromTabID: secondTabID,
            surfaceID: nil
        )

        XCTAssertEqual(
            secondViewModel.title,
            "worker",
            "Title changes must update the source tab's view model, not only the bootstrap tab"
        )
        XCTAssertEqual(
            firstViewModel.title,
            originalFirstTitle,
            "Background tab title updates must not leak into the bootstrap tab's view model"
        )
    }
}
