// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabLifecycle.swift - Tab creation, destruction, and switching.

import AppKit

// MARK: - Tab Lifecycle

/// Extension that handles tab creation, destruction, surface wiring,
/// and tab switching. Extracted from MainWindowController to reduce
/// the main file's size and improve separation of concerns.
extension MainWindowController {

    // MARK: - Create Tab

    /// Creates a new tab with a terminal surface and switches to it.
    ///
    /// - Parameter workingDirectory: Directory for the new terminal.
    ///   Defaults to the active tab's directory or home.
    @discardableResult
    func createTab(workingDirectory: URL? = nil) -> TabID {
        let dir = workingDirectory
            ?? tabManager.activeTab?.workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        let newTab = tabManager.addTab(workingDirectory: dir)

        let viewModel = TerminalViewModel(engine: bridge)
        let configuredFontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        viewModel.setDefaultFontSize(configuredFontSize)
        let surfaceView = CocxyCoreView(viewModel: viewModel)

        tabViewModels[newTab.id] = viewModel
        tabSurfaceViews[newTab.id] = surfaceView

        createAndWireSurface(
            for: newTab.id,
            in: surfaceView,
            viewModel: viewModel,
            workingDirectory: dir
        )

        // Register this session with the multi-window registry so other
        // windows can see it in the dashboard and notification aggregator.
        let sessionID = SessionID()
        tabSessionMap[newTab.id] = sessionID
        sessionRegistry?.registerSession(SessionEntry(
            sessionID: sessionID,
            ownerWindowID: windowID,
            tabID: newTab.id,
            title: newTab.displayTitle,
            workingDirectory: dir
        ))

        // Load project config from .cocxy.toml if present in the tab's directory.
        let projectConfigService = ProjectConfigService()
        if let projectConfig = projectConfigService.loadConfig(for: dir) {
            tabManager.updateTab(id: newTab.id) { tab in
                tab.projectConfig = projectConfig
            }
        }

        handleTabSwitch(to: newTab.id)
        return newTab.id
    }

    /// Attaches worktree metadata to a tab and points tab-level consumers
    /// at the worktree root. When `sendShellDirectoryChange` is true the
    /// primary PTY also receives a `cd` command so the live shell follows
    /// the metadata instead of leaving the user in the origin repo.
    func attachWorktree(
        _ entry: WorktreeManifest.WorktreeEntry,
        originRepo: URL,
        to tabID: TabID,
        sendShellDirectoryChange: Bool = false
    ) {
        let worktreeRoot = entry.path
        let gitProvider = GitInfoProviderImpl()
        let branch = gitProvider.currentBranch(at: worktreeRoot)

        tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = worktreeRoot
            tab.gitBranch = branch
            tab.worktreeID = entry.id
            tab.worktreeRoot = worktreeRoot
            tab.worktreeOriginRepo = originRepo
            tab.worktreeBranch = entry.branch
            let inheritProjectConfig = configService?.current.worktree.inheritProjectConfig ?? true
            let projectOrigin = inheritProjectConfig ? originRepo : nil
            tab.projectConfig = ProjectConfigService().loadConfig(
                for: worktreeRoot,
                originRepo: projectOrigin
            )
        }

        sessionRegistry?.updateWorkingDirectory(
            sessionIDForTab(tabID),
            directory: worktreeRoot
        )
        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        refreshTabStrip()
        applyProjectConfig(for: tabID)

