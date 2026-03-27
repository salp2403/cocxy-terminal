// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuActionWiringTests.swift - Tests that menu items are wired to actual actions.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Menu Action Wiring Tests

/// Tests that menu items previously set to `action: nil` are now wired
/// to their corresponding @objc action methods.
///
/// Each test verifies that the menu item's `action` selector is non-nil
/// and points to the correct method on MainWindowController.
@MainActor
final class MenuActionWiringTests: XCTestCase {

    private var viewMenu: NSMenu!
    private var fileMenu: NSMenu!
    private var helpMenu: NSMenu!

    override func setUp() {
        super.setUp()
        let delegate = AppDelegate()
        delegate.setupMainMenuForTesting()

        let mainMenu = NSApplication.shared.mainMenu
        viewMenu = mainMenu?.items.first(where: { $0.submenu?.title == "View" })?.submenu
        fileMenu = mainMenu?.items.first(where: { $0.submenu?.title == "File" })?.submenu
        helpMenu = mainMenu?.items.first(where: { $0.submenu?.title == "Help" })?.submenu
    }

    override func tearDown() {
        viewMenu = nil
        fileMenu = nil
        helpMenu = nil
        super.tearDown()
    }

    // MARK: - Zoom In

    func testZoomInHasAction() {
        let zoomIn = viewMenu.items.first(where: { $0.title == "Zoom In" })
        XCTAssertNotNil(
            zoomIn?.action,
            "Zoom In menu item must have a non-nil action"
        )
    }

    func testZoomInActionPointsToCorrectSelector() {
        let zoomIn = viewMenu.items.first(where: { $0.title == "Zoom In" })
        XCTAssertEqual(
            zoomIn?.action,
            #selector(MainWindowController.zoomInAction(_:)),
            "Zoom In must be wired to zoomInAction:"
        )
    }

    // MARK: - Zoom Out

    func testZoomOutHasAction() {
        let zoomOut = viewMenu.items.first(where: { $0.title == "Zoom Out" })
        XCTAssertNotNil(
            zoomOut?.action,
            "Zoom Out menu item must have a non-nil action"
        )
    }

    func testZoomOutActionPointsToCorrectSelector() {
        let zoomOut = viewMenu.items.first(where: { $0.title == "Zoom Out" })
        XCTAssertEqual(
            zoomOut?.action,
            #selector(MainWindowController.zoomOutAction(_:)),
            "Zoom Out must be wired to zoomOutAction:"
        )
    }

    // MARK: - Reset Zoom

    func testResetZoomHasAction() {
        let resetZoom = viewMenu.items.first(where: { $0.title == "Reset Zoom" })
        XCTAssertNotNil(
            resetZoom?.action,
            "Reset Zoom menu item must have a non-nil action"
        )
    }

    func testResetZoomActionPointsToCorrectSelector() {
        let resetZoom = viewMenu.items.first(where: { $0.title == "Reset Zoom" })
        XCTAssertEqual(
            resetZoom?.action,
            #selector(MainWindowController.resetZoomAction(_:)),
            "Reset Zoom must be wired to resetZoomAction:"
        )
    }

    // MARK: - Toggle Tab Bar

    func testToggleTabBarHasAction() {
        let toggleTab = viewMenu.items.first(where: { $0.title == "Toggle Tab Bar" })
        XCTAssertNotNil(
            toggleTab?.action,
            "Toggle Tab Bar menu item must have a non-nil action"
        )
    }

    func testToggleTabBarActionPointsToCorrectSelector() {
        let toggleTab = viewMenu.items.first(where: { $0.title == "Toggle Tab Bar" })
        XCTAssertEqual(
            toggleTab?.action,
            #selector(MainWindowController.toggleTabBarAction(_:)),
            "Toggle Tab Bar must be wired to toggleTabBarAction:"
        )
    }

    // MARK: - New Window

    func testNewWindowHasAction() {
        let newWindow = fileMenu.items.first(where: { $0.title == "New Window" })
        XCTAssertNotNil(
            newWindow?.action,
            "New Window menu item must have a non-nil action"
        )
    }

    func testNewWindowActionPointsToCorrectSelector() {
        let newWindow = fileMenu.items.first(where: { $0.title == "New Window" })
        XCTAssertEqual(
            newWindow?.action,
            #selector(MainWindowController.newWindowAction(_:)),
            "New Window must be wired to newWindowAction:"
        )
    }

