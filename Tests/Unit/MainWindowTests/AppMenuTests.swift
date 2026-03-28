// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppMenuTests.swift - Tests for the application menu bar structure (T-012).

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Menu Structure Tests

/// Tests that the application menu has the correct top-level structure.
@MainActor
final class AppMenuStructureTests: XCTestCase {

    private var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
        // Trigger menu setup without full app launch.
        appDelegate.setupMainMenuForTesting()
    }

    override func tearDown() {
        appDelegate = nil
        super.tearDown()
    }

    func testMainMenuHasSixTopLevelMenus() {
        let mainMenu = NSApplication.shared.mainMenu
        XCTAssertNotNil(mainMenu, "Main menu must exist")

        // App, File, Edit, View, Window, Help = 6
        XCTAssertEqual(
            mainMenu?.items.count,
            6,
            "Main menu must have exactly 6 top-level items"
        )
    }

    func testFileMenuExists() {
        let mainMenu = NSApplication.shared.mainMenu
        let fileMenu = mainMenu?.items.first(where: { $0.submenu?.title == "File" })
        XCTAssertNotNil(fileMenu, "File menu must exist")
    }

    func testEditMenuExists() {
        let mainMenu = NSApplication.shared.mainMenu
        let editMenu = mainMenu?.items.first(where: { $0.submenu?.title == "Edit" })
        XCTAssertNotNil(editMenu, "Edit menu must exist")
    }

    func testViewMenuExists() {
        let mainMenu = NSApplication.shared.mainMenu
        let viewMenu = mainMenu?.items.first(where: { $0.submenu?.title == "View" })
        XCTAssertNotNil(viewMenu, "View menu must exist")
    }

    func testWindowMenuExists() {
        let mainMenu = NSApplication.shared.mainMenu
        let windowMenu = mainMenu?.items.first(where: { $0.submenu?.title == "Window" })
        XCTAssertNotNil(windowMenu, "Window menu must exist")
    }

    func testHelpMenuExists() {
        let mainMenu = NSApplication.shared.mainMenu
        let helpMenu = mainMenu?.items.first(where: { $0.submenu?.title == "Help" })
        XCTAssertNotNil(helpMenu, "Help menu must exist")
    }
}

// MARK: - File Menu Tests

/// Tests that the File menu has the correct items and shortcuts.
@MainActor
final class FileMenuItemTests: XCTestCase {

    private var fileMenu: NSMenu!

    override func setUp() {
        super.setUp()
        let delegate = AppDelegate()
        delegate.setupMainMenuForTesting()
        fileMenu = NSApplication.shared.mainMenu?.items
            .first(where: { $0.submenu?.title == "File" })?.submenu
    }

    override func tearDown() {
        fileMenu = nil
        super.tearDown()
    }

    func testFileMenuHasNewTabItem() {
        let newTab = fileMenu.items.first(where: { $0.title == "New Tab" })
        XCTAssertNotNil(newTab, "File menu must have 'New Tab' item")
    }

    func testNewTabHasCorrectShortcut() {
        let newTab = fileMenu.items.first(where: { $0.title == "New Tab" })
        XCTAssertEqual(newTab?.keyEquivalent, "t", "New Tab shortcut must be Cmd+T")
    }

    func testFileMenuHasNewWindowItem() {
        let newWindow = fileMenu.items.first(where: { $0.title == "New Window" })
        XCTAssertNotNil(newWindow, "File menu must have 'New Window' item")
    }

    func testNewWindowHasCorrectShortcut() {
        let newWindow = fileMenu.items.first(where: { $0.title == "New Window" })
        XCTAssertEqual(newWindow?.keyEquivalent, "n", "New Window shortcut must be Cmd+N")
    }

    func testFileMenuHasCloseTabItem() {
        let closeTab = fileMenu.items.first(where: { $0.title == "Close Tab" })
        XCTAssertNotNil(closeTab, "File menu must have 'Close Tab' item")
    }

    func testCloseTabHasCorrectShortcut() {
        let closeTab = fileMenu.items.first(where: { $0.title == "Close Tab" })
        XCTAssertEqual(closeTab?.keyEquivalent, "w", "Close Tab shortcut must be Cmd+W")
    }
}

