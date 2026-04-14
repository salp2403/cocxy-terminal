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
    private(set) var refreshDisplayLinkAnchorCallCount = 0

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

    func refreshDisplayLinkAnchor() {
        refreshDisplayLinkAnchorCallCount += 1
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

    func testCodeReviewSubmitRoutesToOriginatingTabSurface() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let tabA = controller.tabManager.tabs.first?.id else {
            XCTFail("Expected an initial tab")
            return
        }
        let cwdA = URL(fileURLWithPath: "/tmp/code-review-tab-a", isDirectory: true)
        controller.tabManager.updateTab(id: tabA) { $0.workingDirectory = cwdA }
        controller.handleTabSwitch(to: tabA)

        controller.newTabAction(nil)
        guard let tabB = controller.tabManager.activeTabID else {
            XCTFail("Expected a second tab")
            return
        }
        let cwdB = URL(fileURLWithPath: "/tmp/code-review-tab-b", isDirectory: true)
        controller.tabManager.updateTab(id: tabB) { $0.workingDirectory = cwdB }
        controller.handleTabSwitch(to: tabB)

        let surfaceA = controller.viewModelForTab(tabA)?.surfaceID ?? SurfaceID()
        let surfaceB = controller.viewModelForTab(tabB)?.surfaceID ?? SurfaceID()
        controller.tabSurfaceMap[tabA] = surfaceA
        controller.tabSurfaceMap[tabB] = surfaceB

        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(sessionId: "session-a", ref: "aaa111", workingDirectory: cwdA)
        tracker.recordSnapshot(sessionId: "session-b", ref: "bbb222", workingDirectory: cwdB)

        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                [FileDiff(filePath: "foo.swift", status: .modified, hunks: [])]
            }
        )

        controller.injectedSessionDiffTracker = tracker
        controller.injectedCodeReviewViewModel = viewModel
        let resolvedViewModel = controller.resolveCodeReviewViewModel()
        resolvedViewModel.refreshDelay = 0

        controller.tabManager.setActive(id: tabA)
        controller.handleTabSwitch(to: tabA)
        resolvedViewModel.refreshDiffs()

        controller.tabManager.setActive(id: tabB)
        controller.handleTabSwitch(to: tabB)
        resolvedViewModel.addComment(filePath: "foo.swift", line: 5, body: "Route back to tab A")
        resolvedViewModel.submitComments()

        XCTAssertEqual(
            bridge.sentTexts.last?.surface,
            surfaceA,
            "Submitting review feedback must target the tab that originated the review, not the focused tab"
        )
        XCTAssertNotEqual(bridge.sentTexts.last?.surface, surfaceB)
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

    func testDestroyAllSurfacesRemovesTerminalSubviewsFromContainer() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        controller.terminalContainerView = container

        let primaryView = TrackingTerminalHostView(frame: container.bounds)
        controller.terminalSurfaceView = primaryView
        container.addSubview(primaryView)

        XCTAssertEqual(container.subviews.count, 1)

        controller.destroyAllSurfaces()

        XCTAssertTrue(
            container.subviews.isEmpty,
            "Destroying all surfaces must also clear the visible terminal hierarchy from the container"
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

    func testHandleTabSwitchFallsBackToStoredSplitSurfaceWhenPrimaryMappingIsMissing() {
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

        let targetTab = controller.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/fallback-tab")
        )
        let storedSurface = TrackingTerminalHostView()
        let storedSurfaceID = SurfaceID()

        controller.savedTabSplitSurfaceViews[targetTab.id] = [storedSurfaceID: storedSurface]
        controller.tabSurfaceMap[targetTab.id] = storedSurfaceID
        controller.tabSurfaceViews.removeValue(forKey: targetTab.id)

        controller.handleTabSwitch(to: targetTab.id)

        XCTAssertEqual(controller.displayedTabID, targetTab.id)
        XCTAssertTrue(
            controller.terminalSurfaceView === storedSurface,
            "Tab switching must recover from a missing primary mapping by using the stored split surface"
        )
        XCTAssertTrue(
            storedSurface.superview === container,
            "The recovered surface must be attached back into the terminal container"
        )
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

    func testSpawnSubagentPanelIgnoresGenericAgentPlaceholderType() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        controller.injectedDashboardViewModel = AgentDashboardViewModel()

        controller.spawnSubagentPanel(
            subagentId: "sub-generic",
            sessionId: "sess-1",
            agentType: "Agent"
        )

        XCTAssertTrue(
            controller.panelContentViews.isEmpty,
            "Placeholder agent labels must not auto-open subagent panels that the user did not explicitly spawn"
        )
    }

    func testSpawnSubagentPanelIgnoresMissingAgentType() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        controller.injectedDashboardViewModel = AgentDashboardViewModel()

        controller.spawnSubagentPanel(
            subagentId: "sub-untitled",
            sessionId: "sess-1",
            agentType: nil
        )

        XCTAssertTrue(
            controller.panelContentViews.isEmpty,
            "Subagent auto-panels must not open when the hook lacks descriptive type metadata"
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

    func testCloseSplitActionDoesNotCloseLastTerminalWhenOnlyPanelsWouldRemain() {
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

        controller.splitWithBrowserAction(nil)

        guard let splitManager = controller.activeSplitManager else {
            XCTFail("Expected split manager after opening browser panel")
            return
        }

        let leaves = splitManager.rootNode.allLeafIDs()
        guard let terminalLeaf = leaves.first(where: {
            splitManager.panelType(for: $0.terminalID) == .terminal
        }) else {
            XCTFail("Expected a terminal leaf")
            return
        }

        splitManager.focusLeaf(id: terminalLeaf.leafID)
        controller.closeSplitAction(nil)

        XCTAssertNotNil(controller.activeSplitView, "The split hierarchy must stay alive when closing the last terminal would leave only panels")
        XCTAssertTrue(controller.terminalSurfaceView === originalPrimaryView)
        XCTAssertEqual(controller.tabSurfaceMap[activeTabID], originalPrimarySurfaceID)
        XCTAssertFalse(bridge.destroyedSurfaces.contains(originalPrimarySurfaceID))
    }

    func testStripSwapTabsRebuildsNestedVisualHierarchyWhenLeavesHaveDifferentParents() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }

        controller.performVisualSplit(isVertical: true)

        guard let splitManager = controller.activeSplitManager,
              let firstLeaf = splitManager.rootNode.allLeafIDs().first else {
            XCTFail("Expected an active split manager after creating the first split")
            return
        }

        splitManager.focusLeaf(id: firstLeaf.leafID)
        controller.performVisualSplit(isVertical: false)

        let initialLeafViews = controller.collectLeafViews()
        guard initialLeafViews.count == 3,
              let strip = controller.horizontalTabStripView as? HorizontalTabStripView else {
            XCTFail("Expected three visible leaves and a horizontal tab strip")
            return
        }

        strip.onSwapTabs?(0, 2)

        let reorderedLeafViews = controller.collectLeafViews()
        XCTAssertTrue(
            reorderedLeafViews[0] === initialLeafViews[2],
            "Swapping leaves across different split parents must rebuild the hierarchy so the leftmost pane reflects the new model order"
        )
        XCTAssertTrue(
            reorderedLeafViews[2] === initialLeafViews[0],
            "Rebuilding the split hierarchy must also move the original first pane into the new trailing position"
        )
    }

    func testPerformVisualSplitUsesVisibleTabWorkingDirectoryWhenDisplayedTabDiffersFromActive() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }

        guard let firstTabID = controller.tabManager.activeTabID else {
            XCTFail("Expected bootstrap tab")
            return
        }

        let visibleDirectory = URL(fileURLWithPath: "/tmp/visible-tab")
        controller.tabManager.updateTab(id: firstTabID) { tab in
            tab.workingDirectory = visibleDirectory
        }

        let secondTab = controller.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/active-tab")
        )
        controller.tabManager.updateTab(id: secondTab.id) { tab in
            tab.title = "Other"
        }

        controller.displayedTabID = firstTabID
        XCTAssertEqual(controller.tabManager.activeTabID, secondTab.id)

        controller.performVisualSplit(isVertical: true)

        guard let latestRequest = bridge.createSurfaceRequests.last else {
            XCTFail("Expected split surface creation")
            return
        }

        XCTAssertEqual(
            latestRequest.workingDirectory?.path,
            visibleDirectory.path,
            "Split creation must inherit the tab actually shown on screen"
        )
        XCTAssertEqual(
            controller.tabID(for: latestRequest.surface),
            firstTabID,
            "The new split surface must stay attached to the visible workspace"
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

    // MARK: - windowDidChangeScreen safety net

    /// Verifies that `windowDidChangeScreen` walks every managed
    /// surface view (primary, tab map, split map, AND saved tab split
    /// surfaces) and forces a `refreshDisplayLinkAnchor()` call on each.
    /// This is the v0.1.53 safety net for detached/hidden views whose
    /// own `NSWindow.didChangeScreenNotification` observer cannot fire
    /// because they have no window reference.
    func testWindowDidChangeScreenRefreshesAnchorOnEveryManagedSurface() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let primaryView = TrackingTerminalHostView()
        controller.terminalSurfaceView = primaryView

        let tabMappedView = TrackingTerminalHostView()
        let tabID = TabID()
        controller.tabSurfaceViews[tabID] = tabMappedView

        let splitView = TrackingTerminalHostView()
        let splitSurfaceID = SurfaceID()
        controller.splitSurfaceViews[splitSurfaceID] = splitView

        let savedView = TrackingTerminalHostView()
        let savedTabID = TabID()
        let savedSurfaceID = SurfaceID()
        controller.savedTabSplitSurfaceViews[savedTabID] = [savedSurfaceID: savedView]

        // Drive the window-screen-changed delegate path. The notification
        // payload is irrelevant — the controller dispatches based on the
        // event itself, not its userInfo.
        let notification = Notification(
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
        controller.windowDidChangeScreen(notification)

        XCTAssertEqual(
            primaryView.refreshDisplayLinkAnchorCallCount, 1,
            "Primary surface view must receive a display-link re-anchor"
        )
        XCTAssertEqual(
            tabMappedView.refreshDisplayLinkAnchorCallCount, 1,
            "Tab-mapped surface view must receive a display-link re-anchor"
        )
        XCTAssertEqual(
            splitView.refreshDisplayLinkAnchorCallCount, 1,
            "Split surface view must receive a display-link re-anchor"
        )
        XCTAssertEqual(
            savedView.refreshDisplayLinkAnchorCallCount, 1,
            "Saved (detached) split surface view must receive a display-link re-anchor"
        )
    }

    func testWindowDidChangeScreenDeduplicatesSharedViews() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // The same view is the primary AND lives inside tabSurfaceViews —
        // a common situation immediately after surface creation. The
        // safety net must call refreshDisplayLinkAnchor exactly ONCE
        // per distinct view, not once per slot.
        let sharedView = TrackingTerminalHostView()
        let tabID = TabID()
        controller.terminalSurfaceView = sharedView
        controller.tabSurfaceViews[tabID] = sharedView

        let notification = Notification(
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
        controller.windowDidChangeScreen(notification)

        XCTAssertEqual(
            sharedView.refreshDisplayLinkAnchorCallCount, 1,
            "Shared view must be re-anchored exactly once even though it appears in multiple slots"
        )
    }

    func testRecoverTerminalRenderingAfterWakeRefreshesAnchorsAndVisibleViews() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let primaryView = TrackingTerminalHostView()
        controller.terminalSurfaceView = primaryView

        let tabMappedDetachedView = TrackingTerminalHostView()
        controller.tabSurfaceViews[TabID()] = tabMappedDetachedView

        let splitView = TrackingTerminalHostView()
        controller.splitSurfaceViews[SurfaceID()] = splitView

        let savedView = TrackingTerminalHostView()
        controller.savedTabSplitSurfaceViews[TabID()] = [SurfaceID(): savedView]

        controller.recoverTerminalRenderingAfterWake()

        XCTAssertEqual(primaryView.refreshDisplayLinkAnchorCallCount, 1)
        XCTAssertEqual(splitView.refreshDisplayLinkAnchorCallCount, 1)
        XCTAssertEqual(tabMappedDetachedView.refreshDisplayLinkAnchorCallCount, 1)
        XCTAssertEqual(savedView.refreshDisplayLinkAnchorCallCount, 1)

        XCTAssertEqual(primaryView.updateMetricsCallCount, 1)
        XCTAssertEqual(primaryView.redrawCallCount, 1)
        XCTAssertEqual(splitView.updateMetricsCallCount, 1)
        XCTAssertEqual(splitView.redrawCallCount, 1)

        XCTAssertEqual(
            tabMappedDetachedView.redrawCallCount, 0,
            "Detached tab-mapped views must not be redrawn as visible surfaces"
        )
        XCTAssertEqual(
            savedView.redrawCallCount, 0,
            "Saved detached split views must only refresh their anchor, not redraw as visible surfaces"
        )
    }
}
