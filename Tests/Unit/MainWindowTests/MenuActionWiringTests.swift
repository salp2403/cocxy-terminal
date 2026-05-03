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

    // MARK: - Discoverable Panels

    func testRemoteWorkspacesHasAction() {
        let remote = viewMenu.items.first(where: { $0.title == "Remote Workspaces..." })
        XCTAssertNotNil(
            remote?.action,
            "Remote Workspaces must be discoverable from the View menu"
        )
    }

    func testRemoteWorkspacesActionPointsToCorrectSelector() {
        let remote = viewMenu.items.first(where: { $0.title == "Remote Workspaces..." })
        XCTAssertEqual(
            remote?.action,
            #selector(MainWindowController.toggleRemoteWorkspacePanelAction(_:)),
            "Remote Workspaces must open the real remote workspace panel"
        )
    }

    func testOpenMarkdownPanelHasAction() {
        let markdown = viewMenu.items.first(where: { $0.title == "Open Markdown Panel" })
        XCTAssertNotNil(
            markdown?.action,
            "Open Markdown Panel must be discoverable from the View menu"
        )
    }

    func testOpenMarkdownPanelActionPointsToCorrectSelector() {
        let markdown = viewMenu.items.first(where: { $0.title == "Open Markdown Panel" })
        XCTAssertEqual(
            markdown?.action,
            #selector(MainWindowController.splitWithMarkdownAction(_:)),
            "Open Markdown Panel must create the real markdown split panel"
        )
    }

    func testOpenTextEditorPanelHasAction() {
        let editor = viewMenu.items.first(where: { $0.title == "Open Text Editor Panel" })
        XCTAssertNotNil(
            editor?.action,
            "Open Text Editor Panel must be discoverable from the View menu"
        )
    }

    func testOpenTextEditorPanelActionPointsToCorrectSelector() {
        let editor = viewMenu.items.first(where: { $0.title == "Open Text Editor Panel" })
        XCTAssertEqual(
            editor?.action,
            #selector(MainWindowController.splitWithEditorAction(_:)),
            "Open Text Editor Panel must create the real editor split panel"
        )
    }

    func testOpenNotebookPanelHasAction() {
        let notebook = viewMenu.items.first(where: { $0.title == "Open Notebook Panel" })
        XCTAssertNotNil(
            notebook?.action,
            "Open Notebook Panel must be discoverable from the View menu"
        )
    }

    func testOpenNotebookPanelActionPointsToCorrectSelector() {
        let notebook = viewMenu.items.first(where: { $0.title == "Open Notebook Panel" })
        XCTAssertEqual(
            notebook?.action,
            #selector(MainWindowController.splitWithNotebookAction(_:)),
            "Open Notebook Panel must create the real notebook split panel"
        )
    }

    func testOpenWorkflowPanelHasAction() {
        let workflow = viewMenu.items.first(where: { $0.title == "Open Workflow Panel" })
        XCTAssertNotNil(
            workflow?.action,
            "Open Workflow Panel must be discoverable from the View menu"
        )
    }

    func testOpenWorkflowPanelActionPointsToCorrectSelector() {
        let workflow = viewMenu.items.first(where: { $0.title == "Open Workflow Panel" })
        XCTAssertEqual(
            workflow?.action,
            #selector(MainWindowController.splitWithWorkflowAction(_:)),
            "Open Workflow Panel must create the real workflow split panel"
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

    func testMoveTabToNewWindowHasAction() {
        let moveTab = fileMenu.items.first(where: { $0.title == "Move Tab to New Window" })
        XCTAssertNotNil(
            moveTab?.action,
            "Move Tab to New Window menu item must have a non-nil action"
        )
    }

    func testMoveTabToNewWindowActionPointsToCorrectSelector() {
        let moveTab = fileMenu.items.first(where: { $0.title == "Move Tab to New Window" })
        XCTAssertEqual(
            moveTab?.action,
            #selector(MainWindowController.moveActiveTabToNewWindowAction(_:)),
            "Move Tab to New Window must be wired to moveActiveTabToNewWindowAction:"
        )
    }

    func testSaveCurrentTabAsConfigHasAction() {
        let saveConfig = fileMenu.items.first(where: { $0.title == "Save Current Tab as Config..." })
        XCTAssertNotNil(
            saveConfig?.action,
            "Save Current Tab as Config must be reachable from the File menu"
        )
    }

    func testSaveCurrentTabAsConfigActionPointsToCorrectSelector() {
        let saveConfig = fileMenu.items.first(where: { $0.title == "Save Current Tab as Config..." })
        XCTAssertEqual(
            saveConfig?.action,
            #selector(MainWindowController.saveCurrentTabConfigAction(_:)),
            "Save Current Tab as Config must be wired to saveCurrentTabConfigAction:"
        )
    }

    func testOpenTabFromConfigHasAction() {
        let openConfig = fileMenu.items.first(where: { $0.title == "Open Tab from Config..." })
        XCTAssertNotNil(
            openConfig?.action,
            "Open Tab from Config must be reachable from the File menu"
        )
    }

    func testOpenTabFromConfigActionPointsToCorrectSelector() {
        let openConfig = fileMenu.items.first(where: { $0.title == "Open Tab from Config..." })
        XCTAssertEqual(
            openConfig?.action,
            #selector(MainWindowController.openTabConfigAction(_:)),
            "Open Tab from Config must be wired to openTabConfigAction:"
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

    func testShowOnboardingHasAction() {
        let onboarding = helpMenu?.items.first(where: { $0.title == "Show Onboarding" })
        XCTAssertNotNil(
            onboarding?.action,
            "Show Onboarding must be reachable from the Help menu"
        )
    }

    func testShowOnboardingActionPointsToCorrectSelector() {
        let onboarding = helpMenu?.items.first(where: { $0.title == "Show Onboarding" })
        XCTAssertEqual(
            onboarding?.action,
            #selector(MainWindowController.showOnboardingAction(_:)),
            "Show Onboarding must be wired to showOnboardingAction:"
        )
    }
}

// MARK: - Zoom Action Behavior Tests

/// Tests that the zoom @objc methods on MainWindowController correctly
/// delegate to the TerminalViewModel's zoom methods.
@MainActor
final class ZoomActionBehaviorTests: XCTestCase {

    func testZoomInIncreasesFontSize() {
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
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

    func testZoomActionsTargetTheVisibleTabInsteadOfTheBootstrapViewModel() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let firstTabID = controller.tabManager.tabs.first?.id,
              let firstViewModel = controller.viewModelForTab(firstTabID) else {
            XCTFail("Expected the bootstrap tab to exist")
            return
        }

        controller.newTabAction(nil)
        guard let activeTabID = controller.tabManager.activeTabID,
              activeTabID != firstTabID,
              let activeViewModel = controller.viewModelForTab(activeTabID) else {
            XCTFail("Expected a second active tab after newTabAction")
            return
        }

        let initialFirstSize = firstViewModel.currentFontSize
        let initialActiveSize = activeViewModel.currentFontSize

        controller.zoomInAction(nil)

        XCTAssertEqual(
            firstViewModel.currentFontSize,
            initialFirstSize,
            "Zooming the visible tab must not mutate the bootstrap tab's font size"
        )
        XCTAssertGreaterThan(
            activeViewModel.currentFontSize,
            initialActiveSize,
            "Zooming must update the visible tab's view model"
        )
    }
}

// MARK: - Tab Bar Toggle Tests

/// Tests that toggleTabBarAction correctly hides and shows the sidebar.
@MainActor
final class TabBarToggleTests: XCTestCase {

    func testTabBarIsVisibleByDefault() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertFalse(
            controller.isTabBarHidden,
            "Tab bar must be visible by default"
        )
    }

    func testToggleTabBarHidesSidebar() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleTabBarAction(nil)

        XCTAssertTrue(
            controller.isTabBarHidden,
            "Toggle tab bar must hide the sidebar on first call"
        )
    }

    func testToggleTabBarTwiceRestoresSidebar() {
        let bridge = MockTerminalEngine()
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
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertNil(
            controller.injectedNotificationManager,
            "Injected notification manager must be nil by default"
        )
    }

    func testInjectedNotificationManagerCanBeSet() {
        let bridge = MockTerminalEngine()
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
