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

        if commandPaletteViewModel == nil {
            let engine = createWiredCommandPaletteEngine()
            commandPaletteViewModel = CommandPaletteViewModel(engine: engine)
        }

        guard let viewModel = commandPaletteViewModel else { return }
        viewModel.isVisible = true

        commandPaletteHostingView?.removeFromSuperview()
        let swiftUIView = CommandPaletteView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        self.commandPaletteHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isCommandPaletteVisible = true
    }

    /// Creates a CommandPaletteEngine with all actions wired to real handlers.
    ///
    /// Actions that require AppKit coordination (toggleDashboard, toggleTimeline, etc.)
    /// are registered with direct handlers referencing `self`, bypassing the coordinator
    /// layer which lacks access to the window controller.
    private func createWiredCommandPaletteEngine() -> CommandPaletteEngineImpl {
        let engine = CommandPaletteEngineImpl()

        // Register actions with direct handlers to the window controller.
        // Each handler first dismisses the palette, then executes the action
        // on the next run loop tick to avoid SwiftUI state mutation during rendering.
        let actions: [CommandAction] = [
            CommandAction(
                id: "tabs.new",
                name: "New Tab",
                description: "Open a new terminal tab",
                shortcut: "Cmd+T",
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.tabManager.addTab() }
                }
            ),
            CommandAction(
                id: "tabs.close",
                name: "Close Tab",
                description: "Close the current tab",
                shortcut: "Cmd+W",
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
                id: "splits.vertical",
                name: "Split Vertical",
                description: "Split the current pane vertically",
                shortcut: "Cmd+Shift+D",
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.splitVerticalAction(nil) }
                }
            ),
            CommandAction(
                id: "splits.horizontal",
                name: "Split Horizontal",
                description: "Split the current pane horizontally",
                shortcut: "Cmd+D",
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
                shortcut: "Cmd+Shift+W",
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
                shortcut: "Cmd+Option+A",
                category: .dashboard,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleDashboard() }
                }
            ),
            CommandAction(
                id: "timeline.toggle",
                name: "Toggle Timeline",
                description: "Show or hide the agent timeline panel",
                shortcut: "Cmd+Shift+T",
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
                shortcut: "Cmd+F",
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.toggleSearchBar() }
                }
            ),
            CommandAction(
                id: "preferences.show",
                name: "Show Preferences",
                description: "Open terminal settings",
                shortcut: "Cmd+,",
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
                shortcut: "Cmd+Shift+I",
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
                shortcut: "Cmd+Shift+B",
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
                shortcut: "Cmd+Shift+E",
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
                shortcut: "Cmd+Shift+F",
                category: .splits,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.activeSplitManager?.handleSplitAction(.toggleZoom)
                    }
                }
            ),
            CommandAction(
                id: "tabs.next",
                name: "Next Tab",
                description: "Switch to the next tab",
                shortcut: "Ctrl+Tab",
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
                shortcut: "Ctrl+Shift+Tab",
                category: .tabs,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.tabManager.previousTab() }
                }
            ),
            CommandAction(
                id: "navigation.quickswitch",
                name: "Quick Switch",
                description: "Open the quick tab switcher",
                shortcut: nil,
                category: .navigation,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        _ = self?.quickSwitchController?.performQuickSwitch()
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
        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
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
        let swiftUIView = DashboardPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissDashboard() }
        )
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

        // If the timeline is already visible, shift it left to make room.
        if isTimelineVisible {
            repositionTimelineForCoexistence()
        }
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

        // If the timeline is still visible, move it back to the right edge.
        if isTimelineVisible {
            repositionTimelineForCoexistence()
        }
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
        searchQueryCancellable = viewModel.$query
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self, weak viewModel] _ in
                guard let self, let viewModel else { return }
                viewModel.performSearch(in: self.terminalOutputBuffer.lines)
            }

        searchBarHostingView?.removeFromSuperview()
        var swiftUIView = ScrollbackSearchBarView(
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.dismissSearchBar()
            }
        )
        swiftUIView.onNavigateToResult = { [weak self] result in
            guard let self,
                  let surfaceID = self.terminalViewModel.surfaceID else { return }
            // Scroll to the line containing the search match.
            // Uses ghostty's native scroll API via binding_action.
            self.bridge.scrollToSearchResult(
                surfaceID: surfaceID,
                lineNumber: result.lineNumber
            )
        }
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
        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
    }

    // MARK: - Smart Routing Overlay (Cmd+Shift+U)

    func showSmartRouting() {
        guard let overlayContainer = overlayContainerView else { return }

        if smartRoutingViewModel == nil {
            let dashVM = dashboardViewModel ?? AgentDashboardViewModel()
            if dashboardViewModel == nil { dashboardViewModel = dashVM }
            let router = SmartAgentRouterImpl(dashboard: dashVM, tabNavigator: nil)
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
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        self.smartRoutingHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isSmartRoutingVisible = true
    }

    func dismissSmartRouting() {
        smartRoutingHostingView?.removeFromSuperview()
        smartRoutingHostingView = nil
        smartRoutingViewModel = nil
        isSmartRoutingVisible = false
        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
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

        let events = injectedTimelineStore?.allEvents ?? []

        var swiftUIView = TimelineView(
            events: events,
            onExportJSON: { [weak self] in
                guard let store = self?.injectedTimelineStore else { return }
                let json = store.allEvents
                let data = TimelineExporter.exportJSON(events: json)
                Self.saveExportedData(data, suggestedName: "timeline.json")
            },
            onExportMarkdown: { [weak self] in
                guard let store = self?.injectedTimelineStore else { return }
                let markdown = TimelineExporter.exportMarkdown(events: store.allEvents)
                if let data = markdown.data(using: .utf8) {
                    Self.saveExportedData(data, suggestedName: "timeline.md")
                }
            },
            onDismiss: { [weak self] in self?.dismissTimeline() }
        )
        swiftUIView.navigationDispatcher = timelineDispatcher
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
    }

    func dismissTimeline() {
        guard let hostingView = timelineHostingView,
              let overlayContainer = overlayContainerView else {
            timelineHostingView?.removeFromSuperview()
            timelineHostingView = nil
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
            }
        })
    }

    /// Repositions the timeline panel based on whether the dashboard is also visible.
    ///
    /// When both panels coexist, the timeline sits to the left of the dashboard.
    /// When only the timeline is visible, it occupies the right edge.
    private func repositionTimelineForCoexistence() {
        guard let overlayContainer = overlayContainerView,
              let hostingView = timelineHostingView else { return }

        let panelWidth: CGFloat = DashboardPanelView.panelWidth
        let containerBounds = overlayContainer.bounds

        let timelineOriginX: CGFloat
        if isDashboardVisible {
            timelineOriginX = containerBounds.width - panelWidth * 2
        } else {
            timelineOriginX = containerBounds.width - panelWidth
        }

        hostingView.frame = NSRect(
            x: timelineOriginX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
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
        let swiftUIView = NotificationPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissNotificationPanel() }
        )
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

        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
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
            browserViewModel = BrowserViewModel()
        }

        guard let viewModel = browserViewModel else { return }

        browserHostingView?.removeFromSuperview()
        let swiftUIView = BrowserPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissBrowser() }
        )
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

        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
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
            guard let self else { return }
            let oldConfig = self.configService?.current ?? .defaults
            try? self.configService?.reload()
            let newConfig = self.configService?.current ?? .defaults

            // Determine if a bridge restart is needed.
            // libghostty embeds font, theme, cursor, and padding at init time —
            // these cannot be changed without destroying and recreating the bridge.
            let needsBridgeRestart =
                oldConfig.appearance.theme != newConfig.appearance.theme ||
                oldConfig.appearance.fontFamily != newConfig.appearance.fontFamily ||
                oldConfig.appearance.fontSize != newConfig.appearance.fontSize ||
                oldConfig.appearance.windowPadding != newConfig.appearance.windowPadding ||
                oldConfig.terminal.cursorStyle != newConfig.terminal.cursorStyle ||
                oldConfig.terminal.cursorBlink != newConfig.terminal.cursorBlink ||
                oldConfig.general.shell != newConfig.general.shell

            if needsBridgeRestart, let appDelegate = NSApp.delegate as? AppDelegate {
                // switchTheme handles full bridge recreation: destroys all surfaces,
                // creates new bridge with updated config, recreates surfaces for
                // every tab, and restores the active tab. Working directories are
                // preserved; shell sessions restart.
                appDelegate.switchTheme(to: newConfig.appearance.theme)
            }

            // Apply UI-only changes that do not require bridge restart.
            self.tabBarView?.setSidebarTransparent(newConfig.appearance.backgroundOpacity < 1.0)
            self.refreshStatusBar()
            self.refreshTabStrip()
        }
        let prefsView = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: prefsView)
        let prefsWindow = NSWindow(contentViewController: hostingController)
        prefsWindow.title = "Cocxy Terminal Settings"
        prefsWindow.styleMask = [.titled, .closable, .resizable]
        prefsWindow.setContentSize(NSSize(width: 600, height: 400))
        prefsWindow.center()

        // Install the delegate that prompts on close with unsaved changes.
        // Retained as a property because NSWindow.delegate is weak.
        let windowDelegate = PreferencesWindowDelegate(viewModel: viewModel)
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
        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
    }

    @objc func showWelcomeAction(_ sender: Any?) {
        if isWelcomeVisible {
            dismissWelcome()
        } else {
            showWelcome()
        }
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
        } else if isDashboardVisible {
            dismissDashboard()
        } else if isTimelineVisible {
            dismissTimeline()
        } else if isSearchBarVisible {
            dismissSearchBar()
        }
    }
}
