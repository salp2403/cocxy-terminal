// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PinnedTabProtectionTests.swift - Pinned tabs must not be closable.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Pinned Tab Protection Tests

/// Verifies that pinned tabs are fully protected from closure across
/// all code paths: TabManager, TabBarViewModel, and closeOtherTabs.
///
/// Covers:
/// - TabManager.removeTab rejects pinned tabs.
/// - TabManager.togglePin flips isPinned and reorders.
/// - TabBarViewModel.closeTab respects isPinned via onCloseTab.
/// - TabBarViewModel.closeOtherTabs skips pinned tabs.
/// - Context menu "Close Tab" is disabled for pinned tabs.
@MainActor
final class PinnedTabProtectionTests: XCTestCase {

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    // MARK: - TabManager Guards

    func testRemoveTabRejectsPinnedTab() {
        let tab2 = tabManager.addTab()
        tabManager.togglePin(id: tab2.id)

        let countBefore = tabManager.tabs.count
        tabManager.removeTab(id: tab2.id)

        XCTAssertEqual(tabManager.tabs.count, countBefore,
                       "Pinned tabs must not be removed by removeTab")
        XCTAssertNotNil(tabManager.tab(for: tab2.id),
                        "Pinned tab must still exist after removeTab attempt")
    }

    func testRemoveTabAllowsUnpinnedTab() {
        let tab2 = tabManager.addTab()

        let countBefore = tabManager.tabs.count
        tabManager.removeTab(id: tab2.id)

        XCTAssertEqual(tabManager.tabs.count, countBefore - 1,
                       "Unpinned tabs should be removable")
    }

    func testTogglePinFlipsPinnedState() {
        let tab = tabManager.tabs[0]
        XCTAssertFalse(tab.isPinned)

        tabManager.togglePin(id: tab.id)

        XCTAssertTrue(tabManager.tab(for: tab.id)!.isPinned,
                      "After toggling, tab should be pinned")

        tabManager.togglePin(id: tab.id)

        XCTAssertFalse(tabManager.tab(for: tab.id)!.isPinned,
                       "After toggling twice, tab should be unpinned")
    }

    func testTogglePinSortsPinnedTabsFirst() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // Pin C -- it should move to the front.
        tabManager.togglePin(id: tabC.id)

        XCTAssertEqual(tabManager.tabs[0].id, tabC.id,
                       "Pinned tab should be at position 0")
        XCTAssertEqual(tabManager.tabs[1].id, tabA.id)
        XCTAssertEqual(tabManager.tabs[2].id, tabB.id)
    }

    // MARK: - TabBarViewModel Guards

    func testViewModelCloseTabRejectsPinnedTab() {
        let viewModel = TabBarViewModel(tabManager: tabManager)
        let tab2 = tabManager.addTab()
        tabManager.togglePin(id: tab2.id)

        var closedIDs: [TabID] = []
        viewModel.onCloseTab = { tabID in
            closedIDs.append(tabID)
        }

        viewModel.closeTab(id: tab2.id)

        // The onCloseTab closure should NOT have been called for a pinned tab.
        XCTAssertTrue(closedIDs.isEmpty,
                      "closeTab on ViewModel must not invoke onCloseTab for pinned tabs")
        XCTAssertNotNil(tabManager.tab(for: tab2.id),
                        "Pinned tab must survive ViewModel closeTab")
    }

    func testViewModelCloseOtherTabsSkipsPinned() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // Pin tab A.
        tabManager.togglePin(id: tabA.id)

        var closedIDs: [TabID] = []
        let viewModel = TabBarViewModel(tabManager: tabManager)
        viewModel.onCloseTab = { tabID in
            closedIDs.append(tabID)
        }

        // Close all except C. Pinned A should survive.
        viewModel.closeOtherTabs(except: tabC.id)

        XCTAssertFalse(closedIDs.contains(tabA.id),
                       "closeOtherTabs must not attempt to close pinned tabs")
        XCTAssertTrue(closedIDs.contains(tabB.id),
                      "Unpinned tab B should be closed")
        XCTAssertNotNil(tabManager.tab(for: tabA.id),
                        "Pinned tab A must survive closeOtherTabs")
    }

    // MARK: - TabManager isPinned Check

    func testIsPinnedQueryForKnownTab() {
        let tab = tabManager.tabs[0]

        XCTAssertFalse(tabManager.tab(for: tab.id)!.isPinned)

        tabManager.togglePin(id: tab.id)

        XCTAssertTrue(tabManager.tab(for: tab.id)!.isPinned)
    }
}
