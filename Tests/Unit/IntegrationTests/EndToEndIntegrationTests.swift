// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EndToEndIntegrationTests.swift - End-to-end integration tests for cross-component flows.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - 1. Tab Lifecycle Integration

/// Tests the full tab lifecycle: create, verify, add, close.
///
/// Verifies that TabManager.tabs, tabSurfaceViews and tabViewModels
/// stay in sync across the entire create/close cycle.
@MainActor
final class TabLifecycleIntegrationTests: XCTestCase {

    func testInitialControllerHasExactlyOneTab() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertEqual(
            controller.tabManager.tabs.count,
            1,
            "A new MainWindowController must start with exactly 1 tab"
        )
    }

    func testAddTabIncreasesTabCountToTwo() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.newTabAction(nil)

        XCTAssertEqual(
            controller.tabManager.tabs.count,
            2,
            "After adding one tab, the total must be 2"
        )
    }

    func testCloseTabReturnsToOneTab() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.newTabAction(nil)
        XCTAssertEqual(controller.tabManager.tabs.count, 2,
                       "Precondition: must have 2 tabs before closing")

        controller.closeTabAction(nil)

        XCTAssertEqual(
            controller.tabManager.tabs.count,
            1,
            "After closing one tab from two, the total must be 1"
        )
    }

    func testCreateAddCloseFullCycle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Phase 1: initial state.
        XCTAssertEqual(controller.tabManager.tabs.count, 1,
                       "Initial state must have 1 tab")

        // Phase 2: add a tab.
        controller.newTabAction(nil)
        XCTAssertEqual(controller.tabManager.tabs.count, 2,
                       "After addTab, must have 2 tabs")

        // Phase 3: close the active tab.
        controller.closeTabAction(nil)
        XCTAssertEqual(controller.tabManager.tabs.count, 1,
                       "After closeTab, must return to 1 tab")
    }

    func testSurfaceViewsSyncedWithTabManagerAfterAdd() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertEqual(
            controller.tabSurfaceViews.count,
            controller.tabManager.tabs.count,
            "tabSurfaceViews must match tabManager.tabs after creation"
        )

        controller.newTabAction(nil)

        XCTAssertEqual(
            controller.tabSurfaceViews.count,
            controller.tabManager.tabs.count,
            "tabSurfaceViews must match tabManager.tabs after addTab"
        )
    }

    func testViewModelsSyncedWithTabManagerAfterAdd() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertEqual(
            controller.tabViewModels.count,
            controller.tabManager.tabs.count,
            "tabViewModels must match tabManager.tabs after creation"
        )

        controller.newTabAction(nil)

        XCTAssertEqual(
            controller.tabViewModels.count,
            controller.tabManager.tabs.count,
            "tabViewModels must match tabManager.tabs after addTab"
        )
    }

    func testSurfaceViewsSyncedWithTabManagerAfterClose() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.newTabAction(nil)
        controller.closeTabAction(nil)

        XCTAssertEqual(
            controller.tabSurfaceViews.count,
            controller.tabManager.tabs.count,
            "tabSurfaceViews must match tabManager.tabs after closeTab"
        )
    }

    func testViewModelsSyncedWithTabManagerAfterClose() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.newTabAction(nil)
        controller.closeTabAction(nil)

        XCTAssertEqual(
            controller.tabViewModels.count,
            controller.tabManager.tabs.count,
            "tabViewModels must match tabManager.tabs after closeTab"
        )
    }
}

// MARK: - 2. Command Palette Integration

/// Tests the Command Palette visibility lifecycle and lazy ViewModel creation.
@MainActor
final class CommandPaletteLifecycleIntegrationTests: XCTestCase {

    func testToggleCommandPaletteMakesItVisible() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleCommandPalette()

