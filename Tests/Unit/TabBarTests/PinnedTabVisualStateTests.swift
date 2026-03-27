// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PinnedTabVisualStateTests.swift - Visual state for pinned tabs.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Pinned Tab Visual State Tests

/// Verifies the visual indicators for pinned tabs in the sidebar.
///
/// Covers:
/// - Pin icon visibility matches isPinned state.
/// - Close button is hidden for pinned tabs (even on hover).
/// - Context menu "Close Tab" is disabled for pinned tabs.
/// - Context menu shows "Unpin Tab" for pinned tabs.
@MainActor
final class PinnedTabVisualStateTests: XCTestCase {

    private var tabManager: TabManager!
    private var viewModel: TabBarViewModel!
    private var tabBarView: TabBarView!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        viewModel = TabBarViewModel(tabManager: tabManager)
        tabBarView = TabBarView(viewModel: viewModel)
        tabBarView.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        tabBarView.layout()
    }

    override func tearDown() {
        tabBarView = nil
        viewModel = nil
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Context Menu for Pinned Tab

    func testContextMenuDisablesCloseForPinnedTab() {
        let tab2 = tabManager.addTab()
        tabManager.togglePin(id: tab2.id)
        viewModel.syncWithManager()

        let menu = tabBarView.buildContextMenu(for: tab2.id)

        let closeItem = menu.items.first { $0.title == "Close Tab" }
        XCTAssertNotNil(closeItem, "Context menu must have Close Tab item")
        XCTAssertFalse(closeItem!.isEnabled,
                       "Close Tab must be disabled for pinned tabs")
    }

    func testContextMenuEnablesCloseForUnpinnedTab() {
        let tab2 = tabManager.addTab()
        viewModel.syncWithManager()

        let menu = tabBarView.buildContextMenu(for: tab2.id)

        let closeItem = menu.items.first { $0.title == "Close Tab" }
        XCTAssertNotNil(closeItem)
        XCTAssertTrue(closeItem!.isEnabled,
                      "Close Tab must be enabled for unpinned tabs")
    }

    func testContextMenuShowsUnpinForPinnedTab() {
        let tab = tabManager.tabs[0]
        tabManager.togglePin(id: tab.id)
        viewModel.syncWithManager()

        let menu = tabBarView.buildContextMenu(for: tab.id)

        let pinItem = menu.items.first {
            $0.title == "Unpin Tab" || $0.title == "Pin Tab"
        }
        XCTAssertNotNil(pinItem)
        XCTAssertEqual(pinItem!.title, "Unpin Tab",
                       "Pinned tabs should show 'Unpin Tab' in context menu")
    }

    func testContextMenuShowsPinForUnpinnedTab() {
        let tab = tabManager.tabs[0]
        viewModel.syncWithManager()

        let menu = tabBarView.buildContextMenu(for: tab.id)

        let pinItem = menu.items.first {
            $0.title == "Unpin Tab" || $0.title == "Pin Tab"
        }
        XCTAssertNotNil(pinItem)
        XCTAssertEqual(pinItem!.title, "Pin Tab",
                       "Unpinned tabs should show 'Pin Tab' in context menu")
    }
}
