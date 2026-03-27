// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabBarViewTests.swift - Tests for TabBarView rendering and interaction.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Tab Bar View Tests

/// Tests for `TabBarView` covering:
/// - View initialization and layout.
/// - Visual effect background (vibrancy).
/// - Scroll view wrapping.
/// - New tab button presence.
/// - Context menu items.
/// - Width constraints.
@MainActor
final class TabBarViewTests: XCTestCase {

    private var tabManager: TabManager!
    private var tabBarViewModel: TabBarViewModel!
    private var tabBarView: TabBarView!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        tabBarViewModel = TabBarViewModel(tabManager: tabManager)
        tabBarView = TabBarView(viewModel: tabBarViewModel)
        // Force layout.
        tabBarView.frame = NSRect(x: 0, y: 0, width: 200, height: 600)
        tabBarView.layout()
    }

    override func tearDown() {
        tabBarView = nil
        tabBarViewModel = nil
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testTabBarViewCanBeCreated() {
        XCTAssertNotNil(tabBarView)
    }

    func testTabBarViewHasSolidBackground() {
        let hasBackground = tabBarView.subviews.contains { subview in
            subview.wantsLayer && subview.layer?.backgroundColor != nil
        }
        XCTAssertTrue(hasBackground,
                      "TabBarView should contain a solid background view")
    }

    func testTabBarViewContainsScrollView() {
        let hasScrollView = findSubview(of: NSScrollView.self, in: tabBarView) != nil
        XCTAssertTrue(hasScrollView,
                      "TabBarView should contain a scroll view for tab overflow")
    }

    // MARK: - Dimensions

    func testDefaultWidth() {
        XCTAssertEqual(TabBarView.defaultWidth, 240,
                       "Default width should be 240pt")
    }

    func testMinimumWidth() {
        XCTAssertEqual(TabBarView.minimumWidth, 200,
                       "Minimum width should be 200pt")
    }

    func testMaximumWidth() {
        XCTAssertEqual(TabBarView.maximumWidth, 380,
                       "Maximum width should be 380pt")
    }

    // MARK: - New Tab Button

    func testNewTabButtonExists() {
        let newTabButton = findSubview(of: NSButton.self, in: tabBarView)
        XCTAssertNotNil(newTabButton, "TabBarView should have a new tab button")
    }

    // MARK: - Context Menu

    func testContextMenuForTabHasCloseItem() {
        let menu = tabBarView.buildContextMenu(for: tabManager.tabs[0].id)

        let closeItem = menu.items.first { $0.title == "Close Tab" }
        XCTAssertNotNil(closeItem, "Context menu should have 'Close Tab' item")
    }

    func testContextMenuForTabHasNewTabItem() {
        let menu = tabBarView.buildContextMenu(for: tabManager.tabs[0].id)

        let newTabItem = menu.items.first { $0.title == "New Tab" }
        XCTAssertNotNil(newTabItem, "Context menu should have 'New Tab' item")
    }

    func testContextMenuForTabHasCloseOthersItem() {
        let menu = tabBarView.buildContextMenu(for: tabManager.tabs[0].id)

        let closeOthersItem = menu.items.first { $0.title == "Close Other Tabs" }
        XCTAssertNotNil(closeOthersItem,
                        "Context menu should have 'Close Other Tabs' item")
    }

    func testContextMenuHasSeparator() {
        let menu = tabBarView.buildContextMenu(for: tabManager.tabs[0].id)

        let separators = menu.items.filter { $0.isSeparatorItem }
        XCTAssertGreaterThanOrEqual(separators.count, 1,
                                    "Context menu should have at least one separator")
    }

    // MARK: - Helpers

    /// Recursively finds a subview of the specified type.
    private func findSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        for subview in view.subviews {
            if let found = subview as? T {
                return found
            }
            if let found = findSubview(of: type, in: subview) {
                return found
            }
        }
        return nil
    }
}