        XCTAssertTrue(
            controller.isCommandPaletteVisible,
            "Command Palette must be visible after toggleCommandPalette"
        )
    }

    func testDismissCommandPaletteMakesItHidden() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleCommandPalette()
        XCTAssertTrue(controller.isCommandPaletteVisible,
                       "Precondition: palette must be visible")

        controller.dismissCommandPalette()

        XCTAssertFalse(
            controller.isCommandPaletteVisible,
            "Command Palette must be hidden after dismissCommandPalette"
        )
    }

    func testCommandPaletteViewModelIsLazilyCreated() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertNil(
            controller.commandPaletteViewModel,
            "commandPaletteViewModel must be nil before first toggle"
        )

        controller.toggleCommandPalette()

        XCTAssertNotNil(
            controller.commandPaletteViewModel,
            "commandPaletteViewModel must be created on first toggle"
        )
    }

    func testToggleTwiceReturnsToHidden() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleCommandPalette()
        controller.toggleCommandPalette()

        XCTAssertFalse(
            controller.isCommandPaletteVisible,
            "Command Palette must be hidden after two toggles"
        )
    }
}

// MARK: - 3. Overlay Mutual Exclusion

/// Tests that dismissActiveOverlay closes overlays one at a time,
/// and that multiple overlays can coexist before being dismissed.
@MainActor
final class OverlayMutualExclusionIntegrationTests: XCTestCase {

    func testDashboardBecomesVisibleOnToggle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleDashboard()

        XCTAssertTrue(
            controller.isDashboardVisible,
            "Dashboard must be visible after toggleDashboard"
        )
    }

    func testNotificationPanelBecomesVisibleOnToggle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleNotificationPanel()

        XCTAssertTrue(
            controller.isNotificationPanelVisible,
            "Notification panel must be visible after toggleNotificationPanel"
        )
    }

    func testDashboardAndNotificationPanelCanCoexist() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleDashboard()
        controller.toggleNotificationPanel()

        XCTAssertTrue(
            controller.isDashboardVisible,
            "Dashboard must remain visible when notification panel opens"
        )
        XCTAssertTrue(
            controller.isNotificationPanelVisible,
            "Notification panel must be visible alongside dashboard"
        )
    }

    func testDismissActiveOverlayDismissesOneAtATime() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleDashboard()
        controller.toggleNotificationPanel()

        // First dismiss: notification panel has higher priority in dismissActiveOverlay.
        controller.dismissActiveOverlay(nil)

        // dismissActiveOverlay checks overlays in a specific order.
        // According to the implementation: browser > notification > dashboard.
        XCTAssertFalse(
            controller.isNotificationPanelVisible,
            "Notification panel must be dismissed first by dismissActiveOverlay"
        )

        // Second dismiss: dashboard is next.
        controller.dismissActiveOverlay(nil)

        XCTAssertFalse(
            controller.isDashboardVisible,
            "Dashboard must be dismissed on second call to dismissActiveOverlay"
        )
    }

    func testAllOverlaysHiddenAfterFullDismissCycle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleDashboard()
        controller.toggleNotificationPanel()

        // Dismiss all by calling until both are gone.
        controller.dismissActiveOverlay(nil)
        controller.dismissActiveOverlay(nil)

        XCTAssertFalse(
            controller.isDashboardVisible,
            "Dashboard must be hidden after full dismiss cycle"
        )
        XCTAssertFalse(
            controller.isNotificationPanelVisible,
            "Notification panel must be hidden after full dismiss cycle"
        )
    }
}

// MARK: - 4. Browser Panel Integration

/// Tests the browser panel toggle lifecycle and default URL.
@MainActor
final class BrowserPanelIntegrationTests: XCTestCase {

    func testToggleBrowserMakesItVisible() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleBrowser()

        XCTAssertTrue(
            controller.isBrowserVisible,
            "Browser must be visible after toggleBrowser"
        )
    }

    func testDismissBrowserMakesItHidden() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleBrowser()
        controller.dismissBrowser()

        XCTAssertFalse(
            controller.isBrowserVisible,
            "Browser must be hidden after dismissBrowser"
        )
    }

    func testBrowserViewModelCreatedWithDefaultURL() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleBrowser()

        XCTAssertNotNil(
            controller.browserViewModel,
            "browserViewModel must exist after toggleBrowser"
        )
        XCTAssertEqual(
            controller.browserViewModel?.urlString,
            "http://localhost:3000",
            "BrowserViewModel default URL must be http://localhost:3000"
        )
    }

    func testBrowserToggleTwiceReturnsToHidden() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.toggleBrowser()
        controller.toggleBrowser()

        XCTAssertFalse(
            controller.isBrowserVisible,
            "Browser must be hidden after two toggles"
        )
    }
}

