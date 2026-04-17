// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabManagerFullTests.swift - Comprehensive tests for TabManager.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Tab Manager Full Tests

/// Comprehensive tests for `TabManager`.
///
/// Covers:
/// - addTab: creates tab, activates it, adds to list.
/// - removeTab: activates next/previous correctly.
/// - removeTab: cannot remove the last tab.
/// - setActive: changes active tab.
/// - moveTab: reorders tabs.
/// - nextTab / previousTab: circular navigation.
/// - updateTab: mutates tab fields.
/// - Invariant: always at least 1 active tab.
@MainActor
final class TabManagerFullTests: XCTestCase {

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateHasOneTab() {
        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertNotNil(tabManager.activeTabID)
        XCTAssertNotNil(tabManager.activeTab)
    }

    func testInitialTabIsActive() {
        let activeTab = tabManager.activeTab
        XCTAssertNotNil(activeTab)
        XCTAssertTrue(activeTab!.isActive)
    }

    // MARK: - Add Tab

    func testAddTabIncreasesCount() {
        let initialCount = tabManager.tabs.count
        _ = tabManager.addTab()

        XCTAssertEqual(tabManager.tabs.count, initialCount + 1)
    }

    func testAddTabActivatesNewTab() {
        let newTab = tabManager.addTab()

        XCTAssertEqual(tabManager.activeTabID, newTab.id)
        XCTAssertTrue(newTab.isActive)
    }

    func testAddTabDeactivatesPreviousTab() {
        let firstTab = tabManager.activeTab!
        _ = tabManager.addTab()

        let firstTabUpdated = tabManager.tab(for: firstTab.id)
        XCTAssertNotNil(firstTabUpdated)
        XCTAssertFalse(firstTabUpdated!.isActive)
    }

    func testAddTabWithCustomWorkingDirectory() {
        let customDir = URL(fileURLWithPath: "/tmp/custom")
        let newTab = tabManager.addTab(workingDirectory: customDir)

        XCTAssertEqual(newTab.workingDirectory, customDir)
    }

    // MARK: - Remove Tab

    func testRemoveTabDecreasesCount() {
        _ = tabManager.addTab()
        let count = tabManager.tabs.count
        let tabToRemove = tabManager.tabs.last!

        tabManager.removeTab(id: tabToRemove.id)

        XCTAssertEqual(tabManager.tabs.count, count - 1)
    }

    func testRemoveActiveTabActivatesNext() {
        // Setup: 3 tabs [A, B, C] with B active.
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // Make B active.
        tabManager.setActive(id: tabB.id)
        XCTAssertEqual(tabManager.activeTabID, tabB.id)

        // Remove B. Should activate C (next).
        tabManager.removeTab(id: tabB.id)

        XCTAssertEqual(tabManager.activeTabID, tabC.id)
        XCTAssertNil(tabManager.tab(for: tabB.id))
        _ = tabA // silence unused warning
    }

    func testRemoveLastPositionTabActivatesPrevious() {
        // Setup: 2 tabs [A, B] with B active (at last position).
        _ = tabManager.tabs[0] // tab A
        let tabB = tabManager.addTab()

        tabManager.setActive(id: tabB.id)

        // Remove B. Should activate A (previous, since B was last).
        tabManager.removeTab(id: tabB.id)

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertNotNil(tabManager.activeTab)
    }

    func testRemoveLastTabDoesNothing() {
        // Only 1 tab exists.
        XCTAssertEqual(tabManager.tabs.count, 1)
        let soleTab = tabManager.tabs[0]

        tabManager.removeTab(id: soleTab.id)

        // Tab is still there.
        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertEqual(tabManager.tabs[0].id, soleTab.id)
    }

    func testRemoveNonExistentTabDoesNothing() {
        let initialCount = tabManager.tabs.count
        let fakeID = TabID()

        tabManager.removeTab(id: fakeID)

        XCTAssertEqual(tabManager.tabs.count, initialCount)
    }

    // MARK: - Set Active

