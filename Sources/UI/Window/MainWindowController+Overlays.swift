// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Overlays.swift - Overlay management (Command Palette, Dashboard, etc.)

import AppKit
import Combine
import SwiftUI

// MARK: - Overlay Management

/// Extension that handles all SwiftUI overlay lifecycle: Command Palette,
/// Dashboard, Search Bar, Smart Routing, Timeline, Preferences, and About.
///
/// Extracted from MainWindowController to keep the main file focused on
/// window management, tabs, and terminal surface lifecycle.
extension MainWindowController {

    // MARK: - Command Palette (Cmd+Shift+P)

    func toggleCommandPalette() {
        // When the Aurora chrome is active the shortcut must drive the
        // redesigned palette. Routing here keeps a single entry point
        // (menu action, sidebar tray button, direct caller) consistent
        // with whatever chrome the user has mounted.
        if isAuroraChromeActive {
            toggleAuroraPalette()
            return
        }
        if isCommandPaletteVisible {
            dismissCommandPalette()
        } else {
            showCommandPaletteOverlay()
        }
    }

    @objc func toggleCommandPaletteAction(_ sender: Any?) {
        toggleCommandPalette()
    }

    func showCommandPaletteOverlay() {
        guard let overlayContainer = overlayContainerView else { return }

        // Preserve the palette engine across open/close cycles so that
        // `recentActions` and `executionCounts` accumulate during the
        // window's lifetime. Rebuilding on every open (previous code)
        // reset the user's recent-actions ranking — a real UX
        // regression. Instead: create the engine lazily on first open,
        // then refresh only the shortcut labels on subsequent opens via
        // `rebuildBuiltInShortcuts(using:)` so palette glyphs still
        // match the latest `[keybindings]` edits without losing state.
        let engine: CommandPaletteEngineImpl
        if let existing = commandPaletteEngine {
            engine = existing
            let keybindings = configService?.current.keybindings ?? .defaults
            engine.rebuildBuiltInShortcuts(using: keybindings)
        } else {
            engine = createWiredCommandPaletteEngine()
            commandPaletteEngine = engine
        }
        commandPaletteViewModel = CommandPaletteViewModel(engine: engine)

        guard let viewModel = commandPaletteViewModel else { return }
        viewModel.isVisible = true

        commandPaletteHostingView?.removeFromSuperview()
        var swiftUIView = CommandPaletteView(viewModel: viewModel)
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = FocusableHostingView(rootView: swiftUIView)
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        self.commandPaletteHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isCommandPaletteVisible = true
        window?.makeFirstResponder(hostingView)
    }

    /// Maps each Command Palette action id to the `KeybindingActionCatalog`
    /// action whose shortcut the UI should display.
    ///
    /// Palette entries without an entry here keep their hardcoded
    /// `shortcut` literal (for actions that are not user-rebindable, such as
    /// theme cycling or remote workspace toggling).
    private static let paletteCatalogMapping: [String: String] = [
        "window.new": KeybindingActionCatalog.windowNewWindow.id,
        "window.minimize": KeybindingActionCatalog.windowMinimize.id,
        "window.fullscreen": KeybindingActionCatalog.windowToggleFullScreen.id,
        "window.commandPalette": KeybindingActionCatalog.windowCommandPalette.id,
        "tabs.new": KeybindingActionCatalog.tabNew.id,
        "tabs.close": KeybindingActionCatalog.tabClose.id,
        "tabs.next": KeybindingActionCatalog.tabNext.id,
        "tabs.previous": KeybindingActionCatalog.tabPrevious.id,
        "tabs.moveToNewWindow": KeybindingActionCatalog.tabMoveToNewWindow.id,
        "tabs.goto1": KeybindingActionCatalog.tabGoto1.id,
        "tabs.goto2": KeybindingActionCatalog.tabGoto2.id,
        "tabs.goto3": KeybindingActionCatalog.tabGoto3.id,
        "tabs.goto4": KeybindingActionCatalog.tabGoto4.id,
        "tabs.goto5": KeybindingActionCatalog.tabGoto5.id,
        "tabs.goto6": KeybindingActionCatalog.tabGoto6.id,
        "tabs.goto7": KeybindingActionCatalog.tabGoto7.id,
        "tabs.goto8": KeybindingActionCatalog.tabGoto8.id,
        "tabs.goto9": KeybindingActionCatalog.tabGoto9.id,
        "splits.vertical": KeybindingActionCatalog.splitVertical.id,
        "splits.horizontal": KeybindingActionCatalog.splitHorizontal.id,
        "splits.close": KeybindingActionCatalog.splitClose.id,
        "splits.equalize": KeybindingActionCatalog.splitEqualize.id,
        "splits.zoom": KeybindingActionCatalog.splitToggleZoom.id,
        "navigation.splitLeft": KeybindingActionCatalog.navigateSplitLeft.id,
        "navigation.splitRight": KeybindingActionCatalog.navigateSplitRight.id,
        "navigation.splitUp": KeybindingActionCatalog.navigateSplitUp.id,
        "navigation.splitDown": KeybindingActionCatalog.navigateSplitDown.id,
        "dashboard.toggle": KeybindingActionCatalog.reviewDashboard.id,
        "agent.review": KeybindingActionCatalog.reviewCodeReview.id,
        "github.toggle": KeybindingActionCatalog.windowGitHubPane.id,
        "timeline.toggle": KeybindingActionCatalog.reviewTimeline.id,
        "search.toggle": KeybindingActionCatalog.editorFind.id,
        "editor.zoomIn": KeybindingActionCatalog.editorZoomIn.id,
        "editor.zoomOut": KeybindingActionCatalog.editorZoomOut.id,
        "editor.resetZoom": KeybindingActionCatalog.editorResetZoom.id,
        "preferences.show": KeybindingActionCatalog.windowPreferences.id,
        "notifications.toggle": KeybindingActionCatalog.reviewNotifications.id,
        "browser.toggle": KeybindingActionCatalog.markdownBrowser.id,
        "navigation.quickterminal": KeybindingActionCatalog.windowQuickTerminal.id,
        "navigation.quickswitch": KeybindingActionCatalog.remoteGoToAttention.id,
    ]

    /// Resolves the Command Palette shortcut label for a palette action id
    /// against the live keybindings config.
    ///
    /// Returns the user's current binding (pretty macOS-glyph label) when
    /// `paletteId` maps to a catalog action; otherwise returns `fallback`
    /// unchanged so actions outside the catalog keep their hardcoded label.
    private func paletteShortcutLabel(
        _ paletteId: String,
        fallback: String?
    ) -> String? {
        guard let actionId = Self.paletteCatalogMapping[paletteId] else {
            return fallback
        }
        let config = configService?.current.keybindings ?? .defaults
        return MenuKeybindingsBinder.prettyShortcut(for: actionId, in: config)
    }