// MARK: - 5. Agent Detection Injection

/// Tests the agent detection engine injection into MainWindowController.
@MainActor
final class AgentDetectionInjectionIntegrationTests: XCTestCase {

    func testAgentDetectionEngineIsNilByDefault() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertNil(
            controller.injectedAgentDetectionEngine,
            "injectedAgentDetectionEngine must be nil by default"
        )
    }

    func testAgentDetectionEngineCanBeInjected() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let engine = AgentDetectionEngineImpl(compiledConfigs: [])
        controller.injectedAgentDetectionEngine = engine

        XCTAssertNotNil(
            controller.injectedAgentDetectionEngine,
            "injectedAgentDetectionEngine must not be nil after injection"
        )
    }

    func testInjectedEngineIsTheSameInstance() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let engine = AgentDetectionEngineImpl(compiledConfigs: [])
        controller.injectedAgentDetectionEngine = engine

        XCTAssertTrue(
            controller.injectedAgentDetectionEngine === engine,
            "Injected engine must be the same instance"
        )
    }

    func testEngineWithEmptyConfigsDoesNotCrash() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let engine = AgentDetectionEngineImpl(compiledConfigs: [])
        controller.injectedAgentDetectionEngine = engine

        // Verify the engine is operational: calling reset should not crash.
        engine.reset()

        XCTAssertEqual(
            engine.currentState,
            .idle,
            "Engine with empty configs must start in idle state"
        )
    }
}

// MARK: - 6. Tab Manager State Consistency

/// Tests that TabManager state (tabs.count) remains consistent with
/// MainWindowController mappings across bulk operations.
@MainActor
final class TabManagerStateConsistencyIntegrationTests: XCTestCase {

    func testCreateFiveTabsCountIsFive() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Start with 1, add 4 more.
        for _ in 0..<4 {
            controller.newTabAction(nil)
        }

        XCTAssertEqual(
            controller.tabManager.tabs.count,
            5,
            "After creating 4 additional tabs, total must be 5"
        )
    }

    func testSurfaceViewsMatchTabCountAtFive() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        for _ in 0..<4 {
            controller.newTabAction(nil)
        }

        XCTAssertEqual(
            controller.tabSurfaceViews.count,
            controller.tabManager.tabs.count,
            "tabSurfaceViews.count must match tabManager.tabs.count at 5 tabs"
        )
    }

    func testCloseThreeFromFiveLeavesTwo() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Create 5 tabs total.
        for _ in 0..<4 {
            controller.newTabAction(nil)
        }
        XCTAssertEqual(controller.tabManager.tabs.count, 5,
                       "Precondition: must have 5 tabs")

        // Close 3 tabs.
        for _ in 0..<3 {
            controller.closeTabAction(nil)
        }

        XCTAssertEqual(
            controller.tabManager.tabs.count,
            2,
            "After closing 3 tabs from 5, total must be 2"
        )
    }

    func testSurfaceViewsMatchTabCountAfterBulkClose() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        for _ in 0..<4 {
            controller.newTabAction(nil)
        }

        for _ in 0..<3 {
            controller.closeTabAction(nil)
        }

        XCTAssertEqual(
            controller.tabSurfaceViews.count,
            controller.tabManager.tabs.count,
            "tabSurfaceViews.count must match tabManager.tabs.count after bulk close"
        )
    }

    func testSurfaceViewsSyncedAtEachStep() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Verify sync at each step of creation.
        for expectedCount in 2...5 {
            controller.newTabAction(nil)
            XCTAssertEqual(
                controller.tabSurfaceViews.count,
                expectedCount,
                "tabSurfaceViews.count must be \(expectedCount) after creating tab \(expectedCount)"
            )
            XCTAssertEqual(
                controller.tabManager.tabs.count,
                expectedCount,
                "tabManager.tabs.count must be \(expectedCount) after creating tab \(expectedCount)"
            )
        }

        // Verify sync at each step of closing.
        for expectedCount in stride(from: 4, through: 2, by: -1) {
            controller.closeTabAction(nil)
            XCTAssertEqual(
                controller.tabSurfaceViews.count,
                expectedCount,
                "tabSurfaceViews.count must be \(expectedCount) after closing to \(expectedCount)"
            )
            XCTAssertEqual(
                controller.tabManager.tabs.count,
                expectedCount,
                "tabManager.tabs.count must be \(expectedCount) after closing to \(expectedCount)"
            )
        }
    }
}