    // MARK: - Help

    func testHelpHasAction() {
        let help = helpMenu?.items.first(where: { $0.title == "Cocxy Terminal Help" })
        XCTAssertNotNil(
            help?.action,
            "Help menu item must have a non-nil action"
        )
    }

    func testHelpActionPointsToCorrectSelector() {
        let help = helpMenu?.items.first(where: { $0.title == "Cocxy Terminal Help" })
        XCTAssertEqual(
            help?.action,
            #selector(MainWindowController.showWelcomeAction(_:)),
            "Help must be wired to showWelcomeAction:"
        )
    }
}

// MARK: - Zoom Action Behavior Tests

/// Tests that the zoom @objc methods on MainWindowController correctly
/// delegate to the TerminalViewModel's zoom methods.
@MainActor
final class ZoomActionBehaviorTests: XCTestCase {

    func testZoomInIncreasesFontSize() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        let initialSize = controller.terminalViewModel.currentFontSize

        controller.zoomInAction(nil)

        XCTAssertGreaterThan(
            controller.terminalViewModel.currentFontSize,
            initialSize,
            "zoomInAction must increase the font size"
        )
    }

    func testZoomOutDecreasesFontSize() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        // Zoom in first so we have room to zoom out.
        controller.zoomInAction(nil)
        controller.zoomInAction(nil)
        let afterZoomIn = controller.terminalViewModel.currentFontSize

        controller.zoomOutAction(nil)

        XCTAssertLessThan(
            controller.terminalViewModel.currentFontSize,
            afterZoomIn,
            "zoomOutAction must decrease the font size"
        )
    }

    func testResetZoomRestoresDefaultFontSize() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        let defaultSize = controller.terminalViewModel.currentFontSize

        // Change the size.
        controller.zoomInAction(nil)
        controller.zoomInAction(nil)
        controller.zoomInAction(nil)

        XCTAssertNotEqual(
            controller.terminalViewModel.currentFontSize,
            defaultSize,
            "Font size must change after zooming in"
        )

        // Reset.
        controller.resetZoomAction(nil)

        XCTAssertEqual(
            controller.terminalViewModel.currentFontSize,
            defaultSize,
            "resetZoomAction must restore the default font size"
        )
    }
}

// MARK: - Tab Bar Toggle Tests

/// Tests that toggleTabBarAction correctly hides and shows the sidebar.
@MainActor
final class TabBarToggleTests: XCTestCase {

    func testTabBarIsVisibleByDefault() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertFalse(
            controller.isTabBarHidden,
            "Tab bar must be visible by default"
        )
    }

    func testToggleTabBarHidesSidebar() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleTabBarAction(nil)

        XCTAssertTrue(
            controller.isTabBarHidden,
            "Toggle tab bar must hide the sidebar on first call"
        )
    }

    func testToggleTabBarTwiceRestoresSidebar() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleTabBarAction(nil)
        controller.toggleTabBarAction(nil)

        XCTAssertFalse(
            controller.isTabBarHidden,
            "Toggle tab bar twice must restore sidebar visibility"
        )
    }
}

// MARK: - OSC Notification Forwarding Tests

/// Tests that the MainWindowController has an injectable notification manager
/// for forwarding OSC notifications.
@MainActor
final class OSCNotificationForwardingTests: XCTestCase {

    func testInjectedNotificationManagerIsNilByDefault() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertNil(
            controller.injectedNotificationManager,
            "Injected notification manager must be nil by default"
        )
    }

    func testInjectedNotificationManagerCanBeSet() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        let config = CocxyConfig.defaults
        let emitter = StubSystemNotificationEmitter()
        let manager = NotificationManagerImpl(
            config: config,
            systemEmitter: emitter
        )

        controller.injectedNotificationManager = manager

        XCTAssertNotNil(
            controller.injectedNotificationManager,
            "Injected notification manager must be settable"
        )
    }
}

// MARK: - Stub for tests

/// Minimal stub for SystemNotificationEmitting used only in tests.
@MainActor
private final class StubSystemNotificationEmitter: SystemNotificationEmitting {
    var emittedNotifications: [CocxyNotification] = []

    func emit(_ notification: CocxyNotification) {
        emittedNotifications.append(notification)
    }
}
