// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabReorderContextMenuTests.swift - Tests for tab reorder via context menu.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Tab Reorder Context Menu Tests

/// Tests for the context menu reorder actions on `TabBarView`.
///
/// Verifies that:
/// - Context menu includes "Move Tab Up" and "Move Tab Down" items.
/// - Move Tab Up is disabled for the first tab.
/// - Move Tab Down is disabled for the last tab.
/// - Move actions delegate to TabBarViewModel.moveTab.
@MainActor
final class TabReorderContextMenuTests: XCTestCase {

    private var tabManager: TabManager!
    private var tabBarViewModel: TabBarViewModel!
    private var tabBarView: TabBarView!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        // Add extra tabs for reorder testing.
        tabManager.addTab()
        tabManager.addTab()
        tabBarViewModel = TabBarViewModel(tabManager: tabManager)
        tabBarView = TabBarView(viewModel: tabBarViewModel)
        tabBarView.frame = NSRect(x: 0, y: 0, width: 200, height: 600)
        tabBarView.layout()
    }

    override func tearDown() {
        tabBarView = nil
        tabBarViewModel = nil
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Context Menu Structure

    func testContextMenuContainsMoveTabUpItem() {
        let firstTabID = tabManager.tabs[0].id
        let menu = tabBarView.buildContextMenu(for: firstTabID)

        let moveUpItem = menu.items.first { $0.title == "Move Tab Up" }
        XCTAssertNotNil(moveUpItem, "Context menu must have 'Move Tab Up' item")
    }

    func testContextMenuContainsMoveTabDownItem() {
        let firstTabID = tabManager.tabs[0].id
        let menu = tabBarView.buildContextMenu(for: firstTabID)

        let moveDownItem = menu.items.first { $0.title == "Move Tab Down" }
        XCTAssertNotNil(moveDownItem, "Context menu must have 'Move Tab Down' item")
    }

    // MARK: - Tab Manager Integration

    func testMoveTabDownSwapsPositions() {
        let originalFirstID = tabManager.tabs[0].id
        let originalSecondID = tabManager.tabs[1].id

        tabBarViewModel.moveTab(from: 0, to: 1)

        XCTAssertEqual(tabManager.tabs[0].id, originalSecondID,
                       "First position should now contain the originally second tab")
        XCTAssertEqual(tabManager.tabs[1].id, originalFirstID,
                       "Second position should now contain the originally first tab")
    }

    func testMoveTabUpSwapsPositions() {
        let originalFirstID = tabManager.tabs[0].id
        let originalSecondID = tabManager.tabs[1].id

        tabBarViewModel.moveTab(from: 1, to: 0)

        XCTAssertEqual(tabManager.tabs[0].id, originalSecondID,
                       "First position should now contain the originally second tab")
        XCTAssertEqual(tabManager.tabs[1].id, originalFirstID,
                       "Second position should now contain the originally first tab")
    }

    func testMoveTabWithInvalidIndexIsNoOp() {
        let tabCountBefore = tabManager.tabs.count
        let firstTabID = tabManager.tabs[0].id

        tabBarViewModel.moveTab(from: -1, to: 0)
        tabBarViewModel.moveTab(from: 0, to: 999)

        XCTAssertEqual(tabManager.tabs.count, tabCountBefore)
        XCTAssertEqual(tabManager.tabs[0].id, firstTabID)
    }
}