// MARK: - Edit Menu Tests

/// Tests that the Edit menu has the correct items and shortcuts.
@MainActor
final class EditMenuItemTests: XCTestCase {

    private var editMenu: NSMenu!

    override func setUp() {
        super.setUp()
        let delegate = AppDelegate()
        delegate.setupMainMenuForTesting()
        editMenu = NSApplication.shared.mainMenu?.items
            .first(where: { $0.submenu?.title == "Edit" })?.submenu
    }

    override func tearDown() {
        editMenu = nil
        super.tearDown()
    }

    func testEditMenuHasCopyItem() {
        let copy = editMenu.items.first(where: { $0.title == "Copy" })
        XCTAssertNotNil(copy, "Edit menu must have 'Copy' item")
    }

    func testCopyHasCorrectShortcut() {
        let copy = editMenu.items.first(where: { $0.title == "Copy" })
        XCTAssertEqual(copy?.keyEquivalent, "c", "Copy shortcut must be Cmd+C")
    }

    func testEditMenuHasPasteItem() {
        let paste = editMenu.items.first(where: { $0.title == "Paste" })
        XCTAssertNotNil(paste, "Edit menu must have 'Paste' item")
    }

    func testPasteHasCorrectShortcut() {
        let paste = editMenu.items.first(where: { $0.title == "Paste" })
        XCTAssertEqual(paste?.keyEquivalent, "v", "Paste shortcut must be Cmd+V")
    }

    func testEditMenuHasSelectAllItem() {
        let selectAll = editMenu.items.first(where: { $0.title == "Select All" })
        XCTAssertNotNil(selectAll, "Edit menu must have 'Select All' item")
    }

    func testSelectAllHasCorrectShortcut() {
        let selectAll = editMenu.items.first(where: { $0.title == "Select All" })
        XCTAssertEqual(selectAll?.keyEquivalent, "a", "Select All shortcut must be Cmd+A")
    }

    func testEditMenuHasFindItem() {
        let find = editMenu.items.first(where: { $0.title == "Find..." })
        XCTAssertNotNil(find, "Edit menu must have 'Find...' item")
    }

    func testFindHasCorrectShortcut() {
        let find = editMenu.items.first(where: { $0.title == "Find..." })
        XCTAssertEqual(find?.keyEquivalent, "f", "Find shortcut must be Cmd+F")
    }
}

// MARK: - View Menu Tests

/// Tests that the View menu has the correct items and shortcuts.
@MainActor
final class ViewMenuItemTests: XCTestCase {

    private var viewMenu: NSMenu!

    override func setUp() {
        super.setUp()
        let delegate = AppDelegate()
        delegate.setupMainMenuForTesting()
        viewMenu = NSApplication.shared.mainMenu?.items
            .first(where: { $0.submenu?.title == "View" })?.submenu
    }

    override func tearDown() {
        viewMenu = nil
        super.tearDown()
    }

    func testViewMenuHasToggleFullScreenItem() {
        let fullScreen = viewMenu.items.first(where: {
            $0.title.contains("Full Screen")
        })
        XCTAssertNotNil(fullScreen, "View menu must have a Full Screen item")
    }

    func testViewMenuHasZoomInItem() {
        let zoomIn = viewMenu.items.first(where: { $0.title == "Zoom In" })
        XCTAssertNotNil(zoomIn, "View menu must have 'Zoom In' item")
    }

    func testZoomInHasCorrectShortcut() {
        let zoomIn = viewMenu.items.first(where: { $0.title == "Zoom In" })
        XCTAssertEqual(zoomIn?.keyEquivalent, "+", "Zoom In shortcut must be Cmd++")
    }

    func testViewMenuHasZoomOutItem() {
        let zoomOut = viewMenu.items.first(where: { $0.title == "Zoom Out" })
        XCTAssertNotNil(zoomOut, "View menu must have 'Zoom Out' item")
    }

    func testZoomOutHasCorrectShortcut() {
        let zoomOut = viewMenu.items.first(where: { $0.title == "Zoom Out" })
        XCTAssertEqual(zoomOut?.keyEquivalent, "-", "Zoom Out shortcut must be Cmd+-")
    }

