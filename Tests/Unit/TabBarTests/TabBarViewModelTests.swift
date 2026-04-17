// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabBarViewModelTests.swift - Tests for TabBarViewModel presentation logic.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Tab Bar View Model Tests

/// Tests for `TabBarViewModel` covering:
/// - Tab list synchronization with TabManager.
/// - Active tab tracking.
/// - Tab selection, closure, and reordering.
/// - Close-other-tabs action.
/// - Tab display item generation.
@MainActor
final class TabBarViewModelTests: XCTestCase {

    private var tabManager: TabManager!
    private var viewModel: TabBarViewModel!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        viewModel = TabBarViewModel(tabManager: tabManager)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        viewModel = nil
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateHasOneTabItem() {
        XCTAssertEqual(viewModel.tabItems.count, 1,
                       "Initial state should have one tab item matching TabManager")
    }

    func testInitialActiveTabIDMatchesTabManager() {
        XCTAssertEqual(viewModel.activeTabID, tabManager.activeTabID,
                       "Active tab ID should match TabManager's active tab")
    }

    // MARK: - Tab Items Sync

    func testTabItemsUpdateWhenTabAdded() {
        _ = tabManager.addTab()

        XCTAssertEqual(viewModel.tabItems.count, 2)
    }

    func testTabItemsUpdateWhenTabRemoved() {
        _ = tabManager.addTab()
        let secondTab = tabManager.addTab()

        tabManager.removeTab(id: secondTab.id)

        XCTAssertEqual(viewModel.tabItems.count, 2)
    }

    // MARK: - Select Tab

    func testSelectTabUpdatesActiveTabInManager() {
        let firstTabID = tabManager.tabs[0].id
        _ = tabManager.addTab()

        viewModel.selectTab(id: firstTabID)

        XCTAssertEqual(tabManager.activeTabID, firstTabID)
    }

    func testSelectTabUpdatesActiveTabIDInViewModel() {
        let firstTabID = tabManager.tabs[0].id
        _ = tabManager.addTab()

        viewModel.selectTab(id: firstTabID)

        XCTAssertEqual(viewModel.activeTabID, firstTabID)
    }

    // MARK: - Close Tab

    func testCloseTabRemovesTabFromManager() {
        _ = tabManager.addTab()
        let secondTab = tabManager.tabs[1]

        viewModel.closeTab(id: secondTab.id)

        XCTAssertNil(tabManager.tab(for: secondTab.id))
    }

    func testCloseTabDoesNotRemoveLastTab() {
        let soleTabID = tabManager.tabs[0].id

        viewModel.closeTab(id: soleTabID)

        XCTAssertEqual(tabManager.tabs.count, 1,
                       "Cannot close the last tab")
    }

    // MARK: - Move Tab

    func testMoveTabReordersInManager() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        _ = tabManager.addTab()

        viewModel.moveTab(from: 0, to: 2)

        XCTAssertEqual(tabManager.tabs[0].id, tabB.id,
                       "Tab B should be at index 0 after moving A to index 2")
        XCTAssertEqual(tabManager.tabs[2].id, tabA.id,
                       "Tab A should be at index 2")
    }

    // MARK: - Add Tab

    func testAddTabCreatesNewTabInManager() {
        let initialCount = tabManager.tabs.count

        viewModel.addNewTab()

        XCTAssertEqual(tabManager.tabs.count, initialCount + 1)
    }

    func testAddTabActivatesNewTab() {
        viewModel.addNewTab()

        let lastTab = tabManager.tabs.last!
        XCTAssertEqual(tabManager.activeTabID, lastTab.id)
    }

    // MARK: - Close Other Tabs

    func testCloseOtherTabsRemovesAllExceptTarget() {
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()
        _ = tabManager.addTab()

        viewModel.closeOtherTabs(except: tabA.id)

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertEqual(tabManager.tabs[0].id, tabA.id)
    }

    func testCloseOtherTabsActivatesKeptTab() {
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()
        let tabC = tabManager.addTab()

        // tabC is active since it was last added.
        XCTAssertEqual(tabManager.activeTabID, tabC.id)

        viewModel.closeOtherTabs(except: tabA.id)

        XCTAssertEqual(tabManager.activeTabID, tabA.id)
    }

    // MARK: - Tab Display Item Properties

    func testTabItemDisplaysTitleFromWorkingDirectory() {
        let projectURL = URL(fileURLWithPath: "/Users/test/MyProject")
        tabManager.updateTab(id: tabManager.tabs[0].id) { tab in
            tab.workingDirectory = projectURL
            tab.gitBranch = nil
        }

        // Force sync.
        viewModel.syncWithManager()

        XCTAssertEqual(viewModel.tabItems[0].displayTitle, "MyProject",
                       "Tab display title should show the working directory name")
    }

    func testTabItemDisplaysSubtitleWithGitBranch() {
        tabManager.updateTab(id: tabManager.tabs[0].id) { tab in
            tab.gitBranch = "main"
            tab.processName = "zsh"
        }

        viewModel.syncWithManager()

        let subtitle = viewModel.tabItems[0].subtitle
        XCTAssertEqual(subtitle, "main \u{2022} zsh")
    }

    func testTabItemStatusColorReflectsAgentState() {
        // The sidebar pill reads per-surface state through the injected
        // resolver closure (Fase 3 refactor). Wire a test-only closure
        // that reports `.working` for the bootstrap tab so the display
        // item surfaces the expected color.
        viewModel.agentStateResolver = { _ in
            SurfaceAgentState(agentState: .working)
        }

        viewModel.syncWithManager()

        XCTAssertEqual(viewModel.tabItems[0].statusColorName, "blue")
    }

    func testTabItemIsActiveMatchesManagerState() {
        _ = tabManager.addTab()

        viewModel.syncWithManager()

        let activeItems = viewModel.tabItems.filter(\.isActive)
        XCTAssertEqual(activeItems.count, 1,
                       "Exactly one tab item should be active")
    }
}
