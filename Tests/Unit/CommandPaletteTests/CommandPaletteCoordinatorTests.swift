// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteCoordinatorTests.swift - Tests for Command Palette coordinator wiring.
//
// Test plan (6 tests):
// 1.  Coordinator.newTab -> TabManager.addTab called
// 2.  Coordinator.splitVertical -> SplitManager.splitFocused called
// 3.  Coordinator.splitHorizontal -> SplitManager.splitFocused called
// 4.  Coordinator.toggleDashboard -> ViewModel.toggleVisibility called
// 5.  Engine with coordinator -> built-in actions invoke coordinator methods
// 6.  Engine without coordinator -> built-in actions are safe no-ops

import XCTest
@testable import CocxyTerminal

@MainActor
final class CommandPaletteCoordinatorTests: XCTestCase {

    // MARK: - Test 1: Coordinator.newTab calls TabManager.addTab

    func testNewTabCallsTabManagerAddTab() {
        let tabManager = TabManager()
        let splitManager = SplitManager()
        let dashboardViewModel = AgentDashboardViewModel()
        let coordinator = CommandPaletteCoordinatorImpl(
            tabManager: tabManager,
            splitManager: splitManager,
            dashboardViewModel: dashboardViewModel,
            themeEngine: nil
        )

        let initialTabCount = tabManager.tabs.count

        coordinator.newTab()

        XCTAssertEqual(tabManager.tabs.count, initialTabCount + 1,
                        "newTab must add a new tab via TabManager")
    }

    // MARK: - Test 2: Coordinator.splitVertical calls SplitManager

    func testSplitVerticalCallsSplitManager() {
        let tabManager = TabManager()
        let splitManager = SplitManager()
        let dashboardViewModel = AgentDashboardViewModel()
        let coordinator = CommandPaletteCoordinatorImpl(
            tabManager: tabManager,
            splitManager: splitManager,
            dashboardViewModel: dashboardViewModel,
            themeEngine: nil
        )

        let initialLeafCount = splitManager.rootNode.leafCount

        coordinator.splitVertical()

        XCTAssertEqual(splitManager.rootNode.leafCount, initialLeafCount + 1,
                        "splitVertical must create a new leaf in the split tree")
    }

    // MARK: - Test 3: Coordinator.splitHorizontal calls SplitManager

    func testSplitHorizontalCallsSplitManager() {
        let tabManager = TabManager()
        let splitManager = SplitManager()
        let dashboardViewModel = AgentDashboardViewModel()
        let coordinator = CommandPaletteCoordinatorImpl(
            tabManager: tabManager,
            splitManager: splitManager,
            dashboardViewModel: dashboardViewModel,
            themeEngine: nil
        )

        let initialLeafCount = splitManager.rootNode.leafCount

        coordinator.splitHorizontal()

        XCTAssertEqual(splitManager.rootNode.leafCount, initialLeafCount + 1,
                        "splitHorizontal must create a new leaf in the split tree")
    }

    // MARK: - Test 4: Coordinator.toggleDashboard calls ViewModel

    func testToggleDashboardCallsViewModel() {
        let tabManager = TabManager()
        let splitManager = SplitManager()
        let dashboardViewModel = AgentDashboardViewModel()
        let coordinator = CommandPaletteCoordinatorImpl(
            tabManager: tabManager,
            splitManager: splitManager,
            dashboardViewModel: dashboardViewModel,
            themeEngine: nil
        )

        let initialVisibility = dashboardViewModel.isVisible

        coordinator.toggleDashboard()

        XCTAssertNotEqual(dashboardViewModel.isVisible, initialVisibility,
                           "toggleDashboard must toggle the dashboard visibility")
    }

    // MARK: - Test 5: Engine with coordinator -> built-in actions invoke coordinator

    func testEngineWithCoordinatorInvokesRealHandlers() {
        let tabManager = TabManager()
        let splitManager = SplitManager()
        let dashboardViewModel = AgentDashboardViewModel()
        let coordinator = CommandPaletteCoordinatorImpl(
            tabManager: tabManager,
            splitManager: splitManager,
            dashboardViewModel: dashboardViewModel,
            themeEngine: nil
        )

        let engine = CommandPaletteEngineImpl(coordinator: coordinator)

        let initialTabCount = tabManager.tabs.count

        // Find and execute the "New Tab" action.
        guard let newTabAction = engine.allActions.first(where: { $0.id == "tabs.new" }) else {
            XCTFail("Built-in 'tabs.new' action must exist")
            return
        }

        engine.execute(newTabAction)

        XCTAssertEqual(tabManager.tabs.count, initialTabCount + 1,
                        "Executing 'tabs.new' via engine must add a tab through the coordinator")
    }

    // MARK: - Test 6: Engine without coordinator -> safe no-ops

    func testEngineWithoutCoordinatorActionsAreSafeNoOps() {
        let engine = CommandPaletteEngineImpl()

        guard let newTabAction = engine.allActions.first(where: { $0.id == "tabs.new" }) else {
            XCTFail("Built-in 'tabs.new' action must exist even without coordinator")
            return
        }

        // This must not crash -- the handler is a no-op without coordinator.
        engine.execute(newTabAction)

        // Reaching this line means no crash occurred.
        XCTAssertTrue(true, "Executing built-in actions without coordinator must be a safe no-op")
    }

    // MARK: - Test 7 (bonus): Coordinator.closeTab calls TabManager.removeTab

    func testCloseTabCallsTabManagerRemoveTab() {
        let tabManager = TabManager()
        let splitManager = SplitManager()
        let dashboardViewModel = AgentDashboardViewModel()
        let coordinator = CommandPaletteCoordinatorImpl(
            tabManager: tabManager,
            splitManager: splitManager,
            dashboardViewModel: dashboardViewModel,
            themeEngine: nil
        )

        // Add a second tab so we can close one (TabManager won't close the last tab).
        tabManager.addTab()
        let tabCountAfterAdd = tabManager.tabs.count

        coordinator.closeTab()

        XCTAssertEqual(tabManager.tabs.count, tabCountAfterAdd - 1,
                        "closeTab must remove the active tab via TabManager")
    }
}