    func testViewMenuHasResetZoomItem() {
        let resetZoom = viewMenu.items.first(where: { $0.title == "Reset Zoom" })
        XCTAssertNotNil(resetZoom, "View menu must have 'Reset Zoom' item")
    }

    func testResetZoomHasCorrectShortcut() {
        let resetZoom = viewMenu.items.first(where: { $0.title == "Reset Zoom" })
        XCTAssertEqual(resetZoom?.keyEquivalent, "0", "Reset Zoom shortcut must be Cmd+0")
    }
}

// MARK: - Window Menu Tests

/// Tests that the Window menu has the correct items.
@MainActor
final class WindowMenuItemTests: XCTestCase {

    private var windowMenu: NSMenu!

    override func setUp() {
        super.setUp()
        let delegate = AppDelegate()
        delegate.setupMainMenuForTesting()
        windowMenu = NSApplication.shared.mainMenu?.items
            .first(where: { $0.submenu?.title == "Window" })?.submenu
    }

    override func tearDown() {
        windowMenu = nil
        super.tearDown()
    }

    func testWindowMenuHasMinimizeItem() {
        let minimize = windowMenu.items.first(where: { $0.title == "Minimize" })
        XCTAssertNotNil(minimize, "Window menu must have 'Minimize' item")
    }

    func testMinimizeHasCorrectShortcut() {
        let minimize = windowMenu.items.first(where: { $0.title == "Minimize" })
        XCTAssertEqual(minimize?.keyEquivalent, "m", "Minimize shortcut must be Cmd+M")
    }

    func testWindowMenuHasZoomItem() {
        let zoom = windowMenu.items.first(where: { $0.title == "Zoom" })
        XCTAssertNotNil(zoom, "Window menu must have 'Zoom' item")
    }

    func testWindowMenuHasBringAllToFrontItem() {
        let bringAll = windowMenu.items.first(where: { $0.title == "Bring All to Front" })
        XCTAssertNotNil(bringAll, "Window menu must have 'Bring All to Front' item")
    }
}

// MARK: - Application Menu Tests

/// Tests that the application (first) menu has the correct items.
@MainActor
final class ApplicationMenuItemTests: XCTestCase {

    private var appMenu: NSMenu!

    override func setUp() {
        super.setUp()
        let delegate = AppDelegate()
        delegate.setupMainMenuForTesting()
        appMenu = NSApplication.shared.mainMenu?.items.first?.submenu
    }

    override func tearDown() {
        appMenu = nil
        super.tearDown()
    }

    func testAppMenuHasAboutItem() {
        let about = appMenu.items.first(where: { $0.title.contains("About") })
        XCTAssertNotNil(about, "App menu must have an 'About' item")
    }

    func testAppMenuHasPreferencesItem() {
        let prefs = appMenu.items.first(where: { $0.title.contains("Settings") || $0.title.contains("Preferences") })
        XCTAssertNotNil(prefs, "App menu must have a 'Settings' or 'Preferences' item")
    }

    func testPreferencesHasCorrectShortcut() {
        let prefs = appMenu.items.first(where: { $0.title.contains("Settings") || $0.title.contains("Preferences") })
        XCTAssertEqual(prefs?.keyEquivalent, ",", "Settings shortcut must be Cmd+,")
    }

    func testAppMenuHasHideItem() {
        let hide = appMenu.items.first(where: { $0.title.contains("Hide Cocxy") })
        XCTAssertNotNil(hide, "App menu must have a 'Hide' item")
    }

    func testHideHasCorrectShortcut() {
        let hide = appMenu.items.first(where: { $0.title.contains("Hide Cocxy") })
        XCTAssertEqual(hide?.keyEquivalent, "h", "Hide shortcut must be Cmd+H")
    }

    func testAppMenuHasQuitItem() {
        let quit = appMenu.items.first(where: { $0.title.contains("Quit") })
        XCTAssertNotNil(quit, "App menu must have a 'Quit' item")
    }

    func testQuitHasCorrectShortcut() {
        let quit = appMenu.items.first(where: { $0.title.contains("Quit") })
        XCTAssertEqual(quit?.keyEquivalent, "q", "Quit shortcut must be Cmd+Q")
    }
}