    func testSetActiveChangesActiveTab() {
        let tab1 = tabManager.tabs[0]
        let tab2 = tabManager.addTab()

        tabManager.setActive(id: tab1.id)

        XCTAssertEqual(tabManager.activeTabID, tab1.id)
        XCTAssertTrue(tabManager.tab(for: tab1.id)!.isActive)
        XCTAssertFalse(tabManager.tab(for: tab2.id)!.isActive)
    }

    func testSetActiveWithNonExistentIDDoesNothing() {
        let currentActive = tabManager.activeTabID
        let fakeID = TabID()

        tabManager.setActive(id: fakeID)

        XCTAssertEqual(tabManager.activeTabID, currentActive)
    }

    // MARK: - Move Tab

    func testMoveTabReordersCorrectly() {
        // Setup: 3 tabs [A, B, C].
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()
        _ = tabB // silence unused warning

        // Move C to position 0: [C, A, B].
        tabManager.moveTab(from: 2, to: 0)

        XCTAssertEqual(tabManager.tabs[0].id, tabC.id)
        XCTAssertEqual(tabManager.tabs[1].id, tabA.id)
    }

    func testMoveTabWithInvalidIndicesDoesNothing() {
        let initialOrder = tabManager.tabs.map(\.id)

        tabManager.moveTab(from: -1, to: 0)
        tabManager.moveTab(from: 0, to: 99)

        XCTAssertEqual(tabManager.tabs.map(\.id), initialOrder)
    }

    // MARK: - Next / Previous Tab (Circular)

    func testNextTabCyclesForward() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // C is active. Next should wrap to A.
        tabManager.setActive(id: tabC.id)
        tabManager.nextTab()
        XCTAssertEqual(tabManager.activeTabID, tabA.id)

        // A -> B.
        tabManager.nextTab()
        XCTAssertEqual(tabManager.activeTabID, tabB.id)
    }

    func testPreviousTabCyclesBackward() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // A is active. Previous should wrap to C.
        tabManager.setActive(id: tabA.id)
        tabManager.previousTab()
        XCTAssertEqual(tabManager.activeTabID, tabC.id)

        _ = tabB // silence unused warning
    }

    func testNextTabWithSingleTabStaysSame() {
        let soleTab = tabManager.tabs[0]

        tabManager.nextTab()

        XCTAssertEqual(tabManager.activeTabID, soleTab.id)
    }

    func testPreviousTabWithSingleTabStaysSame() {
        let soleTab = tabManager.tabs[0]

        tabManager.previousTab()

        XCTAssertEqual(tabManager.activeTabID, soleTab.id)
    }

    // MARK: - Update Tab

    func testUpdateTabMutatesFields() {
        let tab = tabManager.tabs[0]

        tabManager.updateTab(id: tab.id) { tab in
            tab.title = "Updated Title"
            tab.gitBranch = "feature/new"
            tab.processName = "claude"
        }

        let updated = tabManager.tab(for: tab.id)!
        XCTAssertEqual(updated.title, "Updated Title")
        XCTAssertEqual(updated.gitBranch, "feature/new")
        XCTAssertEqual(updated.processName, "claude")
    }

    func testUpdateTabWithNonExistentIDDoesNothing() {
        let fakeID = TabID()
        let initialTabs = tabManager.tabs

        tabManager.updateTab(id: fakeID) { tab in
            tab.title = "Should not appear"
        }

        XCTAssertEqual(tabManager.tabs.count, initialTabs.count)
    }

    // MARK: - Tab Lookup

    func testTabForIDReturnsCorrectTab() {
        let tab = tabManager.tabs[0]
        let found = tabManager.tab(for: tab.id)

        XCTAssertNotNil(found)
        XCTAssertEqual(found!.id, tab.id)
    }

    func testTabForNonExistentIDReturnsNil() {
        let result = tabManager.tab(for: TabID())

        XCTAssertNil(result)
    }

    // MARK: - Active Tab Computed Property

    func testActiveTabComputedProperty() {
        let tab = tabManager.addTab()

        XCTAssertEqual(tabManager.activeTab?.id, tab.id)
    }
}