// MARK: - 7. Session Capture Integration

/// Tests that AppDelegate.captureCurrentSession produces a valid session,
/// and that controller tab state is suitable for session serialization.
///
/// Note: AppDelegate.windowController has a private setter. These tests
/// verify captureCurrentSession without a window controller (empty tabs),
/// and verify that the controller's tab data would be correct for capture.
@MainActor
final class SessionCaptureIntegrationTests: XCTestCase {

    func testCaptureSessionWithoutWindowControllerHasNoTabs() {
        let delegate = AppDelegate()
        let session = delegate.captureCurrentSession()

        XCTAssertEqual(
            session.version,
            Session.currentVersion,
            "Session must have the current schema version"
        )
        XCTAssertEqual(
            session.windows.count,
            1,
            "Session must have exactly one window state"
        )
        XCTAssertTrue(
            session.windows[0].tabs.isEmpty,
            "Without a window controller, session must have 0 tabs"
        )
    }

    func testControllerWithThreeTabsHasThreeTabsForCapture() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Add 2 more tabs (total 3).
        controller.newTabAction(nil)
        controller.newTabAction(nil)

        XCTAssertEqual(
            controller.tabManager.tabs.count,
            3,
            "Controller must have 3 tabs after adding 2"
        )

        // Verify each tab has a surface view (needed for session capture).
        for tab in controller.tabManager.tabs {
            XCTAssertNotNil(
                controller.tabSurfaceViews[tab.id],
                "Tab \(tab.id.rawValue) must have a surface view for session capture"
            )
        }
    }

    func testControllerTabsHaveValidWorkingDirectories() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        controller.newTabAction(nil)
        controller.newTabAction(nil)

        for tab in controller.tabManager.tabs {
            XCTAssertFalse(
                tab.workingDirectory.path.isEmpty,
                "Each tab must have a non-empty working directory for session capture"
            )
        }
    }

    func testCaptureSessionVersionIsAlwaysCurrent() {
        let delegate = AppDelegate()
        let session = delegate.captureCurrentSession()

        XCTAssertEqual(
            session.version,
            Session.currentVersion,
            "Session version must always be Session.currentVersion"
        )
    }

    func testCaptureSessionHasValidTimestamp() {
        let before = Date()
        let delegate = AppDelegate()
        let session = delegate.captureCurrentSession()
        let after = Date()

        XCTAssertGreaterThanOrEqual(
            session.savedAt,
            before,
            "Session savedAt must not be before the capture started"
        )
        XCTAssertLessThanOrEqual(
            session.savedAt,
            after,
            "Session savedAt must not be after the capture finished"
        )
    }
}

// MARK: - 8. Port Scanner Lifecycle

/// Tests the PortScanner state transitions without performing real network probes.
@MainActor
final class PortScannerLifecycleIntegrationTests: XCTestCase {

    func testInitialActivePortsAreEmpty() {
        let scanner = PortScannerImpl()

        XCTAssertTrue(
            scanner.activePorts.isEmpty,
            "activePorts must be empty on a newly created scanner"
        )
    }

    func testInitialScanningStateIsFalse() {
        let scanner = PortScannerImpl()

        XCTAssertFalse(
            scanner.isScanning,
            "isScanning must be false on a newly created scanner"
        )
    }

    func testStartScanningChangesStateToTrue() {
        let scanner = PortScannerImpl()

        scanner.startScanning(interval: 60.0)

        XCTAssertTrue(
            scanner.isScanning,
            "isScanning must be true after startScanning"
        )

        // Clean up: stop to release the timer.
        scanner.stopScanning()
    }

    func testStopScanningChangesStateToFalse() {
        let scanner = PortScannerImpl()

        scanner.startScanning(interval: 60.0)
        scanner.stopScanning()

        XCTAssertFalse(
            scanner.isScanning,
            "isScanning must be false after stopScanning"
        )
    }