        guard sendShellDirectoryChange,
              let surfaceID = tabSurfaceMap[tabID] else {
            return
        }
        bridge.sendText(Self.changeDirectoryCommand(for: worktreeRoot), to: surfaceID)
    }

    /// Closes the tab with the given ID, showing a confirmation alert
    /// when the user has enabled `confirmCloseProcess` in their config.
    ///
    /// - Parameter tabID: The tab to close.
    func closeTab(_ tabID: TabID) {
        // Pinned tabs must never be closed. Check before destroying resources.
        if let tab = tabManager.tab(for: tabID), tab.isPinned {
            return
        }

        let shouldConfirm = configService?.current.general.confirmCloseProcess ?? false
        if shouldConfirm {
            let alert = NSAlert()
            alert.messageText = "Close Tab?"
            alert.informativeText = "Running processes in this tab will be terminated."
            alert.alertStyle = .warning
            alert.icon = AppIconGenerator.generatePlaceholderIcon()
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard let window else { return }
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.confirmWorktreeCloseThenPerform(tabID)
                }
            }
            return
        }
        confirmWorktreeCloseThenPerform(tabID)
    }

    /// Performs the actual tab cleanup: destroys surfaces, removes state,
    /// and switches to the next active tab.
    ///
    /// Extracted from `closeTab` so the confirmation alert can call it
    /// asynchronously after the user confirms.
    ///
    /// - Parameter tabID: The tab to close.
    func performCloseTab(_ tabID: TabID) {
        performCloseTab(tabID, worktreeClosePolicyOverride: nil)
    }

    private func performCloseTab(
        _ tabID: TabID,
        worktreeClosePolicyOverride: WorktreeOnClose?
    ) {
        let isClosingActiveTab = (tabID == tabManager.activeTabID)
        let closingTab = tabManager.tab(for: tabID)

        // Remove this session from the multi-window registry before
        // destroying surfaces, so other windows receive the removal
        // event while the session ID is still valid.
        sessionRegistry?.removeSession(sessionIDForTab(tabID))

        // Destroy the primary terminal surface.
        if let surfaceID = tabSurfaceMap[tabID] {
            clearSurfaceTracking(for: surfaceID)
            // Release any per-surface detection state before the bridge
            // tears the terminal down, so the engine does not retain
            // debounce or hook-session records keyed to a dead surface.
            // The shadow store entry is released in the same step so the
            // surface's agent state does not outlive its terminal.
            injectedAgentDetectionEngine?.clearSurface(surfaceID)
            injectedPerSurfaceStore?.reset(surfaceID: surfaceID)
            bridge.destroySurface(surfaceID)
        }
        tabViewModels[tabID]?.markStopped()

        // Destroy split surfaces belonging to this tab.
        // If the tab is currently active, split state is in the live properties.
        // Otherwise, it is in the saved per-tab dictionaries.
        let tabSplitSurfaces: [SurfaceID: TerminalHostView]
        let tabSplitVMs: [SurfaceID: TerminalViewModel]

        if isClosingActiveTab {
            tabSplitSurfaces = splitSurfaceViews
            tabSplitVMs = splitViewModels
            // Remove the active split view from the container.
            activeSplitView?.removeFromSuperview()
            activeSplitView = nil
            splitSurfaceViews.removeAll()
            splitViewModels.removeAll()
            panelContentViews.removeAll()
        } else {
            tabSplitSurfaces = savedTabSplitSurfaceViews.removeValue(forKey: tabID) ?? [:]
            tabSplitVMs = savedTabSplitViewModels.removeValue(forKey: tabID) ?? [:]
            savedTabSplitViews.removeValue(forKey: tabID)
            savedTabPanelContentViews.removeValue(forKey: tabID)
        }

        for (surfaceID, _) in tabSplitSurfaces {
            clearSurfaceTracking(for: surfaceID)
            // Release per-surface detection state (engine + shadow
            // store) for each split before the bridge frees the
            // underlying terminal.
            injectedAgentDetectionEngine?.clearSurface(surfaceID)
            injectedPerSurfaceStore?.reset(surfaceID: surfaceID)
            bridge.destroySurface(surfaceID)
            tabSplitVMs[surfaceID]?.markStopped()
        }

        // Clear the active reference if closing the currently displayed tab
        // to avoid a stale pointer between removeFromSuperview and handleTabSwitch.
        let closingSurfaceView = tabSurfaceViews[tabID]
        if terminalSurfaceView === closingSurfaceView {
            terminalSurfaceView = nil
        }

        // Remove views and mappings.
        closingSurfaceView?.removeFromSuperview()
        tabSurfaceViews.removeValue(forKey: tabID)
        tabViewModels.removeValue(forKey: tabID)
        tabSurfaceMap.removeValue(forKey: tabID)

        // Clean up per-tab resources to prevent memory leaks.
        tabOutputBuffers.removeValue(forKey: tabID)
        tabCommandTrackers.removeValue(forKey: tabID)
        tabSplitCoordinator.removeSplitManager(for: tabID)
        tabSessionMap.removeValue(forKey: tabID)
        processMonitor?.unregisterTab(tabID)

        // Remove from TabManager (activates next tab).
        tabManager.removeTab(id: tabID)
        handleWorktreeLifecycleAfterTabClose(
            closingTab,
            overridePolicy: worktreeClosePolicyOverride
        )

        if let newActiveID = tabManager.activeTabID {
            handleTabSwitch(to: newActiveID)
        }
    }

    private func confirmWorktreeCloseThenPerform(_ tabID: TabID) {
        guard let tab = tabManager.tab(for: tabID) else {
            performCloseTab(tabID)
            return
        }

        let worktreeConfig = Self.effectiveWorktreeConfig(
            for: tab,
            globalConfig: configService?.current ?? .defaults
        )
        guard tab.worktreeID != nil,
              worktreeConfig.onClose == .prompt,
              let window else {
            performCloseTab(tabID)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Close Worktree Tab?"
        alert.informativeText = """
        This tab is attached to a cocxy-managed git worktree. Keep the worktree on disk, or remove it only if it has no uncommitted changes.
        """
        alert.alertStyle = .warning
        alert.icon = AppIconGenerator.generatePlaceholderIcon()
        alert.addButton(withTitle: "Keep Worktree")
        alert.addButton(withTitle: "Remove if Clean")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                self?.performCloseTab(tabID, worktreeClosePolicyOverride: .keep)
            case .alertSecondButtonReturn:
                self?.performCloseTab(tabID, worktreeClosePolicyOverride: .remove)
            default:
                break
            }
        }
    }

    private func handleWorktreeLifecycleAfterTabClose(
        _ tab: Tab?,
        overridePolicy: WorktreeOnClose?
    ) {
        guard let tab,
              let worktreeID = tab.worktreeID,
              let originRepo = tab.worktreeOriginRepo else {
            return
        }

        let config = Self.effectiveWorktreeConfig(
            for: tab,
            globalConfig: configService?.current ?? .defaults
        )
        let policy = overridePolicy ?? config.onClose
        let store = WorktreeManifestStore.forRepo(
            basePath: config.basePath,
            originRepoPath: originRepo
        )

        switch policy {
        case .keep, .prompt:
            Task.detached {
                try? await store.clearTabBinding(id: worktreeID)
            }

        case .remove:
            Task.detached {
                do {
                    _ = try await AppDelegate.sharedWorktreeService.remove(
                        id: worktreeID,
                        force: false,
                        originRepoPath: originRepo,
                        store: store
                    )
                } catch {
                    // Dirty or missing worktrees must never block tab
                    // closure. The tab is gone, so clear only the manifest
                    // binding and leave the worktree on disk for the user
                    // to inspect/remove explicitly.
                    try? await store.clearTabBinding(id: worktreeID)
                }
            }
        }
    }

    nonisolated static func effectiveWorktreeConfig(
        for tab: Tab,
        globalConfig: CocxyConfig
    ) -> WorktreeConfig {
        guard let projectConfig = tab.projectConfig else {
            return globalConfig.worktree
        }
        return globalConfig.applying(projectOverrides: projectConfig).worktree
    }

    private static func changeDirectoryCommand(for directory: URL) -> String {
        "cd -- \(shellQuotedPath(directory.path))\n"
    }

    private static func shellQuotedPath(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - Surface Wiring

    /// Creates a terminal surface and wires OSC + output handlers.
    ///
    /// Shared by `createTab`, `newTabAction`, and session restoration.
    func createAndWireSurface(
        for tabID: TabID,
        in surfaceView: TerminalHostView,
        viewModel: TerminalViewModel,
        workingDirectory: URL?
    ) {
        do {
            let surfaceID = try bridge.createSurface(
                in: surfaceView,
                workingDirectory: workingDirectory,
                command: nil
            )
            viewModel.markRunning(surfaceID: surfaceID)
            surfaceView.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
            surfaceView.syncSizeWithTerminal()
            tabSurfaceMap[tabID] = surfaceID

            registerSurfaceWithProcessMonitor(surfaceID, tabID: tabID)
            wireSurfaceHandlers(
                for: surfaceID,
                tabID: tabID,
                in: surfaceView,
                initialWorkingDirectory: workingDirectory ?? tabManager.tab(for: tabID)?.workingDirectory
            )
        } catch {
            NSLog("[MainWindowController] Failed to create surface for tab: %@",
                  String(describing: error))
        }
    }
}
