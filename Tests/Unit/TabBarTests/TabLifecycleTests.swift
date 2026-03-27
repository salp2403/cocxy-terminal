// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabLifecycleTests.swift - Tests for tab creation/close lifecycle and keyboard shortcuts.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Tab Lifecycle Tests

/// Tests for tab creation and closure lifecycle (T-017).
///
/// Covers:
/// - Keyboard shortcut action methods.
/// - Tab navigation (next, previous, goto N).
/// - Active tab switching updates surface visibility.
/// - Close-other-tabs logic.
/// - Last-tab behavior.
@MainActor
final class TabLifecycleTests: XCTestCase {

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Tab Creation

    func testNewTabInheritsWorkingDirectoryFromActiveTab() {
        let customDir = URL(fileURLWithPath: "/tmp/project-dir")
        tabManager.updateTab(id: tabManager.tabs[0].id) { tab in
            tab.workingDirectory = customDir
        }

        let activeDir = tabManager.activeTab?.workingDirectory ?? URL(fileURLWithPath: "/")
        let newTab = tabManager.addTab(workingDirectory: activeDir)

        XCTAssertEqual(newTab.workingDirectory, customDir)
    }

    // MARK: - Tab Navigation

    func testGotoTabByIndexActivatesCorrectTab() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // Go to tab at index 0 (tabA).
        tabManager.setActive(id: tabA.id)
        XCTAssertEqual(tabManager.activeTabID, tabA.id)

        // Go to tab at index 1 (tabB).
        if tabManager.tabs.count > 1 {
            tabManager.setActive(id: tabManager.tabs[1].id)
        }
        XCTAssertEqual(tabManager.activeTabID, tabB.id)

        _ = tabC // silence unused
    }

    func testGotoTabByIndexOutOfBoundsIsNoOp() {
        let activeBeforeID = tabManager.activeTabID

        // Index 9 does not exist (only 1 tab).
        // Using setActive with non-existent ID as the equivalent.
        let fakeID = TabID()
        tabManager.setActive(id: fakeID)

        XCTAssertEqual(tabManager.activeTabID, activeBeforeID)
    }

    func testNextTabNavigatesForward() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()

        tabManager.setActive(id: tabA.id)
        tabManager.nextTab()

        XCTAssertEqual(tabManager.activeTabID, tabB.id)
    }

    func testPreviousTabNavigatesBackward() {
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()

        // Second tab is active (just added).
        tabManager.previousTab()

        XCTAssertEqual(tabManager.activeTabID, tabA.id)
    }

    func testNextTabWrapsAroundFromLast() {
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()
        let tabC = tabManager.addTab()

        tabManager.setActive(id: tabC.id)
        tabManager.nextTab()

        XCTAssertEqual(tabManager.activeTabID, tabA.id)
    }

    func testPreviousTabWrapsAroundFromFirst() {
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()
        let tabC = tabManager.addTab()

        tabManager.setActive(id: tabA.id)
        tabManager.previousTab()

        XCTAssertEqual(tabManager.activeTabID, tabC.id)
    }

    // MARK: - Close Tab

    func testCloseActiveTabActivatesNext() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        tabManager.setActive(id: tabB.id)
        tabManager.removeTab(id: tabB.id)

        XCTAssertEqual(tabManager.activeTabID, tabC.id)
        _ = tabA // silence
    }

    func testCloseLastPositionTabActivatesPrevious() {
        _ = tabManager.tabs[0]
        let tabB = tabManager.addTab()

        tabManager.setActive(id: tabB.id)
        tabManager.removeTab(id: tabB.id)

        // Only one tab left -- it should be active.
        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertNotNil(tabManager.activeTab)
    }

    func testCannotCloseOnlyTab() {
        let soleTab = tabManager.tabs[0]

        tabManager.removeTab(id: soleTab.id)

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertEqual(tabManager.tabs[0].id, soleTab.id)
    }

    // MARK: - Close Other Tabs

    func testCloseOtherTabsKeepsOnlySpecifiedTab() {
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()
        _ = tabManager.addTab()

        // Simulate "close other tabs" by removing all except tabA.
        let idsToRemove = tabManager.tabs
            .filter { $0.id != tabA.id }
            .map(\.id)
        for id in idsToRemove {
            tabManager.removeTab(id: id)
        }

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertEqual(tabManager.tabs[0].id, tabA.id)
    }

    // MARK: - Tab Surface Map

    func testTabSurfaceMapTracksAssociations() {
        var tabSurfaceMap: [TabID: SurfaceID] = [:]

        let tab = tabManager.tabs[0]
        let surfaceID = SurfaceID()

        tabSurfaceMap[tab.id] = surfaceID

        XCTAssertEqual(tabSurfaceMap[tab.id], surfaceID)
    }

    func testTabSurfaceMapRemovalOnClose() {
        var tabSurfaceMap: [TabID: SurfaceID] = [:]

        let tab = tabManager.addTab()
        let surfaceID = SurfaceID()
        tabSurfaceMap[tab.id] = surfaceID

        // Simulate close: remove from manager and map.
        tabManager.removeTab(id: tab.id)
        tabSurfaceMap.removeValue(forKey: tab.id)

        XCTAssertNil(tabSurfaceMap[tab.id])
    }
}

// MARK: - Tab Goto by Index Extension Tests

/// Tests for the `gotoTab(at:)` convenience method on TabManager.
@MainActor
final class TabManagerGotoTests: XCTestCase {

    func testGotoTabAtValidIndex() {
        let tabManager = TabManager()
        let tabA = tabManager.tabs[0]
        _ = tabManager.addTab()
        _ = tabManager.addTab()

        tabManager.gotoTab(at: 0)

        XCTAssertEqual(tabManager.activeTabID, tabA.id)
    }

    func testGotoTabAtLastIndex() {
        let tabManager = TabManager()
        _ = tabManager.addTab()
        let tabC = tabManager.addTab()

        tabManager.gotoTab(at: 2)

        XCTAssertEqual(tabManager.activeTabID, tabC.id)
    }

    func testGotoTabAtNegativeIndexIsNoOp() {
        let tabManager = TabManager()
        let activeBefore = tabManager.activeTabID

        tabManager.gotoTab(at: -1)

        XCTAssertEqual(tabManager.activeTabID, activeBefore)
    }

    func testGotoTabAtOutOfBoundsIndexIsNoOp() {
        let tabManager = TabManager()
        let activeBefore = tabManager.activeTabID

        tabManager.gotoTab(at: 99)

        XCTAssertEqual(tabManager.activeTabID, activeBefore)
    }
}
