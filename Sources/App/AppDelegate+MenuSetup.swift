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
    func setupMainMenu(localizer overrideLocalizer: AppLocalizer? = nil) {
        let localizer = overrideLocalizer ?? appLocalizer()
        let mainMenu = NSMenu()

        mainMenu.addItem(createApplicationMenu(localizer: localizer))
        mainMenu.addItem(createFileMenu(localizer: localizer))
        mainMenu.addItem(createEditMenu(localizer: localizer))
        mainMenu.addItem(createViewMenu(localizer: localizer))
        mainMenu.addItem(createWindowMenu(localizer: localizer))
        mainMenu.addItem(createHelpMenu(localizer: localizer))

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Menu Construction

    private func menuString(_ key: String, _ fallback: String, _ localizer: AppLocalizer) -> String {
        localizer.string(key, fallback: fallback)
    }

    private func createApplicationMenu(localizer: AppLocalizer) -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: menuString("menu.application.about", "About Cocxy Terminal", localizer),
                        action: #selector(MainWindowController.showAboutPanel(_:)),
                        keyEquivalent: "")

        appMenu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(
            title: menuString("menu.application.settings", "Settings...", localizer),
            action: #selector(MainWindowController.openPreferences(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(preferencesItem, with: KeybindingActionCatalog.windowPreferences)
        appMenu.addItem(preferencesItem)

        appMenu.addItem(withTitle: menuString("menu.application.checkForUpdates", "Check for Updates...", localizer),
                        action: #selector(AppDelegate.checkForUpdatesMenu(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let servicesTitle = menuString("menu.application.services", "Services", localizer)
        let servicesMenuItem = NSMenuItem(title: servicesTitle, action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: servicesTitle)
        servicesMenuItem.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        appMenu.addItem(servicesMenuItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: menuString("menu.application.hide", "Hide Cocxy Terminal", localizer),
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")

        let hideOthersItem = appMenu.addItem(
            withTitle: menuString("menu.application.hideOthers", "Hide Others", localizer),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: menuString("menu.application.showAll", "Show All", localizer),
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: menuString("menu.application.quit", "Quit Cocxy Terminal", localizer),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func createFileMenu(localizer: AppLocalizer) -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: menuString("menu.file.title", "File", localizer))

        let newTabItem = NSMenuItem(
            title: menuString("menu.file.newTab", "New Tab", localizer),
            action: #selector(MainWindowController.newTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(newTabItem, with: KeybindingActionCatalog.tabNew)
        fileMenu.addItem(newTabItem)

        let newWindowItem = NSMenuItem(
            title: menuString("menu.file.newWindow", "New Window", localizer),
            action: #selector(MainWindowController.newWindowAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(newWindowItem, with: KeybindingActionCatalog.windowNewWindow)
        fileMenu.addItem(newWindowItem)

        let moveTabItem = NSMenuItem(
            title: menuString("menu.file.moveTabToNewWindow", "Move Tab to New Window", localizer),
            action: #selector(MainWindowController.moveActiveTabToNewWindowAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(moveTabItem, with: KeybindingActionCatalog.tabMoveToNewWindow)
        fileMenu.addItem(moveTabItem)

        fileMenu.addItem(NSMenuItem.separator())

        fileMenu.addItem(
            withTitle: menuString("menu.file.saveCurrentTabAsConfig", "Save Current Tab as Config...", localizer),
            action: #selector(MainWindowController.saveCurrentTabConfigAction(_:)),
            keyEquivalent: ""
        )
        fileMenu.addItem(
            withTitle: menuString("menu.file.openTabFromConfig", "Open Tab from Config...", localizer),
            action: #selector(MainWindowController.openTabConfigAction(_:)),
            keyEquivalent: ""
        )

        fileMenu.addItem(NSMenuItem.separator())

        let closeTabItem = NSMenuItem(
            title: menuString("menu.file.closeTab", "Close Tab", localizer),
            action: #selector(MainWindowController.closeTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(closeTabItem, with: KeybindingActionCatalog.tabClose)
        fileMenu.addItem(closeTabItem)

        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    private func createEditMenu(localizer: AppLocalizer) -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: menuString("menu.edit.title", "Edit", localizer))

        editMenu.addItem(withTitle: menuString("common.undo", "Undo", localizer),
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        editMenu.addItem(withTitle: menuString("common.redo", "Redo", localizer),
                         action: Selector(("redo:")),
                         keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: menuString("common.cut", "Cut", localizer),
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: menuString("common.copy", "Copy", localizer),
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: menuString("common.paste", "Paste", localizer),
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: menuString("common.selectAll", "Select All", localizer),
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        let findItem = NSMenuItem(
            title: menuString("menu.edit.find", "Find...", localizer),
            action: #selector(MainWindowController.toggleSearchBarAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(findItem, with: KeybindingActionCatalog.editorFind)
        editMenu.addItem(findItem)

        // Escape key: dismiss active overlay.
        // Not rebindable — Escape is a reserved UX contract.
        let escapeItem = NSMenuItem(
            title: menuString("menu.edit.dismissOverlay", "Dismiss Overlay", localizer),
            action: #selector(MainWindowController.dismissActiveOverlay(_:)),
            keyEquivalent: "\u{1b}" // Escape key
        )
        escapeItem.keyEquivalentModifierMask = []
        escapeItem.isHidden = true
        editMenu.addItem(escapeItem)

        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    private func createViewMenu(localizer: AppLocalizer) -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: menuString("menu.view.title", "View", localizer))

        let commandPaletteItem = NSMenuItem(
            title: menuString("menu.view.commandPalette", "Command Palette", localizer),
            action: #selector(MainWindowController.toggleCommandPaletteAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(commandPaletteItem, with: KeybindingActionCatalog.windowCommandPalette)
        viewMenu.addItem(commandPaletteItem)

        let voiceInputItem = NSMenuItem(
            title: menuString("menu.view.voiceInput", "Voice Input", localizer),
            action: #selector(MainWindowController.startVoiceInputAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(voiceInputItem, with: KeybindingActionCatalog.voiceInput)
        viewMenu.addItem(voiceInputItem)

        let dashboardItem = NSMenuItem(
            title: menuString("menu.view.agentDashboard", "Agent Dashboard", localizer),
            action: #selector(MainWindowController.toggleDashboardAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(dashboardItem, with: KeybindingActionCatalog.reviewDashboard)
        viewMenu.addItem(dashboardItem)

        let agentModeItem = NSMenuItem(
            title: menuString("menu.view.agentMode", "Agent Mode", localizer),
            action: #selector(MainWindowController.toggleAgentModeAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(agentModeItem, with: KeybindingActionCatalog.reviewAgentMode)
        viewMenu.addItem(agentModeItem)

        let codeReviewItem = NSMenuItem(
            title: menuString("menu.view.agentCodeReview", "Agent Code Review", localizer),
            action: #selector(MainWindowController.toggleCodeReviewAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(codeReviewItem, with: KeybindingActionCatalog.reviewCodeReview)
        viewMenu.addItem(codeReviewItem)

        let githubPaneItem = NSMenuItem(
            title: menuString("menu.view.githubPane", "GitHub Pane", localizer),
            action: #selector(MainWindowController.toggleGitHubPaneAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(githubPaneItem, with: KeybindingActionCatalog.windowGitHubPane)
        viewMenu.addItem(githubPaneItem)

        let notesItem = NSMenuItem(
            title: menuString("menu.view.notes", "Notes", localizer),
            action: #selector(MainWindowController.toggleNotesAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(notesItem, with: KeybindingActionCatalog.windowNotes)
        viewMenu.addItem(notesItem)

        let quickSwitchItem = NSMenuItem(
            title: menuString("menu.view.quickSwitch", "Quick Switch", localizer),
            action: #selector(MainWindowController.quickSwitchAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(quickSwitchItem, with: KeybindingActionCatalog.remoteGoToAttention)
        viewMenu.addItem(quickSwitchItem)

        let smartRoutingItem = NSMenuItem(
            title: menuString("menu.view.smartRouting", "Smart Routing", localizer),
            action: #selector(MainWindowController.showSmartRoutingAction(_:)),
            keyEquivalent: ""
        )
        viewMenu.addItem(smartRoutingItem)

        viewMenu.addItem(withTitle: menuString("menu.view.remoteWorkspaces", "Remote Workspaces...", localizer),
                         action: #selector(MainWindowController.toggleRemoteWorkspacePanelAction(_:)),
                         keyEquivalent: "")

        let timelineItem = NSMenuItem(
            title: menuString("menu.view.agentTimeline", "Agent Timeline", localizer),
            action: #selector(MainWindowController.toggleTimelineAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(timelineItem, with: KeybindingActionCatalog.reviewTimeline)
        viewMenu.addItem(timelineItem)

        let notificationPanelItem = NSMenuItem(
            title: menuString("menu.view.notifications", "Notifications", localizer),
            action: #selector(MainWindowController.toggleNotificationPanelAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(notificationPanelItem, with: KeybindingActionCatalog.reviewNotifications)
        viewMenu.addItem(notificationPanelItem)

        let browserItem = NSMenuItem(
            title: menuString("menu.view.browser", "Browser", localizer),
            action: #selector(MainWindowController.toggleBrowserAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(browserItem, with: KeybindingActionCatalog.markdownBrowser)
        viewMenu.addItem(browserItem)

        viewMenu.addItem(withTitle: menuString("menu.view.openMarkdownPanel", "Open Markdown Panel", localizer),
                         action: #selector(MainWindowController.splitWithMarkdownAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openTextEditorPanel", "Open Text Editor Panel", localizer),
                         action: #selector(MainWindowController.splitWithEditorAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openNotebookPanel", "Open Notebook Panel", localizer),
                         action: #selector(MainWindowController.splitWithNotebookAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openWorkflowPanel", "Open Workflow Panel", localizer),
                         action: #selector(MainWindowController.splitWithWorkflowAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openSessionReplayPanel", "Open Session Replay Panel", localizer),
                         action: #selector(MainWindowController.splitWithSessionReplayAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openEditHistoryPanel", "Open Edit History Panel", localizer),
                         action: #selector(MainWindowController.splitWithAIEditHistoryAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openTemplatesPanel", "Open Templates Panel", localizer),
                         action: #selector(MainWindowController.splitWithTemplatesAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openMacrosPanel", "Open Macros Panel", localizer),
                         action: #selector(MainWindowController.splitWithMacrosAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(withTitle: menuString("menu.view.openDBCloudHelpersPanel", "Open DB/Cloud Helpers Panel", localizer),
                         action: #selector(MainWindowController.splitWithDBCloudAction(_:)),
                         keyEquivalent: "")

        viewMenu.addItem(NSMenuItem.separator())

        // Toggle Tab Bar: not rebindable (no catalog entry, no default shortcut).
        viewMenu.addItem(withTitle: menuString("menu.view.toggleTabBar", "Toggle Tab Bar", localizer),
                         action: #selector(MainWindowController.toggleTabBarAction(_:)),
                         keyEquivalent: "")

        let splitHorizontalItem = NSMenuItem(
            title: menuString("menu.view.splitSideBySide", "Split Side by Side", localizer),
            action: #selector(MainWindowController.splitHorizontalAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(splitHorizontalItem, with: KeybindingActionCatalog.splitHorizontal)
        viewMenu.addItem(splitHorizontalItem)

        let splitVerticalItem = NSMenuItem(
            title: menuString("menu.view.splitStacked", "Split Stacked", localizer),
            action: #selector(MainWindowController.splitVerticalAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(splitVerticalItem, with: KeybindingActionCatalog.splitVertical)
        viewMenu.addItem(splitVerticalItem)

        let closeSplitItem = NSMenuItem(
            title: menuString("menu.view.closeSplit", "Close Split", localizer),
            action: #selector(MainWindowController.closeSplitAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(closeSplitItem, with: KeybindingActionCatalog.splitClose)
        viewMenu.addItem(closeSplitItem)

        let equalizeSplitsItem = NSMenuItem(
            title: menuString("menu.view.equalizeSplits", "Equalize Splits", localizer),
            action: #selector(MainWindowController.equalizeSplitsAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(equalizeSplitsItem, with: KeybindingActionCatalog.splitEqualize)
        viewMenu.addItem(equalizeSplitsItem)

        let toggleZoomItem = NSMenuItem(
            title: menuString("menu.view.toggleSplitZoom", "Toggle Split Zoom", localizer),
            action: #selector(MainWindowController.toggleSplitZoomAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(toggleZoomItem, with: KeybindingActionCatalog.splitToggleZoom)
        viewMenu.addItem(toggleZoomItem)

        viewMenu.addItem(NSMenuItem.separator())

        let navLeftItem = NSMenuItem(
            title: menuString("menu.view.navigateSplitLeft", "Navigate Split Left", localizer),
            action: #selector(MainWindowController.navigateSplitLeftAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navLeftItem, with: KeybindingActionCatalog.navigateSplitLeft)
        viewMenu.addItem(navLeftItem)

        let navRightItem = NSMenuItem(
            title: menuString("menu.view.navigateSplitRight", "Navigate Split Right", localizer),
            action: #selector(MainWindowController.navigateSplitRightAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navRightItem, with: KeybindingActionCatalog.navigateSplitRight)
        viewMenu.addItem(navRightItem)

        let navUpItem = NSMenuItem(
            title: menuString("menu.view.navigateSplitUp", "Navigate Split Up", localizer),
            action: #selector(MainWindowController.navigateSplitUpAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navUpItem, with: KeybindingActionCatalog.navigateSplitUp)
        viewMenu.addItem(navUpItem)

        let navDownItem = NSMenuItem(
            title: menuString("menu.view.navigateSplitDown", "Navigate Split Down", localizer),
            action: #selector(MainWindowController.navigateSplitDownAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(navDownItem, with: KeybindingActionCatalog.navigateSplitDown)
        viewMenu.addItem(navDownItem)

        viewMenu.addItem(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(
            title: menuString("menu.view.zoomIn", "Zoom In", localizer),
            action: #selector(MainWindowController.zoomInAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(zoomInItem, with: KeybindingActionCatalog.editorZoomIn)
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(
            title: menuString("menu.view.zoomOut", "Zoom Out", localizer),
            action: #selector(MainWindowController.zoomOutAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(zoomOutItem, with: KeybindingActionCatalog.editorZoomOut)
        viewMenu.addItem(zoomOutItem)

        let resetZoomItem = NSMenuItem(
            title: menuString("menu.view.resetZoom", "Reset Zoom", localizer),
            action: #selector(MainWindowController.resetZoomAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(resetZoomItem, with: KeybindingActionCatalog.editorResetZoom)
        viewMenu.addItem(resetZoomItem)

        viewMenu.addItem(NSMenuItem.separator())

        let fullScreenItem = NSMenuItem(
            title: menuString("menu.view.enterFullScreen", "Enter Full Screen", localizer),
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(fullScreenItem, with: KeybindingActionCatalog.windowToggleFullScreen)
        viewMenu.addItem(fullScreenItem)

        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    private func createWindowMenu(localizer: AppLocalizer) -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: menuString("menu.window.title", "Window", localizer))

        let minimizeItem = NSMenuItem(
            title: menuString("menu.window.minimize", "Minimize", localizer),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(minimizeItem, with: KeybindingActionCatalog.windowMinimize)
        windowMenu.addItem(minimizeItem)

        // Zoom: not rebindable, no catalog entry (macOS-native window zoom).
        windowMenu.addItem(withTitle: menuString("menu.window.zoom", "Zoom", localizer),
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())

        let nextTabItem = NSMenuItem(
            title: menuString("menu.window.nextTab", "Next Tab", localizer),
            action: #selector(MainWindowController.nextTabAction(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(nextTabItem, with: KeybindingActionCatalog.tabNext)
        windowMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(
            title: menuString("menu.window.previousTab", "Previous Tab", localizer),
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
                title: String(
                    format: menuString("menu.window.tabNumber", "Tab %d", localizer),
                    index + 1
                ),
                action: gotoSelectors[index],
                keyEquivalent: ""
            )
            MenuKeybindingsBinder.tag(gotoItem, with: gotoActions[index])
            windowMenu.addItem(gotoItem)
        }

        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: menuString("menu.window.bringAllToFront", "Bring All to Front", localizer),
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        NSApplication.shared.windowsMenu = windowMenu
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }

    private func createHelpMenu(localizer: AppLocalizer) -> NSMenuItem {
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: menuString("menu.help.title", "Help", localizer))

        helpMenu.addItem(withTitle: menuString("menu.help.cocxyTerminalHelp", "Cocxy Terminal Help", localizer),
                         action: #selector(MainWindowController.showWelcomeAction(_:)),
                         keyEquivalent: "?")
        helpMenu.addItem(
            withTitle: menuString("menu.help.showOnboarding", "Show Onboarding", localizer),
            action: #selector(MainWindowController.showOnboardingAction(_:)),
            keyEquivalent: ""
        )

        NSApplication.shared.helpMenu = helpMenu
        helpMenuItem.submenu = helpMenu
        return helpMenuItem
    }
}
