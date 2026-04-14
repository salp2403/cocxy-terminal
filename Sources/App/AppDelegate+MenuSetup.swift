// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+MenuSetup.swift - Application menu bar construction.

import AppKit

// MARK: - Menu Setup

/// Extension that constructs the application menu bar with all standard
/// menus: Application, File, Edit, View, Window, and Help.
///
/// Extracted from AppDelegate to keep the main file focused on
/// lifecycle management and service initialization.
extension AppDelegate {

    /// Creates the application menu bar with standard menus.
    func setupMainMenu() {
        let mainMenu = NSMenu()

        mainMenu.addItem(createApplicationMenu())
        mainMenu.addItem(createFileMenu())
        mainMenu.addItem(createEditMenu())
        mainMenu.addItem(createViewMenu())
        mainMenu.addItem(createWindowMenu())
        mainMenu.addItem(createHelpMenu())

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Menu Construction

    private func createApplicationMenu() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: "About Cocxy Terminal",
                        action: #selector(MainWindowController.showAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...",
                        action: #selector(MainWindowController.openPreferences(_:)),
                        keyEquivalent: ",")
        appMenu.addItem(withTitle: "Check for Updates...",
                        action: #selector(AppDelegate.checkForUpdatesMenu(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let servicesMenuItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesMenuItem.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        appMenu.addItem(servicesMenuItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Cocxy Terminal",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")

        let hideOthersItem = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Cocxy Terminal",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func createFileMenu() -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")

