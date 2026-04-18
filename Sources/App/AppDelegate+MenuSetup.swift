// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+MenuSetup.swift - Application menu bar construction.

import AppKit

// MARK: - Menu Setup

/// Extension that constructs the application menu bar with all standard
/// menus: Application, File, Edit, View, Window, and Help.
///
/// Extracted from AppDelegate to keep the main file focused on
/// lifecycle management and service initialization.
///
/// ## Rebindable shortcuts
///
/// Menu items whose shortcut is surfaced in the Keybindings editor are
/// registered via `MenuKeybindingsBinder.tag(_:with:)`. That helper both
/// stores the catalog id on the item (via `NSUserInterfaceItemIdentifier`)
/// and applies the catalog default `keyEquivalent`. `AppDelegate` then
/// overlays the user's live `ConfigService.current.keybindings` on top via
/// `MenuKeybindingsBinder.apply(_:to:)`, and re-applies whenever the config
/// changes on disk.
///
/// Items that are not user-rebindable (About, Hide, Quit, Cut/Copy/Paste,
/// Undo/Redo, Services, Bring All to Front, the hidden Escape handler,
/// etc.) keep hardcoded `keyEquivalent` values and are never touched by the
/// binder.
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

        let preferencesItem = NSMenuItem(
            title: "Settings...",
            action: #selector(MainWindowController.openPreferences(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(preferencesItem, with: KeybindingActionCatalog.windowPreferences)
        appMenu.addItem(preferencesItem)

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

        let newTabItem = NSMenuItem(
            title: "New Tab",
            action: #selector(MainWindowController.newTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(newTabItem, with: KeybindingActionCatalog.tabNew)
        fileMenu.addItem(newTabItem)

        let newWindowItem = NSMenuItem(
            title: "New Window",
            action: #selector(MainWindowController.newWindowAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(newWindowItem, with: KeybindingActionCatalog.windowNewWindow)
        fileMenu.addItem(newWindowItem)

        let moveTabItem = NSMenuItem(
            title: "Move Tab to New Window",
            action: #selector(MainWindowController.moveActiveTabToNewWindowAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(moveTabItem, with: KeybindingActionCatalog.tabMoveToNewWindow)
        fileMenu.addItem(moveTabItem)

        fileMenu.addItem(NSMenuItem.separator())

        let closeTabItem = NSMenuItem(
            title: "Close Tab",
            action: #selector(MainWindowController.closeTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(closeTabItem, with: KeybindingActionCatalog.tabClose)
        fileMenu.addItem(closeTabItem)

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

        let findItem = NSMenuItem(
            title: "Find...",
            action: #selector(MainWindowController.toggleSearchBarAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(findItem, with: KeybindingActionCatalog.editorFind)
        editMenu.addItem(findItem)

        // Escape key: dismiss active overlay.
        // Not rebindable — Escape is a reserved UX contract.
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

        let commandPaletteItem = NSMenuItem(
            title: "Command Palette",
            action: #selector(MainWindowController.toggleCommandPaletteAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(commandPaletteItem, with: KeybindingActionCatalog.windowCommandPalette)
        viewMenu.addItem(commandPaletteItem)

        let dashboardItem = NSMenuItem(
            title: "Agent Dashboard",
            action: #selector(MainWindowController.toggleDashboardAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(dashboardItem, with: KeybindingActionCatalog.reviewDashboard)
        viewMenu.addItem(dashboardItem)

        let codeReviewItem = NSMenuItem(
            title: "Agent Code Review",
            action: #selector(MainWindowController.toggleCodeReviewAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(codeReviewItem, with: KeybindingActionCatalog.reviewCodeReview)
        viewMenu.addItem(codeReviewItem)

        let smartRoutingItem = NSMenuItem(
            title: "Smart Routing",
            action: #selector(MainWindowController.showSmartRoutingAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(smartRoutingItem, with: KeybindingActionCatalog.remoteGoToAttention)
        viewMenu.addItem(smartRoutingItem)

        let timelineItem = NSMenuItem(
            title: "Agent Timeline",
            action: #selector(MainWindowController.toggleTimelineAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(timelineItem, with: KeybindingActionCatalog.reviewTimeline)
        viewMenu.addItem(timelineItem)

        let notificationPanelItem = NSMenuItem(
            title: "Notifications",
            action: #selector(MainWindowController.toggleNotificationPanelAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(notificationPanelItem, with: KeybindingActionCatalog.reviewNotifications)
        viewMenu.addItem(notificationPanelItem)

        let browserItem = NSMenuItem(
            title: "Browser",
            action: #selector(MainWindowController.toggleBrowserAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(browserItem, with: KeybindingActionCatalog.markdownBrowser)
        viewMenu.addItem(browserItem)

        viewMenu.addItem(NSMenuItem.separator())

        // Toggle Tab Bar: not rebindable (no catalog entry, no default shortcut).
        viewMenu.addItem(withTitle: "Toggle Tab Bar",
                         action: #selector(MainWindowController.toggleTabBarAction(_:)),
                         keyEquivalent: "")

        let splitHorizontalItem = NSMenuItem(
            title: "Split Horizontal",
            action: #selector(MainWindowController.splitHorizontalAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(splitHorizontalItem, with: KeybindingActionCatalog.splitHorizontal)
        viewMenu.addItem(splitHorizontalItem)

        let splitVerticalItem = NSMenuItem(
            title: "Split Vertical",
            action: #selector(MainWindowController.splitVerticalAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(splitVerticalItem, with: KeybindingActionCatalog.splitVertical)
        viewMenu.addItem(splitVerticalItem)

        let closeSplitItem = NSMenuItem(
            title: "Close Split",
            action: #selector(MainWindowController.closeSplitAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(closeSplitItem, with: KeybindingActionCatalog.splitClose)
        viewMenu.addItem(closeSplitItem)

        let equalizeSplitsItem = NSMenuItem(
            title: "Equalize Splits",
            action: #selector(MainWindowController.equalizeSplitsAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(equalizeSplitsItem, with: KeybindingActionCatalog.splitEqualize)
        viewMenu.addItem(equalizeSplitsItem)

        let toggleZoomItem = NSMenuItem(
            title: "Toggle Split Zoom",
            action: #selector(MainWindowController.toggleSplitZoomAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(toggleZoomItem, with: KeybindingActionCatalog.splitToggleZoom)
        viewMenu.addItem(toggleZoomItem)

        viewMenu.addItem(NSMenuItem.separator())

        let navLeftItem = NSMenuItem(
            title: "Navigate Split Left",
            action: #selector(MainWindowController.navigateSplitLeftAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navLeftItem, with: KeybindingActionCatalog.navigateSplitLeft)
        viewMenu.addItem(navLeftItem)

        let navRightItem = NSMenuItem(
            title: "Navigate Split Right",
            action: #selector(MainWindowController.navigateSplitRightAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navRightItem, with: KeybindingActionCatalog.navigateSplitRight)
        viewMenu.addItem(navRightItem)

        let navUpItem = NSMenuItem(
            title: "Navigate Split Up",
            action: #selector(MainWindowController.navigateSplitUpAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navUpItem, with: KeybindingActionCatalog.navigateSplitUp)
        viewMenu.addItem(navUpItem)

        let navDownItem = NSMenuItem(
            title: "Navigate Split Down",
            action: #selector(MainWindowController.navigateSplitDownAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navDownItem, with: KeybindingActionCatalog.navigateSplitDown)
        viewMenu.addItem(navDownItem)

        viewMenu.addItem(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(
            title: "Zoom In",
            action: #selector(MainWindowController.zoomInAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(zoomInItem, with: KeybindingActionCatalog.editorZoomIn)
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(
            title: "Zoom Out",
            action: #selector(MainWindowController.zoomOutAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(zoomOutItem, with: KeybindingActionCatalog.editorZoomOut)
        viewMenu.addItem(zoomOutItem)

        let resetZoomItem = NSMenuItem(
            title: "Reset Zoom",
            action: #selector(MainWindowController.resetZoomAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(resetZoomItem, with: KeybindingActionCatalog.editorResetZoom)
        viewMenu.addItem(resetZoomItem)

        viewMenu.addItem(NSMenuItem.separator())

        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(fullScreenItem, with: KeybindingActionCatalog.windowToggleFullScreen)
        viewMenu.addItem(fullScreenItem)

        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    private func createWindowMenu() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")

        let minimizeItem = NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(minimizeItem, with: KeybindingActionCatalog.windowMinimize)
        windowMenu.addItem(minimizeItem)

        // Zoom: not rebindable, no catalog entry (macOS-native window zoom).
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())

        let nextTabItem = NSMenuItem(
            title: "Next Tab",
            action: #selector(MainWindowController.nextTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(nextTabItem, with: KeybindingActionCatalog.tabNext)
        windowMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(
            title: "Previous Tab",
            action: #selector(MainWindowController.previousTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(prevTabItem, with: KeybindingActionCatalog.tabPrevious)
        windowMenu.addItem(prevTabItem)

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
        let gotoActions: [KeybindingAction] = [
            KeybindingActionCatalog.tabGoto1,
            KeybindingActionCatalog.tabGoto2,
            KeybindingActionCatalog.tabGoto3,
            KeybindingActionCatalog.tabGoto4,
            KeybindingActionCatalog.tabGoto5,
            KeybindingActionCatalog.tabGoto6,
            KeybindingActionCatalog.tabGoto7,
            KeybindingActionCatalog.tabGoto8,
            KeybindingActionCatalog.tabGoto9,
        ]
        for index in 0..<gotoSelectors.count {
            let gotoItem = NSMenuItem(
                title: "Tab \(index + 1)",
                action: gotoSelectors[index],
                keyEquivalent: ""
            )
            MenuKeybindingsBinder.tag(gotoItem, with: gotoActions[index])
            windowMenu.addItem(gotoItem)
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