    /// Creates a CommandPaletteEngine with all actions wired to real handlers.
    ///
    /// Actions that require AppKit coordination (toggleDashboard, toggleTimeline, etc.)
    /// are registered with direct handlers referencing `self`, bypassing the coordinator
    /// layer which lacks access to the window controller.
    ///
    /// Shortcut labels for catalog-backed actions are resolved live from
    /// `ConfigService.current.keybindings` so the palette glyph always
    /// matches the menu bar glyph, even after a user customization.
    /// Visibility is `internal` (default) so the Aurora integration in
    /// `MainWindowController+AuroraIntegration` can reuse the same
    /// engine factory and keep classic and Aurora palettes aligned.
    func createWiredCommandPaletteEngine() -> CommandPaletteEngineImpl {
        let engine = CommandPaletteEngineImpl()

        // Register actions with direct handlers to the window controller.
        // Each handler first dismisses the palette, then executes the action
        // on the next run loop tick to avoid SwiftUI state mutation during rendering.
        let actions: [CommandAction] = [
            CommandAction(
                id: "window.new",
                name: "New Window",
                description: "Open a new Cocxy Terminal window",
                shortcut: paletteShortcutLabel("window.new", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.newWindowAction(nil) }
                }
            ),
            CommandAction(
                id: "window.minimize",
                name: "Minimize Window",
                description: "Minimize the active window to the Dock",
                shortcut: paletteShortcutLabel("window.minimize", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.window?.performMiniaturize(nil) }
                }
            ),
            CommandAction(
                id: "window.fullscreen",
                name: "Toggle Full Screen",
                description: "Enter or leave full-screen mode",
                shortcut: paletteShortcutLabel("window.fullscreen", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.window?.toggleFullScreen(nil) }
                }
            ),
            CommandAction(
                id: "window.commandPalette",
                name: "Close Command Palette",
                description: "Dismiss the command palette",
                shortcut: paletteShortcutLabel("window.commandPalette", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                }
            ),
            CommandAction(
                id: "tabs.new",
                name: "New Tab",
                description: "Open a new terminal tab",
                shortcut: paletteShortcutLabel("tabs.new", fallback: nil),
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.createTab() }
                }
            ),
            CommandAction(
                id: "tabs.close",
                name: "Close Tab",
                description: "Close the current tab",
                shortcut: paletteShortcutLabel("tabs.close", fallback: nil),
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor [weak self] in
                        guard let self, let activeId = self.tabManager.activeTabID else { return }
                        self.closeTab(activeId)
                    }
                }
            ),
            CommandAction(
                id: "tabs.moveToNewWindow",
                name: "Move Tab to New Window",
                description: "Detach the active tab into its own window",
                shortcut: paletteShortcutLabel("tabs.moveToNewWindow", fallback: nil),
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.moveActiveTabToNewWindowAction(nil) }
                }
            ),
            CommandAction(
                id: "splits.vertical",
                name: "Split Stacked",
                description: "Split the current pane into a top/bottom stack",
                shortcut: paletteShortcutLabel("splits.vertical", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.splitVerticalAction(nil) }
                }
            ),
            CommandAction(
                id: "splits.horizontal",
                name: "Split Side by Side",
                description: "Split the current pane into left/right columns",
                shortcut: paletteShortcutLabel("splits.horizontal", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.splitHorizontalAction(nil) }
                }
            ),
            CommandAction(
                id: "splits.close",
                name: "Close Split",
                description: "Close the focused split pane",
                shortcut: paletteShortcutLabel("splits.close", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.closeSplitAction(nil) }
                }
            ),
            CommandAction(
                id: "dashboard.toggle",
                name: "Toggle Dashboard",
                description: "Show or hide the agent dashboard panel",
                shortcut: paletteShortcutLabel("dashboard.toggle", fallback: nil),
                category: .dashboard,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleDashboard() }
                }
            ),
            CommandAction(
                id: "agent.review",
                name: "Toggle Code Review",
                description: "Review agent-generated file changes",
                shortcut: paletteShortcutLabel("agent.review", fallback: nil),
                category: .agent,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleCodeReview() }
                }
            ),
            CommandAction(
                id: "github.toggle",
                name: "Toggle GitHub Pane",
                description: "Show pull requests, issues and checks from gh",
                shortcut: paletteShortcutLabel("github.toggle", fallback: nil),
                category: .agent,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleGitHubPane() }
                }
            ),
            CommandAction(
                id: "timeline.toggle",
                name: "Toggle Timeline",
                description: "Show or hide the agent timeline panel",
                shortcut: paletteShortcutLabel("timeline.toggle", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleTimeline() }
                }
            ),
            CommandAction(
                id: "search.toggle",
                name: "Find in Terminal",
                description: "Search the scrollback buffer",
                shortcut: paletteShortcutLabel("search.toggle", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleSearchBar() }
                }
            ),
            CommandAction(
                id: "editor.zoomIn",
                name: "Zoom In",
                description: "Increase the terminal font size",
                shortcut: paletteShortcutLabel("editor.zoomIn", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.zoomInAction(nil) }
                }
            ),
            CommandAction(
                id: "editor.zoomOut",
                name: "Zoom Out",
                description: "Decrease the terminal font size",
                shortcut: paletteShortcutLabel("editor.zoomOut", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.zoomOutAction(nil) }
                }
            ),
            CommandAction(
                id: "editor.resetZoom",
                name: "Reset Zoom",
                description: "Restore the configured terminal font size",
                shortcut: paletteShortcutLabel("editor.resetZoom", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.resetZoomAction(nil) }
                }
            ),
            CommandAction(
                id: "preferences.show",
                name: "Show Preferences",
                description: "Open terminal settings",
                shortcut: paletteShortcutLabel("preferences.show", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.openPreferences(nil) }
                }
            ),
            CommandAction(
                id: "welcome.show",
                name: "Show Welcome",
                description: "Show the welcome overlay with shortcuts",
                shortcut: "Cmd+?",
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.showWelcome() }
                }
            ),
            CommandAction(
                id: "tabbar.toggle",
                name: "Toggle Tab Bar",
                description: "Show or hide the sidebar tab bar",
                shortcut: nil,
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleTabBarAction(nil) }
                }
            ),
            CommandAction(
                id: "notifications.toggle",
                name: "Toggle Notifications",
                description: "Show or hide the notification panel",
                shortcut: paletteShortcutLabel("notifications.toggle", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleNotificationPanel() }
                }
            ),
            CommandAction(
                id: "browser.toggle",
                name: "Toggle Browser",
                description: "Show or hide the in-app browser",
                shortcut: paletteShortcutLabel("browser.toggle", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleBrowser() }
                }
            ),
            CommandAction(
                id: "theme.cycle",
                name: "Cycle Color Scheme",
                description: "Switch between Mocha, One Dark, Dracula, Solarized",
                shortcut: nil,
                category: .theme,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleTheme() }
                }
            ),
            CommandAction(
                id: "workspace.browser",
                name: "Open Browser Panel",
                description: "Open a browser panel alongside the terminal",
                shortcut: "Cmd+Option+B",
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.splitWithBrowserAction(nil) }
                }
            ),
            CommandAction(
                id: "workspace.markdown",
                name: "Open Markdown Panel",
                description: "Open a markdown viewer alongside the terminal",
                shortcut: nil,
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.splitWithMarkdownAction(nil) }
                }
            ),
            CommandAction(
                id: "remote.toggle",
                name: "Toggle Remote Workspaces",
                description: "Show or hide the remote workspace panel",
                shortcut: "Cmd+Shift+R",
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleRemoteWorkspacePanel() }
                }
            ),
            CommandAction(
                id: "browser.history",
                name: "Browser History",
                description: "Show or hide the browser history panel",
                shortcut: nil,
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleBrowserHistory() }
                }
            ),
            CommandAction(
                id: "browser.bookmarks",
                name: "Browser Bookmarks",
                description: "Show or hide the browser bookmarks panel",
                shortcut: nil,
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleBrowserBookmarks() }
                }
            ),
            CommandAction(
                id: "sidebar.transparency",
                name: "Toggle Sidebar Transparency",
                description: "Switch between transparent and solid sidebar background",
                shortcut: nil,
                category: .theme,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor [weak self] in
                        guard let tabBar = self?.tabBarView else { return }
                        tabBar.setSidebarTransparent(!tabBar.isSidebarTransparent)
                    }
                }
            ),
            CommandAction(
                id: "splits.equalize",
                name: "Equalize Splits",
                description: "Set all split panes to equal size",
                shortcut: paletteShortcutLabel("splits.equalize", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.activeSplitManager?.handleSplitAction(.equalizeSplits)
                    }
                }
            ),
            CommandAction(
                id: "splits.zoom",
                name: "Toggle Split Zoom",
                description: "Maximize the focused pane or restore equal sizes",
                shortcut: paletteShortcutLabel("splits.zoom", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.activeSplitManager?.handleSplitAction(.toggleZoom)
                    }
                }
            ),
            CommandAction(
                id: "navigation.splitLeft",
                name: "Navigate Split Left",
                description: "Move focus to the split pane on the left",
                shortcut: paletteShortcutLabel("navigation.splitLeft", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.navigateSplitLeftAction(nil) }
                }
            ),
            CommandAction(
                id: "navigation.splitRight",
                name: "Navigate Split Right",
                description: "Move focus to the split pane on the right",
                shortcut: paletteShortcutLabel("navigation.splitRight", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.navigateSplitRightAction(nil) }
                }
            ),
            CommandAction(
                id: "navigation.splitUp",
                name: "Navigate Split Up",
                description: "Move focus to the split pane above",
                shortcut: paletteShortcutLabel("navigation.splitUp", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.navigateSplitUpAction(nil) }
                }
            ),
            CommandAction(
                id: "navigation.splitDown",
                name: "Navigate Split Down",
                description: "Move focus to the split pane below",
                shortcut: paletteShortcutLabel("navigation.splitDown", fallback: nil),
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.navigateSplitDownAction(nil) }
                }
            ),
            CommandAction(
                id: "tabs.next",
                name: "Next Tab",
                description: "Switch to the next tab",
                shortcut: paletteShortcutLabel("tabs.next", fallback: nil),
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.tabManager.nextTab() }
                }
            ),
            CommandAction(
                id: "tabs.previous",
                name: "Previous Tab",
                description: "Switch to the previous tab",
                shortcut: paletteShortcutLabel("tabs.previous", fallback: nil),
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.tabManager.previousTab() }
                }
            ),
            CommandAction(
                id: "tabs.goto1",
                name: "Go to Tab 1",
                description: "Switch to the first tab",
                shortcut: paletteShortcutLabel("tabs.goto1", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab1(nil) } }
            ),
            CommandAction(
                id: "tabs.goto2",
                name: "Go to Tab 2",
                description: "Switch to the second tab",
                shortcut: paletteShortcutLabel("tabs.goto2", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab2(nil) } }
            ),
            CommandAction(
                id: "tabs.goto3",
                name: "Go to Tab 3",
                description: "Switch to the third tab",
                shortcut: paletteShortcutLabel("tabs.goto3", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab3(nil) } }
            ),
            CommandAction(
                id: "tabs.goto4",
                name: "Go to Tab 4",
                description: "Switch to the fourth tab",
                shortcut: paletteShortcutLabel("tabs.goto4", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab4(nil) } }
            ),
            CommandAction(
                id: "tabs.goto5",
                name: "Go to Tab 5",
                description: "Switch to the fifth tab",
                shortcut: paletteShortcutLabel("tabs.goto5", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab5(nil) } }
            ),
            CommandAction(
                id: "tabs.goto6",
                name: "Go to Tab 6",
                description: "Switch to the sixth tab",
                shortcut: paletteShortcutLabel("tabs.goto6", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab6(nil) } }
            ),
            CommandAction(
                id: "tabs.goto7",
                name: "Go to Tab 7",
                description: "Switch to the seventh tab",
                shortcut: paletteShortcutLabel("tabs.goto7", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab7(nil) } }
            ),
            CommandAction(
                id: "tabs.goto8",
                name: "Go to Tab 8",
                description: "Switch to the eighth tab",
                shortcut: paletteShortcutLabel("tabs.goto8", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab8(nil) } }
            ),
            CommandAction(
                id: "tabs.goto9",
                name: "Go to Tab 9",
                description: "Switch to the ninth tab",
                shortcut: paletteShortcutLabel("tabs.goto9", fallback: nil),
                category: .tabs,
                handler: { [weak self] in self?.dismissCommandPalette(); Task { @MainActor in self?.gotoTab9(nil) } }
            ),
            CommandAction(
                id: "navigation.quickswitch",
                name: "Quick Switch",
                description: "Open the quick tab switcher",
                shortcut: paletteShortcutLabel("navigation.quickswitch", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        _ = self?.quickSwitchController?.performQuickSwitch()
                    }
                }
            ),
            CommandAction(
                id: "navigation.quickterminal",
                name: "Toggle Quick Terminal",
                description: "Show or hide the dropdown quick terminal",
                shortcut: paletteShortcutLabel("navigation.quickterminal", fallback: nil),
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        (NSApp.delegate as? AppDelegate)?.quickTerminalController?.toggle()
                    }
                }
            ),
            CommandAction(
                id: "worktree.create",
                name: "Create Agent Worktree Tab",
                description: "Create a cocxy-managed git worktree off the active tab's origin repo",
                shortcut: paletteShortcutLabel("worktree.create", fallback: nil),
                category: .worktree,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        guard let delegate = NSApp.delegate as? AppDelegate else { return }
                        _ = await delegate.performWorktreeCLIRequest(
                            kind: "add",
                            params: [:]
                        )
                    }
                }
            ),
            CommandAction(
                id: "worktree.remove",
                name: "Remove Current Worktree",
                description: "Remove the cocxy-managed worktree attached to the active tab (refuses when dirty)",
                shortcut: paletteShortcutLabel("worktree.remove", fallback: nil),
                category: .worktree,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        guard let delegate = NSApp.delegate as? AppDelegate,
                              let tabID = self?.tabManager.activeTabID,
                              let tab = self?.tabManager.tab(for: tabID),
                              let worktreeID = tab.worktreeID else { return }
                        _ = await delegate.performWorktreeCLIRequest(
                            kind: "remove",
                            params: ["id": worktreeID]
                        )
                    }
                }
            ),
        ]

        engine.registerActions(actions)
        return engine
    }

    func dismissCommandPalette() {
        commandPaletteViewModel?.isVisible = false
        commandPaletteHostingView?.removeFromSuperview()
        commandPaletteHostingView = nil
        isCommandPaletteVisible = false
        focusActiveTerminalSurface()
    }

    // MARK: - Dashboard Panel (Cmd+Option+A)

    func toggleDashboard() {
        if isDashboardVisible {
            dismissDashboard()
        } else {
            showDashboardPanel()
        }
    }

    @objc func toggleDashboardAction(_ sender: Any?) {
        toggleDashboard()
    }

    func showDashboardPanel() {
        guard let overlayContainer = overlayContainerView else { return }

        if dashboardViewModel == nil {
            dashboardViewModel = injectedDashboardViewModel ?? AgentDashboardViewModel()
        }

        guard let viewModel = dashboardViewModel else { return }

        dashboardHostingView?.removeFromSuperview()
        var swiftUIView = DashboardPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissDashboard() },
            currentWindowID: windowID
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelWidth: CGFloat = DashboardPanelView.panelWidth
        let containerBounds = overlayContainer.bounds

        // Position at target directly to avoid animation issues.
        let targetX = containerBounds.width - panelWidth
        hostingView.frame = NSRect(
            x: targetX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.dashboardHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isDashboardVisible = true
        layoutRightDockedAgentPanels()
    }

    func dismissDashboard() {
        guard let hostingView = dashboardHostingView,
              let overlayContainer = overlayContainerView else {
            dashboardHostingView?.removeFromSuperview()
            dashboardHostingView = nil
            isDashboardVisible = false
            return
        }

        isDashboardVisible = false

        // Animate slide-out to the right, then remove.
        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.dashboardHostingView?.removeFromSuperview()
                self?.dashboardHostingView = nil
            }
        })

        layoutRightDockedAgentPanels()
    }

    // MARK: - Code Review Panel (Cmd+Option+R)

    func toggleCodeReview() {
        if isCodeReviewVisible {
            dismissCodeReview()
        } else {
            showCodeReviewPanel()
        }
    }

    @objc func toggleCodeReviewAction(_ sender: Any?) {
        toggleCodeReview()
    }

    func showCodeReviewPanel() {
        guard let overlayContainer = overlayContainerView else { return }

        dismissCodeReviewSuggestion()
        let viewModel = resolveCodeReviewViewModel()
        viewModel.refreshDiffs()

        codeReviewHostingView?.removeFromSuperview()
        let panelWidth = clampedCodeReviewPanelWidth(
            preferredCodeReviewPanelWidth,
            containerWidth: overlayContainer.bounds.width
        )
        codeReviewPanelWidth = panelWidth
        var swiftUIView = makeCodeReviewPanelView(viewModel: viewModel, panelWidth: panelWidth)
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelY = statusBarHostingView?.frame.height ?? 24
        hostingView.frame = NSRect(
            x: overlayContainer.bounds.width - panelWidth,
            y: panelY,
            width: panelWidth,
            height: max(0, overlayContainer.bounds.height - panelY)
        )
        hostingView.autoresizingMask = [.height, .minXMargin]

        codeReviewHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        isCodeReviewVisible = true
        viewModel.isVisible = true
        layoutRightDockedAgentPanels()
    }

    func showCodeReviewSuggestion(for viewModel: CodeReviewPanelViewModel) {
        guard let overlayContainer = overlayContainerView else { return }
        guard !isCodeReviewVisible else { return }

        codeReviewSuggestionHostingView?.removeFromSuperview()
        let swiftUIView = CodeReviewOpenSuggestionView(
            fileCount: viewModel.currentDiffs.count,
            agentCount: max(viewModel.reviewAgentSessions.count, 1),
            onOpen: { [weak self] in
                self?.dismissCodeReviewSuggestion()
                self?.showCodeReviewPanel()
            },
            onDismiss: { [weak self] in
                self?.dismissCodeReviewSuggestion()
            }
        )
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let width: CGFloat = 390
        let height: CGFloat = 90
        let bottomInset = (statusBarHostingView?.frame.height ?? 24) + 14
        hostingView.frame = NSRect(
            x: max(12, overlayContainer.bounds.width - width - 18),
            y: bottomInset,
            width: width,
            height: height
        )
        hostingView.autoresizingMask = [.minXMargin, .maxYMargin]
        codeReviewSuggestionHostingView = hostingView
        overlayContainer.addSubview(hostingView)
    }

    func dismissCodeReviewSuggestion() {
        codeReviewSuggestionHostingView?.removeFromSuperview()
        codeReviewSuggestionHostingView = nil
    }

    func dismissCodeReview() {
        guard let hostingView = codeReviewHostingView,
              let overlayContainer = overlayContainerView else {
            codeReviewHostingView?.removeFromSuperview()
            codeReviewHostingView = nil
            codeReviewViewModel?.isVisible = false
            isCodeReviewVisible = false
            return
        }

        isCodeReviewVisible = false
        codeReviewViewModel?.isVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.codeReviewHostingView?.removeFromSuperview()
                self?.codeReviewHostingView = nil
                self?.layoutRightDockedAgentPanels()
                self?.focusActiveTerminalSurface()
            }
        })
    }

    func adjustCodeReviewPanelWidth(by delta: CGFloat) {
        setCodeReviewPanelWidth(preferredCodeReviewPanelWidth + delta)
    }

    func setCodeReviewPanelWidth(_ proposedWidth: CGFloat) {
        updatePreferredCodeReviewPanelWidth(proposedWidth)
        if isCodeReviewVisible {
            layoutRightDockedAgentPanels()
        } else {
            codeReviewPanelWidth = preferredCodeReviewPanelWidth
        }
    }

    func resolveCodeReviewViewModel() -> CodeReviewPanelViewModel {
        if let codeReviewViewModel {
            configureCodeReviewViewModel(codeReviewViewModel)
            return codeReviewViewModel
        }

        if let injectedCodeReviewViewModel {
            codeReviewViewModel = injectedCodeReviewViewModel
            configureCodeReviewViewModel(injectedCodeReviewViewModel)
            return injectedCodeReviewViewModel
        }

        let hookReceiver = (NSApp.delegate as? AppDelegate)?.hookEventReceiver
        let tracker = injectedSessionDiffTracker ?? SessionDiffTrackerImpl()
        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: hookReceiver
        )
        codeReviewViewModel = viewModel
        configureCodeReviewViewModel(viewModel)
        return viewModel
    }

    private func configureCodeReviewViewModel(_ viewModel: CodeReviewPanelViewModel) {
        viewModel.activeTabCwdProvider = { [weak self] in
            self?.currentCodeReviewWorkingDirectory()
        }
        viewModel.activeTabIDProvider = { [weak self] in
            self?.visibleTabID ?? self?.tabManager.activeTabID
        }
        viewModel.activeSessionIdProvider = { [weak self] in
            guard let self,
                  let tracker = self.injectedSessionDiffTracker,
                  let workingDirectory = self.currentCodeReviewWorkingDirectory() else {
                return nil
            }
            return tracker.latestSessionId(for: workingDirectory)
        }
        viewModel.referenceProvider = { [weak self] in
            guard let self,
                  let tabID = self.visibleTabID ?? self.tabManager.activeTabID else {
                return nil
            }
            return self.tabManager.tab(for: tabID)?.gitBranch
        }
        viewModel.ptyWriteHandler = { [weak self] text, sessionId, workingDirectory, tabID in
            self?.sendCodeReviewFeedback(
                text,
                sessionId: sessionId,
                workingDirectory: workingDirectory,
                tabID: tabID
            ) ?? false
        }
        viewModel.autoShowEnabledProvider = { [weak self] in
            self?.configService?.current.codeReview.autoShowOnSessionEnd ?? true
        }
        viewModel.createPullRequestHandler = { [weak self, weak viewModel] title, body, baseBranch, draft in
            guard let self, let viewModel else { throw GitHubCLIError.notAGitRepository(path: "") }
            guard let workingDirectory = await MainActor.run(body: { viewModel.reviewActionWorkingDirectory }) else {
                throw GitHubCLIError.notAGitRepository(path: "")
            }
            return try await self.performCodeReviewCreatePullRequest(
                title: title,
                body: body,
                baseBranch: baseBranch,
                draft: draft,
                workingDirectory: workingDirectory
            )
        }
        // Merge integration (v0.1.86). Routed through the same shared
        // GitHubService used by the GitHub pane so the actor serialises
        // every gh subprocess across both surfaces.
        viewModel.mergePullRequestHandler = { [weak self, weak viewModel] request in
            guard let self, let viewModel else { throw GitHubCLIError.notAGitRepository(path: "") }
            guard let workingDirectory = await MainActor.run(body: { viewModel.reviewActionWorkingDirectory }) else {
                throw GitHubCLIError.notAGitRepository(path: "")
            }
            return try await self.performCodeReviewMergePullRequest(
                request: request,
                workingDirectory: workingDirectory
            )
        }
        viewModel.pullRequestMergeabilityHandler = { [weak self, weak viewModel] number in
            guard let self, let viewModel else {
                throw GitHubCLIError.notAGitRepository(path: "")
            }
            guard let workingDirectory = await MainActor.run(body: { viewModel.reviewActionWorkingDirectory }) else {
                throw GitHubCLIError.notAGitRepository(path: "")
            }
            return try await self.performCodeReviewPullRequestMergeability(
                number: number,
                workingDirectory: workingDirectory
            )
        }
        viewModel.activePullRequestDetectionHandler = { [weak self, weak viewModel] branch in
            guard let self, let viewModel else { return nil }
            guard let workingDirectory = await MainActor.run(body: { viewModel.reviewActionWorkingDirectory }) else {
                return nil
            }
            return try await self.performCodeReviewPullRequestNumberLookup(
                forBranch: branch,
                workingDirectory: workingDirectory
            )
        }
        viewModel.activeBranchProvider = { [weak viewModel] in
            viewModel?.gitStatus?.branch
        }
        let dashboardVM = dashboardViewModel
            ?? injectedDashboardViewModel
            ?? (NSApp.delegate as? AppDelegate)?.agentDashboardViewModel
        if let dashboardVM {
            viewModel.bindAgentSessionsPublisher(dashboardVM.sessionsPublisher)
        }

        if codeReviewCancellables.isEmpty {
            viewModel.$shouldAutoShow
                .removeDuplicates()
                .filter { $0 }
                .sink { [weak self, weak viewModel] _ in
                    guard let self, let viewModel else { return }
                    self.showCodeReviewSuggestion(for: viewModel)
                    viewModel.shouldAutoShow = false
                }
                .store(in: &codeReviewCancellables)
        }
    }

    func codeReviewStatsSnapshot() -> [String: String] {
        let viewModel = resolveCodeReviewViewModel()
        let totalAdditions = viewModel.currentDiffs.reduce(0) { $0 + $1.additions }
        let totalDeletions = viewModel.currentDiffs.reduce(0) { $0 + $1.deletions }
        var data: [String: String] = [
            "visible": isCodeReviewVisible ? "true" : "false",
            "files": "\(viewModel.currentDiffs.count)",
            "additions": "\(totalAdditions)",
            "deletions": "\(totalDeletions)",
            "pending_comments": "\(viewModel.pendingCommentCount)",
            "review_rounds": "\(viewModel.reviewRounds.count)",
            "mode": viewModel.diffMode.rawValue
        ]
        if let selectedFilePath = viewModel.selectedFilePath {
            data["selected_file"] = selectedFilePath
        }
        if let sessionID = viewModel.activeSessionId {
            data["session_id"] = sessionID
        }
        return data
    }

    func refreshCodeReviewFromCLI() -> [String: String] {
        let viewModel = resolveCodeReviewViewModel()
        viewModel.refreshDiffs()
        var data = codeReviewStatsSnapshot()
        data["status"] = "refreshing"
        return data
    }

    func submitCodeReviewFromCLI() -> [String: String] {
        let viewModel = resolveCodeReviewViewModel()
        let pendingCount = viewModel.pendingCommentCount
        guard pendingCount > 0 else {
            return ["status": "no_comments", "pending_comments": "0"]
        }
        viewModel.submitComments()
        return [
            "status": "submitted",
            "submitted_comments": "\(pendingCount)"
        ]
    }

    private func currentCodeReviewWorkingDirectory() -> URL? {
        if let surfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID,
           let surfaceDirectory = surfaceWorkingDirectories[surfaceID] {
            return surfaceDirectory
        }
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return nil }
        return tabManager.tab(for: tabID)?.workingDirectory
    }

    private func sendCodeReviewFeedback(
        _ text: String,
        sessionId: String?,
        workingDirectory: URL?,
        tabID: TabID?
    ) -> Bool {
        guard let surfaceID = resolveCodeReviewSurfaceID(
            sessionId: sessionId,
            workingDirectory: workingDirectory,
            tabID: tabID
        ) else {
            return false
        }
        bridge.sendText(text, to: surfaceID)
        return true
    }

    private func resolveCodeReviewSurfaceID(
        sessionId: String?,
        workingDirectory: URL?,
        tabID: TabID?
    ) -> SurfaceID? {
        if let tabID, let liveSurface = preferredCodeReviewSurfaceID(for: tabID) {
            return liveSurface
        }

        let resolvedWorkingDirectory = sessionId
            .flatMap { injectedSessionDiffTracker?.workingDirectory(for: $0) }
            ?? workingDirectory

        if let sessionId,
           let matchingTab = tabManager.tabs.first(where: {
               injectedSessionDiffTracker?.latestSessionId(for: $0.workingDirectory) == sessionId
           }),
           let surfaceID = preferredCodeReviewSurfaceID(for: matchingTab.id) {
            return surfaceID
        }

        if let resolvedWorkingDirectory {
            let standardized = resolvedWorkingDirectory.standardizedFileURL
            if let matchingTab = tabManager.tabs.first(where: {
                $0.workingDirectory.standardizedFileURL == standardized
            }),
               let surfaceID = preferredCodeReviewSurfaceID(for: matchingTab.id) {
                return surfaceID
            }
        }

        return nil
    }

    private func preferredCodeReviewSurfaceID(for tabID: TabID) -> SurfaceID? {
        func isLive(_ surfaceID: SurfaceID) -> Bool {
            guard let cocxyBridge = bridge as? CocxyCoreBridge else { return true }
            return cocxyBridge.withTerminalLock(surfaceID) { _ in true } == true
        }

        if displayedTabID == tabID {
            if let focusedSurfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID,
               isLive(focusedSurfaceID) {
                return focusedSurfaceID
            }
            if let activeSurfaceID = activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
               isLive(activeSurfaceID) {
                return activeSurfaceID
            }
        }

        if let primarySurfaceID = tabSurfaceMap[tabID], isLive(primarySurfaceID) {
            return primarySurfaceID
        }

        return surfaceIDs(for: tabID).first(where: isLive)
    }

    // MARK: - Search Bar (Cmd+F)

    func toggleSearchBar() {
        if isSearchBarVisible {
            dismissSearchBar()
        } else {
            showSearchBarOverlay()
        }
    }

    @objc func toggleSearchBarAction(_ sender: Any?) {
        toggleSearchBar()
    }

    func showSearchBarOverlay() {
        guard let container = terminalContainerView else { return }

        if searchBarViewModel == nil {
            searchBarViewModel = ScrollbackSearchBarViewModel()
        }
        guard let viewModel = searchBarViewModel else { return }

        searchQueryCancellable?.cancel()
        searchQueryCancellable = Publishers.CombineLatest3(
            viewModel.$query,
            viewModel.$caseSensitive,
            viewModel.$useRegex
        )
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .removeDuplicates(by: { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
            })
            .sink { [weak self, weak viewModel] query, caseSensitive, useRegex in
                guard let self, let viewModel else { return }
                let options = SearchOptions(
                    query: query,
                    caseSensitive: caseSensitive,
                    useRegex: useRegex
                )

                if let surfaceID = self.activeSearchSurfaceID(),
                   let nativeResults = self.bridge.searchScrollback(
                       surfaceID: surfaceID,
                       options: options
                   ) {
                    viewModel.applySearchResults(nativeResults)
                    return
                }

                let searchLines = self.searchLinesForActiveSurface()
                viewModel.performSearch(in: searchLines)
            }

        searchBarHostingView?.removeFromSuperview()
        var swiftUIView = ScrollbackSearchBarView(
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.dismissSearchBar()
            }
        )
        swiftUIView.onNavigateToResult = { [weak self] result in
            guard let self, let surfaceID = self.activeSearchSurfaceID() else { return }
            // Scroll to the line containing the search match.
            // Uses the active terminal engine's scrollback navigation API.
            self.bridge.scrollToSearchResult(
                surfaceID: surfaceID,
                lineNumber: result.lineNumber
            )
        }
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.frame = NSRect(x: 0, y: container.bounds.height - 40,
                                   width: container.bounds.width, height: 40)
        hostingView.autoresizingMask = [.width, .minYMargin]
        self.searchBarHostingView = hostingView

        container.addSubview(hostingView)
        isSearchBarVisible = true
    }

    func dismissSearchBar() {
        searchQueryCancellable?.cancel()
        searchQueryCancellable = nil
        searchBarHostingView?.removeFromSuperview()
        searchBarHostingView = nil
        isSearchBarVisible = false
        focusActiveTerminalSurface()
    }

    private func activeSearchSurfaceID() -> SurfaceID? {
        activeTerminalSurfaceView?.terminalViewModel?.surfaceID
    }

    private func searchLinesForActiveSurface() -> [String] {
        guard let surfaceID = activeSearchSurfaceID(),
              let cocxyBridge = bridge as? CocxyCoreBridge else {
            return terminalOutputBuffer.lines
        }

        let historyLines = cocxyBridge.historyLines(for: surfaceID)
        return historyLines.isEmpty ? terminalOutputBuffer.lines : historyLines
    }

    // MARK: - Smart Routing Overlay (Cmd+Shift+U)

    func showSmartRouting() {
        guard let overlayContainer = overlayContainerView else { return }

        if smartRoutingViewModel == nil {
            let dashVM = dashboardViewModel ?? AgentDashboardViewModel()
            if dashboardViewModel == nil { dashboardViewModel = dashVM }
            let router = SmartAgentRouterImpl(dashboard: dashVM, tabNavigator: self)
            smartRoutingViewModel = SmartRoutingOverlayViewModel(router: router)
        }

        guard let viewModel = smartRoutingViewModel else { return }
        viewModel.refresh()

        smartRoutingHostingView?.removeFromSuperview()
        let swiftUIView = SmartRoutingOverlayView(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.dismissSmartRouting()
            }
        )
        let overlayView = AnyView(
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { [weak self] in
                        self?.dismissSmartRouting()
                    }
                swiftUIView
            }
        )
        let hostingView = FocusableHostingView(rootView: overlayView)
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        self.smartRoutingHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isSmartRoutingVisible = true
        window?.makeFirstResponder(hostingView)
    }

    func dismissSmartRouting() {
        smartRoutingHostingView?.removeFromSuperview()
        smartRoutingHostingView = nil
        smartRoutingViewModel = nil
        isSmartRoutingVisible = false
        focusActiveTerminalSurface()
    }

    @objc func showSmartRoutingAction(_ sender: Any?) {
        if isSmartRoutingVisible {
            dismissSmartRouting()
        } else {
            showSmartRouting()
        }
    }

    // MARK: - Timeline Panel (Cmd+Shift+T)

    func toggleTimeline() {
        if isTimelineVisible {
            dismissTimeline()
        } else {
            showTimelinePanel()
        }
    }

    @objc func toggleTimelineAction(_ sender: Any?) {
        toggleTimeline()
    }

    func showTimelinePanel() {
        guard let overlayContainer = overlayContainerView else { return }

        timelineHostingView?.removeFromSuperview()

        let store = injectedTimelineStore ?? AgentTimelineStoreImpl()
        let vm = TimelineViewModel(
            store: store,
            onExportJSON: { [weak store] in
                guard let store = store else { return }
                let data = TimelineExporter.exportJSON(events: store.allEvents)
                MainWindowController.saveExportedData(data, suggestedName: "timeline.json")
            },
            onExportMarkdown: { [weak store] in
                guard let store = store else { return }
                let markdown = TimelineExporter.exportMarkdown(events: store.allEvents)
                if let data = markdown.data(using: .utf8) {
                    MainWindowController.saveExportedData(data, suggestedName: "timeline.md")
                }
            }
        )
        self.timelineViewModel = vm

        var swiftUIView = TimelineView(
            viewModel: vm,
            onDismiss: { [weak self] in self?.dismissTimeline() },
            currentWindowID: windowID
        )
        swiftUIView.navigationDispatcher = timelineDispatcher
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelWidth: CGFloat = DashboardPanelView.panelWidth
        let containerBounds = overlayContainer.bounds

        // If the dashboard is visible, place the timeline to its left.
        let targetX: CGFloat
        if isDashboardVisible {
            targetX = containerBounds.width - panelWidth * 2
        } else {
            targetX = containerBounds.width - panelWidth
        }

        // Position at target directly.
        hostingView.frame = NSRect(
            x: targetX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.timelineHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isTimelineVisible = true
        layoutRightDockedAgentPanels()
    }

    func dismissTimeline() {
        guard let hostingView = timelineHostingView,
              let overlayContainer = overlayContainerView else {
            timelineHostingView?.removeFromSuperview()
            timelineHostingView = nil
            timelineViewModel = nil
            isTimelineVisible = false
            return
        }

        isTimelineVisible = false

        // Animate slide-out to the right, then remove.
        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.timelineHostingView?.removeFromSuperview()
                self?.timelineHostingView = nil
                self?.timelineViewModel = nil
                self?.layoutRightDockedAgentPanels()
            }
        })
    }

    func layoutRightDockedAgentPanels() {
        guard let overlayContainer = overlayContainerView else { return }

        struct DockedPanel {
            let width: CGFloat
            let view: NSView
            let avoidsStatusBar: Bool
        }

        if isCodeReviewVisible {
            let reviewWidth = clampedCodeReviewPanelWidth(
                preferredCodeReviewPanelWidth,
                containerWidth: overlayContainer.bounds.width
            )
            codeReviewPanelWidth = reviewWidth
            syncCodeReviewPanelRootView(panelWidth: reviewWidth)
        }

        if isGitHubPaneVisible {
            let ghWidth = clampedGitHubPanePanelWidth(
                preferredGitHubPanePanelWidth,
                containerWidth: overlayContainer.bounds.width
            )
            gitHubPanePanelWidth = ghWidth
            syncGitHubPaneRootView(panelWidth: ghWidth)
        }

        let visiblePanels: [DockedPanel] = [
            isTimelineVisible ? DockedPanel(width: DashboardPanelView.panelWidth, view: timelineHostingView!, avoidsStatusBar: false) : nil,
            isDashboardVisible ? DockedPanel(width: DashboardPanelView.panelWidth, view: dashboardHostingView!, avoidsStatusBar: false) : nil,
            isCodeReviewVisible ? DockedPanel(width: codeReviewPanelWidth, view: codeReviewHostingView!, avoidsStatusBar: true) : nil,
            isGitHubPaneVisible ? DockedPanel(width: gitHubPanePanelWidth, view: gitHubPaneHostingView!, avoidsStatusBar: true) : nil
        ].compactMap { $0 }

        var currentX = overlayContainer.bounds.width
        for panel in visiblePanels.reversed() {
            currentX -= panel.width
            let panelY = panel.avoidsStatusBar ? statusBarHostingView?.frame.height ?? 24 : 0
            panel.view.frame = NSRect(
                x: currentX,
                y: panelY,
                width: panel.width,
                height: max(0, overlayContainer.bounds.height - panelY)
            )
        }

        if let suggestionView = codeReviewSuggestionHostingView {
            let width = suggestionView.frame.width
            let height = suggestionView.frame.height
            let bottomInset = (statusBarHostingView?.frame.height ?? 24) + 14
            suggestionView.frame = NSRect(
                x: max(12, overlayContainer.bounds.width - width - 18),
                y: bottomInset,
                width: width,
                height: height
            )
        }
    }

    private func makeCodeReviewPanelView(
        viewModel: CodeReviewPanelViewModel,
        panelWidth: CGFloat
    ) -> CodeReviewPanelView {
        let minimumWidth = minimumCodeReviewPanelWidth()
        let maximumWidth = maximumCodeReviewPanelWidth()

        return CodeReviewPanelView(
            viewModel: viewModel,
            panelWidth: panelWidth,
            canDecreaseWidth: panelWidth > minimumWidth + 1,
            canIncreaseWidth: panelWidth < maximumWidth - 1,
            onDecreaseWidth: { [weak self] in
                self?.adjustCodeReviewPanelWidth(by: -CodeReviewPanelView.panelResizeStep)
            },
            onIncreaseWidth: { [weak self] in
                self?.adjustCodeReviewPanelWidth(by: CodeReviewPanelView.panelResizeStep)
            },
            onDismiss: { [weak self] in
                self?.dismissCodeReview()
            }
        )
    }

    private func syncCodeReviewPanelRootView(panelWidth: CGFloat) {
        guard isCodeReviewVisible,
              let hostingView = codeReviewHostingView,
              let viewModel = codeReviewViewModel else {
            return
        }
        var view = makeCodeReviewPanelView(viewModel: viewModel, panelWidth: panelWidth)
        view.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        hostingView.rootView = view
    }

    private func minimumCodeReviewPanelWidth(containerWidth: CGFloat? = nil) -> CGFloat {
        let effectiveContainerWidth = containerWidth ?? overlayContainerView?.bounds.width ?? CodeReviewPanelView.defaultPanelWidth
        let occupiedSiblingWidth =
            (isTimelineVisible ? DashboardPanelView.panelWidth : 0) +
            (isDashboardVisible ? DashboardPanelView.panelWidth : 0)
        let reservedTerminalWidth: CGFloat = 280
        let adaptiveMinimum = max(360, effectiveContainerWidth - occupiedSiblingWidth - reservedTerminalWidth)
        return min(CodeReviewPanelView.minimumPanelWidth, adaptiveMinimum)
    }

    private func maximumCodeReviewPanelWidth(containerWidth: CGFloat? = nil) -> CGFloat {
        let effectiveContainerWidth = containerWidth ?? overlayContainerView?.bounds.width ?? CodeReviewPanelView.defaultPanelWidth
        let occupiedSiblingWidth =
            (isTimelineVisible ? DashboardPanelView.panelWidth : 0) +
            (isDashboardVisible ? DashboardPanelView.panelWidth : 0)
        let reservedTerminalWidth: CGFloat = 280
        let minimumWidth = minimumCodeReviewPanelWidth(containerWidth: effectiveContainerWidth)
        let adaptiveMaximum = effectiveContainerWidth - occupiedSiblingWidth - reservedTerminalWidth
        return max(minimumWidth, min(CodeReviewPanelView.maximumPanelWidth, adaptiveMaximum))
    }

    private func clampedCodeReviewPanelWidth(
        _ proposedWidth: CGFloat? = nil,
        containerWidth: CGFloat? = nil
    ) -> CGFloat {
        let minimumWidth = minimumCodeReviewPanelWidth(containerWidth: containerWidth)
        let maximumWidth = maximumCodeReviewPanelWidth(containerWidth: containerWidth)
        let requestedWidth = proposedWidth ?? codeReviewPanelWidth
        return min(max(requestedWidth, minimumWidth), maximumWidth)
    }

    static func saveExportedData(_ data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                NSLog("[Cocxy] Failed to export file: %@", String(describing: error))
            }
        }
    }

    // MARK: - Notification Panel (Cmd+Shift+I)

    func toggleNotificationPanel() {
        if isNotificationPanelVisible {
            dismissNotificationPanel()
        } else {
            showNotificationPanel()
        }
    }

    @objc func toggleNotificationPanelAction(_ sender: Any?) {
        toggleNotificationPanel()
    }

    func showNotificationPanel() {
        guard let overlayContainer = overlayContainerView else { return }

        if notificationPanelViewModel == nil {
            notificationPanelViewModel = NotificationPanelViewModel(
                notificationManager: injectedNotificationManager
            )
            notificationPanelViewModel?.onNavigateToTab = { [weak self] tabId in
                self?.dismissNotificationPanel()
                self?.tabManager.setActive(id: tabId)
            }
        }

        guard let viewModel = notificationPanelViewModel else { return }

        notificationPanelHostingView?.removeFromSuperview()
        var swiftUIView = NotificationPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissNotificationPanel() }
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelWidth: CGFloat = NotificationPanelView.panelWidth
        let containerBounds = overlayContainer.bounds

        // Position at target directly.
        let targetX = containerBounds.width - panelWidth
        hostingView.frame = NSRect(
            x: targetX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.notificationPanelHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isNotificationPanelVisible = true
    }

    func dismissNotificationPanel() {
        guard let hostingView = notificationPanelHostingView,
              let overlayContainer = overlayContainerView else {
            notificationPanelHostingView?.removeFromSuperview()
            notificationPanelHostingView = nil
            isNotificationPanelVisible = false
            return
        }

        isNotificationPanelVisible = false

        // Animate slide-out to the right, then remove.
        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.notificationPanelHostingView?.removeFromSuperview()
                self?.notificationPanelHostingView = nil
            }
        })

        focusActiveTerminalSurface()
    }

    // MARK: - Browser Panel (Cmd+Shift+B)

    func toggleBrowser() {
        if isBrowserVisible {
            dismissBrowser()
        } else {
            showBrowserPanel()
        }
    }

    @objc func toggleBrowserAction(_ sender: Any?) {
        toggleBrowser()
    }

    func showBrowserPanel() {
        guard let overlayContainer = overlayContainerView else { return }

        if browserViewModel == nil {
            let vm = BrowserViewModel()
            vm.historyStore = browserHistoryStore
            vm.activeProfileID = browserProfileManager?.activeProfileID
            browserViewModel = vm
        }

        guard let viewModel = browserViewModel else { return }

        browserHostingView?.removeFromSuperview()
        var swiftUIView = BrowserPanelView(
            viewModel: viewModel,
            profileManager: browserProfileManager,
            onToggleHistory: { [weak self] in self?.toggleBrowserHistory() },
            onToggleBookmarks: { [weak self] in self?.toggleBrowserBookmarks() },
            onDismiss: { [weak self] in self?.dismissBrowser() }
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelWidth: CGFloat = BrowserPanelView.panelWidth
        let containerBounds = overlayContainer.bounds

        // Position at target directly.
        let targetX = containerBounds.width - panelWidth
        hostingView.frame = NSRect(
            x: targetX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.browserHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isBrowserVisible = true
    }

    @discardableResult
    func openInternalBrowser(to rawURL: String) -> Bool {
        if !isBrowserVisible || browserViewModel == nil {
            showBrowserPanel()
        }
        guard let viewModel = browserViewModel else { return false }
        viewModel.navigate(to: rawURL)
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func dismissBrowser() {
        guard let hostingView = browserHostingView,
              let overlayContainer = overlayContainerView else {
            browserHostingView?.removeFromSuperview()
            browserHostingView = nil
            isBrowserVisible = false
            return
        }

        isBrowserVisible = false

        // Animate slide-out to the right, then remove.
        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.browserHostingView?.removeFromSuperview()
                self?.browserHostingView = nil
            }
        })

        focusActiveTerminalSurface()
    }

    // MARK: - Preferences Window (Cmd+,)

    @objc func openPreferences(_ sender: Any?) {
        if let existingWindow = preferencesWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let config = configService?.current ?? .defaults
        let viewModel = PreferencesViewModel(config: config)
        viewModel.onSave = { [weak self] in
            // Reload the config from disk. The configChangedPublisher
            // subscriber fires applyConfig which handles everything:
            // background color, tab position, vibrancy, notification
            // toggles, and bridge restart when needed.
            try? self?.configService?.reload()
        }
        let prefsView = PreferencesView(
            viewModel: viewModel,
            onGitHubSignIn: { [weak self] in
                guard let self else { return }
                let directory = self.currentGitHubPaneWorkingDirectory()
                    ?? FileManager.default.homeDirectoryForCurrentUser
                self.startGitHubAuthentication(in: directory)
            },
            onOpenGitHubCLIInstallGuide: { [weak self] in
                self?.openInternalBrowser(to: "https://cli.github.com/")
            }
        )
        let hostingController = NSHostingController(rootView: prefsView)
        let prefsWindow = NSWindow(contentViewController: hostingController)
        prefsWindow.title = "Cocxy Terminal Settings"
        prefsWindow.styleMask = [.titled, .closable, .resizable]
        prefsWindow.setContentSize(NSSize(width: 600, height: 400))
        prefsWindow.center()

        // Install the delegate that prompts on close with unsaved changes.
        // Retained as a property because NSWindow.delegate is weak.
        let windowDelegate = PreferencesWindowDelegate(viewModel: viewModel)
        windowDelegate.onClose = { [weak self] in
            guard let self else { return }
            self.preferencesWindow = nil
            self.preferencesWindowDelegate = nil
            // Restore terminal focus on the next run loop tick to ensure
            // the preferences window is fully ordered out first.
            Task { @MainActor [weak self] in
                guard let self,
                      let surfaceView = self.activeTerminalSurfaceView else { return }
                self.window?.makeKeyAndOrderFront(nil)
                self.window?.makeFirstResponder(surfaceView)
            }
        }
        prefsWindow.delegate = windowDelegate
        self.preferencesWindowDelegate = windowDelegate

        prefsWindow.makeKeyAndOrderFront(nil)
        self.preferencesWindow = prefsWindow
    }

    // MARK: - About Panel

    @objc func showAboutPanel(_ sender: Any?) {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Cocxy Terminal",
            .applicationVersion: CocxyVersion.current,
            .version: CocxyVersion.current,
            .applicationIcon: AppIconGenerator.generatePlaceholderIcon(),
            .credits: NSAttributedString(
                string: "Agent-aware terminal for macOS\nby Said Arturo Lopez\n\nZero telemetry. MIT License.",
                attributes: [
                    .foregroundColor: NSColor.textColor,
                    .font: NSFont.systemFont(ofSize: 12),
                ]
            ),
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    // MARK: - Welcome Overlay (Cmd+?)

    func showWelcome() {
        guard let overlayContainer = overlayContainerView else { return }

        welcomeHostingView?.removeFromSuperview()
        let swiftUIView = WelcomeOverlayView(
            onDismiss: { [weak self] in self?.dismissWelcome() }
        )
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        self.welcomeHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isWelcomeVisible = true
    }

    func dismissWelcome() {
        welcomeHostingView?.removeFromSuperview()
        welcomeHostingView = nil
        isWelcomeVisible = false
        focusActiveTerminalSurface()
    }

    @objc func showWelcomeAction(_ sender: Any?) {
        if isWelcomeVisible {
            dismissWelcome()
        } else {
            showWelcome()
        }
    }

    // MARK: - Agent Progress Overlay

    /// Updates the agent progress overlay based on the active tab's state.
    ///
    /// Called from `handleTabSwitch` and `wireAgentDetectionToTabs` whenever
    /// the active tab's agent state changes.
    ///
    /// Reads the overlay state from the per-surface store via
    /// `resolveSurfaceAgentState(for:)`, which picks the focused split
    /// first and falls back to the tab primary or `.idle` when no
    /// surface of the tab has an active entry in the store.
    func updateAgentProgressOverlay() {
        guard let container = terminalContainerView,
              let tabID = displayedTabID,
              let tab = tabManager.tab(for: tabID) else {
            dismissAgentProgressOverlay()
            return
        }

        let resolved = resolveSurfaceAgentState(for: tabID)

        let isActive = resolved.agentState == .working || resolved.agentState == .launched
        guard isActive else {
            dismissAgentProgressOverlay()
            return
        }

        // `processName` is a Tab-level field (the foreground PTY process
        // name) used as a last-resort label when neither the resolved
        // surface nor the tab has a detected agent yet. It intentionally
        // stays on the Tab fallback path during Fase 3 because
        // foreground-process tracking is not mirrored into the per-surface
        // store in this phase.
        let agentName = resolved.detectedAgent?.displayName ?? tab.processName ?? "Agent"
        let durationText: String? = resolved.detectedAgent.map { agent in
            let seconds = Int(Date().timeIntervalSince(agent.startedAt))
            if seconds < 60 { return "\(seconds)s" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m" }
            return "\(minutes / 60)h\(minutes % 60)m"
        }

        let overlay = AgentProgressOverlay(
            agentName: agentName,
            toolCount: resolved.agentToolCount,
            errorCount: resolved.agentErrorCount,
            durationText: durationText
        )

        // Reuse or create the hosting view.
        agentProgressHostingView?.removeFromSuperview()
        let hosting = NSHostingView(rootView: overlay)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Allow clicks to pass through to the terminal.
        hosting.wantsLayer = true
        hosting.alphaValue = 0.9

        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        agentProgressHostingView = hosting
    }

    private func dismissAgentProgressOverlay() {
        agentProgressHostingView?.removeFromSuperview()
        agentProgressHostingView = nil
    }

    // MARK: - Dismiss All Overlays (Esc)

    @objc func dismissActiveOverlay(_ sender: Any?) {
        if isWelcomeVisible {
            dismissWelcome()
        } else if isCommandPaletteVisible {
            dismissCommandPalette()
        } else if isSmartRoutingVisible {
            dismissSmartRouting()
        } else if isRemoteWorkspaceVisible {
            dismissRemoteWorkspacePanel()
        } else if isBrowserHistoryVisible {
            dismissBrowserHistory()
        } else if isBrowserBookmarksVisible {
            dismissBrowserBookmarks()
        } else if isBrowserVisible {
            dismissBrowser()
        } else if isNotificationPanelVisible {
            dismissNotificationPanel()
        } else if codeReviewSuggestionHostingView != nil {
            dismissCodeReviewSuggestion()
        } else if isCodeReviewVisible {
            dismissCodeReview()
        } else if isDashboardVisible {
            dismissDashboard()
        } else if isTimelineVisible {
            dismissTimeline()
        } else if isSearchBarVisible {
            dismissSearchBar()
        }
    }

    // MARK: - Vibrancy Override Propagation

    /// Rewrites the `rootView` of every live SwiftUI overlay hosting view
    /// so the forced `NSAppearance` override matches the value the chrome
    /// bordes just adopted.
    ///
    /// Called from `applyEffectiveAppearance` after the permanent chrome
    /// (sidebar, horizontal tab strip, status bar) has already been
    /// updated. Hosting views backed by a concrete
    /// `NSHostingView<ConcreteView>` are rebuilt with the new override in
    /// place; overlays stored as `NSView?` (timeline, remote workspace,
    /// browser history, browser bookmarks, subagent panels) are
    /// re-rooted via their typed hosting view helpers.
    ///
    /// The function is a no-op for overlays that are not visible — both
    /// the `isXxxVisible` flags and the optional hosting-view properties
    /// guard the re-root — so repeatedly calling it during hot-reload is
    /// safe.
    func syncVibrancyOverrideToLiveOverlays(_ override: NSAppearance?) {
        syncCommandPaletteVibrancyOverride(override)
        syncDashboardVibrancyOverride(override)
        syncTimelineVibrancyOverride(override)
        syncCodeReviewVibrancyOverride(override)
        syncNotificationPanelVibrancyOverride(override)
        syncBrowserVibrancyOverride(override)
        syncBrowserHistoryVibrancyOverride(override)
        syncBrowserBookmarksVibrancyOverride(override)
        syncRemoteWorkspaceVibrancyOverride(override)
        syncSearchBarVibrancyOverride(override)
        syncSubagentPanelsVibrancyOverride(override)
    }

    private func syncCommandPaletteVibrancyOverride(_ override: NSAppearance?) {
        guard isCommandPaletteVisible,
              let hostingView = commandPaletteHostingView,
              let viewModel = commandPaletteViewModel else { return }
        var view = CommandPaletteView(viewModel: viewModel)
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncDashboardVibrancyOverride(_ override: NSAppearance?) {
        guard isDashboardVisible,
              let hostingView = dashboardHostingView,
              let viewModel = dashboardViewModel else { return }
        var view = DashboardPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissDashboard() },
            currentWindowID: windowID
        )
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncTimelineVibrancyOverride(_ override: NSAppearance?) {
        guard isTimelineVisible,
              let hostingView = timelineHostingView as? NSHostingView<TimelineView>,
              let viewModel = timelineViewModel else { return }
        var view = TimelineView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissTimeline() },
            currentWindowID: windowID
        )
        view.navigationDispatcher = timelineDispatcher
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncCodeReviewVibrancyOverride(_ override: NSAppearance?) {
        guard isCodeReviewVisible,
              let hostingView = codeReviewHostingView,
              let viewModel = codeReviewViewModel else { return }
        var view = makeCodeReviewPanelView(viewModel: viewModel, panelWidth: codeReviewPanelWidth)
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncNotificationPanelVibrancyOverride(_ override: NSAppearance?) {
        guard isNotificationPanelVisible,
              let hostingView = notificationPanelHostingView,
              let viewModel = notificationPanelViewModel else { return }
        var view = NotificationPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissNotificationPanel() }
        )
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncBrowserVibrancyOverride(_ override: NSAppearance?) {
        guard isBrowserVisible,
              let hostingView = browserHostingView,
              let viewModel = browserViewModel else { return }
        var view = BrowserPanelView(
            viewModel: viewModel,
            profileManager: browserProfileManager,
            onToggleHistory: { [weak self] in self?.toggleBrowserHistory() },
            onToggleBookmarks: { [weak self] in self?.toggleBrowserBookmarks() },
            onDismiss: { [weak self] in self?.dismissBrowser() }
        )
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncBrowserHistoryVibrancyOverride(_ override: NSAppearance?) {
        guard isBrowserHistoryVisible,
              let hostingView = browserHistoryHostingView as? NSHostingView<BrowserHistoryView>,
              let historyStore = browserHistoryStore else { return }
        var view = BrowserHistoryView(
            historyStore: historyStore,
            activeProfileID: browserProfileManager?.activeProfileID,
            onNavigate: { [weak self] url in
                self?.dismissBrowserHistory()
                self?.activeBrowserViewModel()?.navigate(to: url)
            },
            onDismiss: { [weak self] in self?.dismissBrowserHistory() }
        )
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncBrowserBookmarksVibrancyOverride(_ override: NSAppearance?) {
        guard isBrowserBookmarksVisible,
              let hostingView = browserBookmarksHostingView as? NSHostingView<BrowserBookmarksView>,
              let bookmarkStore = browserBookmarkStore else { return }
        var view = BrowserBookmarksView(
            bookmarkStore: bookmarkStore,
            onNavigate: { [weak self] url in
                self?.dismissBrowserBookmarks()
                self?.activeBrowserViewModel()?.navigate(to: url)
            },
            onAddBookmark: { [weak self] in
                guard let vm = self?.activeBrowserViewModel(),
                      let pageURL = vm.currentURL else { return }
                let urlString = pageURL.absoluteString
                let title = vm.pageTitle.isEmpty ? urlString : vm.pageTitle
                try? bookmarkStore.save(BrowserBookmark(
                    title: title,
                    url: urlString
                ))
            },
            onDismiss: { [weak self] in self?.dismissBrowserBookmarks() }
        )
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncRemoteWorkspaceVibrancyOverride(_ override: NSAppearance?) {
        guard isRemoteWorkspaceVisible,
              let hostingView = remoteWorkspaceHostingView as? NSHostingView<RemoteConnectionView>,
              let viewModel = remoteConnectionViewModel else { return }
        var view = RemoteConnectionView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissRemoteWorkspacePanel() },
            sshKeyManager: sshKeyManager,
            sftpExecutor: SystemSFTPExecutor()
        )
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncSearchBarVibrancyOverride(_ override: NSAppearance?) {
        guard isSearchBarVisible,
              let hostingView = searchBarHostingView,
              let viewModel = searchBarViewModel else { return }
        var view = ScrollbackSearchBarView(
            viewModel: viewModel,
            onClose: { [weak self] in self?.dismissSearchBar() }
        )
        view.onNavigateToResult = { [weak self] result in
            guard let self, let surfaceID = self.activeTerminalSurfaceView?.terminalViewModel?.surfaceID else { return }
            self.bridge.scrollToSearchResult(
                surfaceID: surfaceID,
                lineNumber: result.lineNumber
            )
        }
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    private func syncSubagentPanelsVibrancyOverride(_ override: NSAppearance?) {
        for (_, view) in panelContentViews {
            (view as? SubagentContentView)?.setVibrancyAppearanceOverride(override)
        }
    }
}