    func testStartStopStartCycleIsStable() {
        let scanner = PortScannerImpl()

        scanner.startScanning(interval: 60.0)
        XCTAssertTrue(scanner.isScanning, "Must be scanning after first start")

        scanner.stopScanning()
        XCTAssertFalse(scanner.isScanning, "Must not be scanning after stop")

        scanner.startScanning(interval: 60.0)
        XCTAssertTrue(scanner.isScanning, "Must be scanning after second start")

        scanner.stopScanning()
        XCTAssertFalse(scanner.isScanning, "Must not be scanning after final stop")
    }
}

// MARK: - 9. Notification Ring Integration

/// Tests the notification ring visibility on the terminal host view.
@MainActor
final class NotificationRingIntegrationTests: XCTestCase {

    func testNotificationRingIsInactiveByDefault() {
        let bridge = MockTerminalEngine()
        let viewModel = TerminalViewModel(engine: bridge)
        let surfaceView = CocxyCoreView(viewModel: viewModel)

        XCTAssertFalse(
            surfaceView.isNotificationRingActive,
            "Notification ring must be inactive on a new terminal host view"
        )
    }

    func testShowNotificationRingActivatesIt() {
        let bridge = MockTerminalEngine()
        let viewModel = TerminalViewModel(engine: bridge)
        let surfaceView = CocxyCoreView(viewModel: viewModel)

        surfaceView.showNotificationRing()

        XCTAssertTrue(
            surfaceView.isNotificationRingActive,
            "Notification ring must be active after showNotificationRing"
        )
    }

    func testHideNotificationRingDeactivatesIt() {
        let bridge = MockTerminalEngine()
        let viewModel = TerminalViewModel(engine: bridge)
        let surfaceView = CocxyCoreView(viewModel: viewModel)

        surfaceView.showNotificationRing()
        surfaceView.hideNotificationRing()

        XCTAssertFalse(
            surfaceView.isNotificationRingActive,
            "Notification ring must be inactive after hideNotificationRing"
        )
    }

    func testShowHideShowCycleIsStable() {
        let bridge = MockTerminalEngine()
        let viewModel = TerminalViewModel(engine: bridge)
        let surfaceView = CocxyCoreView(viewModel: viewModel)

        surfaceView.showNotificationRing()
        XCTAssertTrue(surfaceView.isNotificationRingActive,
                       "Ring must be active after first show")

        surfaceView.hideNotificationRing()
        XCTAssertFalse(surfaceView.isNotificationRingActive,
                        "Ring must be inactive after hide")

        surfaceView.showNotificationRing()
        XCTAssertTrue(surfaceView.isNotificationRingActive,
                       "Ring must be active after second show")

        surfaceView.hideNotificationRing()
    }

    func testHideNotificationRingWhenAlreadyHiddenIsNoOp() {
        let bridge = MockTerminalEngine()
        let viewModel = TerminalViewModel(engine: bridge)
        let surfaceView = CocxyCoreView(viewModel: viewModel)

        // Hide without showing first: must not crash.
        surfaceView.hideNotificationRing()

        XCTAssertFalse(
            surfaceView.isNotificationRingActive,
            "Calling hideNotificationRing on an already hidden ring must be a no-op"
        )
    }
}

// MARK: - 10. Status Bar Data Integration

/// Tests the agent summary computation from tab agent states.
@MainActor
final class StatusBarDataIntegrationTests: XCTestCase {