        fileMenu.addItem(withTitle: "New Tab",
                         action: #selector(MainWindowController.newTabAction(_:)),
                         keyEquivalent: "t")
        fileMenu.addItem(withTitle: "New Window",
                         action: #selector(MainWindowController.newWindowAction(_:)),
                         keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Move Tab to New Window",
                         action: #selector(MainWindowController.moveActiveTabToNewWindowAction(_:)),
                         keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab",
                         action: #selector(MainWindowController.closeTabAction(_:)),
                         keyEquivalent: "w")

        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    private func createEditMenu() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",
                         action: Selector(("redo:")),
                         keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find...",
                         action: #selector(MainWindowController.toggleSearchBarAction(_:)),
                         keyEquivalent: "f")

        // Escape key: dismiss active overlay.
        let escapeItem = NSMenuItem(
            title: "Dismiss Overlay",
            action: #selector(MainWindowController.dismissActiveOverlay(_:)),
            keyEquivalent: "\u{1b}" // Escape key
        )
        escapeItem.keyEquivalentModifierMask = []
        escapeItem.isHidden = true
        editMenu.addItem(escapeItem)

        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    private func createViewMenu() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        // Command Palette: Cmd+Shift+P
        let commandPaletteItem = viewMenu.addItem(
            withTitle: "Command Palette",
            action: #selector(MainWindowController.toggleCommandPaletteAction(_:)),
            keyEquivalent: "p"
        )
        commandPaletteItem.keyEquivalentModifierMask = [.command, .shift]

        // Dashboard: Cmd+Option+A (Agent dashboard)
        // Note: Cmd+Option+D conflicts with macOS Dock toggle.
        let dashboardItem = viewMenu.addItem(
            withTitle: "Agent Dashboard",
            action: #selector(MainWindowController.toggleDashboardAction(_:)),
            keyEquivalent: "a"
        )
        dashboardItem.keyEquivalentModifierMask = [.command, .option]

        let codeReviewItem = viewMenu.addItem(
            withTitle: "Agent Code Review",
            action: #selector(MainWindowController.toggleCodeReviewAction(_:)),
            keyEquivalent: "r"
        )
        codeReviewItem.keyEquivalentModifierMask = [.command, .option]

        // Smart Routing: Cmd+Shift+U (replaces Quick Switch)
        let smartRoutingItem = viewMenu.addItem(
            withTitle: "Smart Routing",
            action: #selector(MainWindowController.showSmartRoutingAction(_:)),
            keyEquivalent: "u"
        )
        smartRoutingItem.keyEquivalentModifierMask = [.command, .shift]

        // Timeline: Cmd+Shift+T (no conflict with Cmd+T which is New Tab)
        let timelineItem = viewMenu.addItem(
            withTitle: "Agent Timeline",
            action: #selector(MainWindowController.toggleTimelineAction(_:)),
            keyEquivalent: "t"
        )
        timelineItem.keyEquivalentModifierMask = [.command, .shift]

        // Notification Panel: Cmd+Shift+I
        let notificationPanelItem = viewMenu.addItem(
            withTitle: "Notifications",
            action: #selector(MainWindowController.toggleNotificationPanelAction(_:)),
            keyEquivalent: "i"
        )
        notificationPanelItem.keyEquivalentModifierMask = [.command, .shift]

        // Browser: Cmd+Shift+B
        let browserItem = viewMenu.addItem(
            withTitle: "Browser",
            action: #selector(MainWindowController.toggleBrowserAction(_:)),
            keyEquivalent: "b"
        )
        browserItem.keyEquivalentModifierMask = [.command, .shift]

        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(withTitle: "Toggle Tab Bar",
                         action: #selector(MainWindowController.toggleTabBarAction(_:)),
                         keyEquivalent: "")

        let splitHorizontalItem = viewMenu.addItem(
            withTitle: "Split Horizontal",
            action: #selector(MainWindowController.splitHorizontalAction(_:)),
            keyEquivalent: "d"
        )
        splitHorizontalItem.keyEquivalentModifierMask = [.command]

        let splitVerticalItem = viewMenu.addItem(
            withTitle: "Split Vertical",
            action: #selector(MainWindowController.splitVerticalAction(_:)),
            keyEquivalent: "d"
        )
        splitVerticalItem.keyEquivalentModifierMask = [.command, .shift]

        let closeSplitItem = viewMenu.addItem(
            withTitle: "Close Split",
            action: #selector(MainWindowController.closeSplitAction(_:)),
            keyEquivalent: "w"
        )
        closeSplitItem.keyEquivalentModifierMask = [.command, .shift]

        let equalizeSplitsItem = viewMenu.addItem(
            withTitle: "Equalize Splits",
            action: #selector(MainWindowController.equalizeSplitsAction(_:)),
            keyEquivalent: "e"
        )
        equalizeSplitsItem.keyEquivalentModifierMask = [.command, .shift]

        let toggleZoomItem = viewMenu.addItem(
            withTitle: "Toggle Split Zoom",
            action: #selector(MainWindowController.toggleSplitZoomAction(_:)),
            keyEquivalent: "f"
        )
        toggleZoomItem.keyEquivalentModifierMask = [.command, .shift]

        viewMenu.addItem(NSMenuItem.separator())

        // Navigation between splits.
        let navLeftItem = viewMenu.addItem(
            withTitle: "Navigate Split Left",
            action: #selector(MainWindowController.navigateSplitLeftAction(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        )
        navLeftItem.keyEquivalentModifierMask = [.command, .option]

        let navRightItem = viewMenu.addItem(
            withTitle: "Navigate Split Right",
            action: #selector(MainWindowController.navigateSplitRightAction(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        )
        navRightItem.keyEquivalentModifierMask = [.command, .option]

        let navUpItem = viewMenu.addItem(
            withTitle: "Navigate Split Up",
            action: #selector(MainWindowController.navigateSplitUpAction(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        )
        navUpItem.keyEquivalentModifierMask = [.command, .option]

        let navDownItem = viewMenu.addItem(
            withTitle: "Navigate Split Down",
            action: #selector(MainWindowController.navigateSplitDownAction(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        )
        navDownItem.keyEquivalentModifierMask = [.command, .option]

        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(MainWindowController.zoomInAction(_:)),
                         keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(MainWindowController.zoomOutAction(_:)),
                         keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Zoom",
                         action: #selector(MainWindowController.resetZoomAction(_:)),
                         keyEquivalent: "0")

        viewMenu.addItem(NSMenuItem.separator())

        let fullScreenItem = viewMenu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]

        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    private func createWindowMenu() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")

        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())

        // Tab navigation shortcuts.
        let nextTabItem = windowMenu.addItem(
            withTitle: "Next Tab",
            action: #selector(MainWindowController.nextTabAction(_:)),
            keyEquivalent: "]"
        )
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]

        let prevTabItem = windowMenu.addItem(
            withTitle: "Previous Tab",
            action: #selector(MainWindowController.previousTabAction(_:)),
            keyEquivalent: "["
        )
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]

        windowMenu.addItem(NSMenuItem.separator())

        // Direct tab switching: Cmd+1 through Cmd+9.
        let gotoSelectors: [Selector] = [
            #selector(MainWindowController.gotoTab1(_:)),
            #selector(MainWindowController.gotoTab2(_:)),
            #selector(MainWindowController.gotoTab3(_:)),
            #selector(MainWindowController.gotoTab4(_:)),
            #selector(MainWindowController.gotoTab5(_:)),
            #selector(MainWindowController.gotoTab6(_:)),
            #selector(MainWindowController.gotoTab7(_:)),
            #selector(MainWindowController.gotoTab8(_:)),
            #selector(MainWindowController.gotoTab9(_:)),
        ]
        for (index, selector) in gotoSelectors.enumerated() {
            windowMenu.addItem(
                withTitle: "Tab \(index + 1)",
                action: selector,
                keyEquivalent: "\(index + 1)"
            )
        }

        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        NSApplication.shared.windowsMenu = windowMenu
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }

    private func createHelpMenu() -> NSMenuItem {
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")

        helpMenu.addItem(withTitle: "Cocxy Terminal Help",
                         action: #selector(MainWindowController.showWelcomeAction(_:)),
                         keyEquivalent: "?")

        NSApplication.shared.helpMenu = helpMenu
        helpMenuItem.submenu = helpMenu
        return helpMenuItem
    }
}
