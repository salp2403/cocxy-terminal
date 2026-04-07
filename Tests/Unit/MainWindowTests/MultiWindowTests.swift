// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MultiWindowTests.swift - Tests for multi-window support.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Multi-Window Tests

/// Tests for multi-window support in `MainWindowController` and `AppDelegate`.
///
/// Verifies that:
/// - MainWindowController responds to the newWindowAction selector.
/// - AppDelegate tracks additional window controllers.
/// - Multiple windows can be created without crashing.
@MainActor
final class MultiWindowTests: XCTestCase {

    func testMainWindowControllerRespondsToNewWindowAction() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertTrue(
            controller.responds(to: #selector(MainWindowController.newWindowAction(_:))),
            "MainWindowController must respond to newWindowAction"
        )
    }

    func testAppDelegateHasAdditionalWindowControllersArray() {
        let delegate = AppDelegate()

        XCTAssertNotNil(
            delegate.additionalWindowControllers,
            "AppDelegate must expose additionalWindowControllers"
        )
        XCTAssertTrue(
            delegate.additionalWindowControllers.isEmpty,
            "Additional window controllers should start empty"
        )
    }

    func testWindowControllerTabRouterTargetsTheOwningWindow() {
        let delegate = AppDelegate()
        let windowA = MainWindowController(bridge: MockTerminalEngine())
        let windowB = MainWindowController(bridge: MockTerminalEngine())
        delegate.additionalWindowControllers = [windowA, windowB]

        let firstWindowBTab = windowB.tabManager.tabs.first!.id
        windowB.newTabAction(nil)
        let secondWindowBTab = windowB.tabManager.activeTabID!

        let router = WindowControllerTabRouter(appDelegate: delegate)
        let handled = router.focusTab(id: firstWindowBTab)

        XCTAssertTrue(handled, "Router must report success for a tab owned by another window")
        XCTAssertEqual(windowB.tabManager.activeTabID, firstWindowBTab,
                       "Router must activate the target tab in its owning window")
        XCTAssertEqual(windowA.tabManager.activeTabID, windowA.tabManager.tabs.first?.id,
                       "Routing to window B must not disturb window A")
        XCTAssertNotEqual(windowB.tabManager.activeTabID, secondWindowBTab,
                          "Window B must switch away from its previously active tab")
    }
}