    func testComputeAgentSummaryWithAllIdleTabs() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(
            summary.working, 0,
            "working count must be 0 when all tabs are idle"
        )
        XCTAssertEqual(
            summary.waiting, 0,
            "waiting count must be 0 when all tabs are idle"
        )
        XCTAssertEqual(
            summary.errors, 0,
            "errors count must be 0 when all tabs are idle"
        )
        XCTAssertEqual(
            summary.finished, 0,
            "finished count must be 0 when all tabs are idle"
        )
    }

    // MARK: - Per-surface store seeding helper

    /// Attaches a per-surface store to the controller (if missing), wires
    /// the tab to a primary surface, and seeds the surface's agent state.
    /// The resolver then observes this state through the same path it
    /// uses in production.
    @discardableResult
    private func seedTabAgentState(
        controller: MainWindowController,
        tabID: TabID,
        state: AgentState,
        detectedAgent: DetectedAgent? = nil,
        activity: String? = nil,
        toolCount: Int = 0,
        errorCount: Int = 0
    ) -> SurfaceID {
        if controller.injectedPerSurfaceStore == nil {
            controller.injectedPerSurfaceStore = AgentStatePerSurfaceStore()
        }
        let sid = SurfaceID()
        controller.tabSurfaceMap[tabID] = sid
        controller.injectedPerSurfaceStore?.update(surfaceID: sid) {
            $0.agentState = state
            $0.detectedAgent = detectedAgent
            $0.agentActivity = activity
            $0.agentToolCount = toolCount
            $0.agentErrorCount = errorCount
        }
        return sid
    }

    func testComputeAgentSummaryCountsWorkingTab() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        seedTabAgentState(
            controller: controller,
            tabID: firstTabID,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(
            summary.working, 1,
            "working count must be 1 when one tab has agentState .working"
        )
        XCTAssertEqual(
            summary.activeAgentText,
            "Claude Code working",
            "active agent text must describe the focused agent state"
        )
    }

    func testComputeAgentSummaryCountsWaitingTab() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        seedTabAgentState(controller: controller, tabID: firstTabID, state: .waitingInput)

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(
            summary.waiting, 1,
            "waiting count must be 1 when one tab has agentState .waitingInput"
        )
    }

    func testComputeAgentSummaryCountsErrorTab() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        // `.error` alone is not `isActive`; the resolver keeps it
        // visible only when a detected agent stays attached. Seed one
        // so the indicator surfaces the error count.
        seedTabAgentState(
            controller: controller,
            tabID: firstTabID,
            state: .error,
            detectedAgent: DetectedAgent(
                name: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(
            summary.errors, 1,
            "errors count must be 1 when one tab has agentState .error"
        )
    }

    func testComputeAgentSummaryCountsFinishedTab() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        // `.finished` alone is not `isActive`; the resolver keeps it
        // visible only when a detected agent stays attached.
        seedTabAgentState(
            controller: controller,
            tabID: firstTabID,
            state: .finished,
            detectedAgent: DetectedAgent(
                name: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(
            summary.finished, 1,
            "finished count must be 1 when one tab has agentState .finished"
        )
    }

    func testComputeAgentSummaryCountsLaunchedAsWorking() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }
        seedTabAgentState(controller: controller, tabID: firstTabID, state: .launched)

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(
            summary.working, 1,
            "working count must include tabs with agentState .launched"
        )
    }

    func testComputeAgentSummaryAcrossMultipleTabs() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Create 3 additional tabs (total 4).
        controller.newTabAction(nil)
        controller.newTabAction(nil)
        controller.newTabAction(nil)

        // Set different states on each tab via the per-surface store.
        let tabs = controller.tabManager.tabs
        XCTAssertEqual(tabs.count, 4, "Precondition: must have 4 tabs")

        let agent = DetectedAgent(
            name: "Claude Code",
            launchCommand: "claude",
            startedAt: Date()
        )
        seedTabAgentState(controller: controller, tabID: tabs[0].id, state: .working)
        seedTabAgentState(controller: controller, tabID: tabs[1].id, state: .waitingInput)
        seedTabAgentState(controller: controller, tabID: tabs[2].id, state: .error, detectedAgent: agent)
        seedTabAgentState(controller: controller, tabID: tabs[3].id, state: .finished, detectedAgent: agent)

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(summary.working, 1,
                       "working must be 1 with one .working tab")
        XCTAssertEqual(summary.waiting, 1,
                       "waiting must be 1 with one .waitingInput tab")
        XCTAssertEqual(summary.errors, 1,
                       "errors must be 1 with one .error tab")
        XCTAssertEqual(summary.finished, 1,
                       "finished must be 1 with one .finished tab")
    }

    func testComputeAgentSummaryIncludesActiveToolAndErrorCounts() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        guard let firstTabID = controller.tabManager.tabs.first?.id else {
            XCTFail("TabManager must have at least one tab")
            return
        }

        seedTabAgentState(
            controller: controller,
            tabID: firstTabID,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            ),
            activity: "Read: main.swift",
            toolCount: 3,
            errorCount: 1
        )

        let summary = controller.computeAgentSummary()

        XCTAssertEqual(summary.activeAgentText, "Read: main.swift")
        XCTAssertEqual(summary.activeToolCount, 3)
        XCTAssertEqual(summary.activeErrorCount, 1)
    }
}
