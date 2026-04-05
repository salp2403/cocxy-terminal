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
    func createTab(workingDirectory: URL? = nil) {
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

        // Load project config from .cocxy.toml if present in the tab's directory.
        let projectConfigService = ProjectConfigService()
        if let projectConfig = projectConfigService.loadConfig(for: dir) {
            tabManager.updateTab(id: newTab.id) { tab in
                tab.projectConfig = projectConfig
            }
        }

        handleTabSwitch(to: newTab.id)
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
                    self?.performCloseTab(tabID)
                }
            }
            return
        }
        performCloseTab(tabID)
    }

    /// Performs the actual tab cleanup: destroys surfaces, removes state,
    /// and switches to the next active tab.
    ///
    /// Extracted from `closeTab` so the confirmation alert can call it
    /// asynchronously after the user confirms.
    ///
    /// - Parameter tabID: The tab to close.
    func performCloseTab(_ tabID: TabID) {
        let isClosingActiveTab = (tabID == tabManager.activeTabID)

        // Destroy the primary terminal surface.
        if let surfaceID = tabSurfaceMap[tabID] {
            clearSurfaceTracking(for: surfaceID)
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
        processMonitor?.unregisterTab(tabID)

        // Remove from TabManager (activates next tab).
        tabManager.removeTab(id: tabID)

        if let newActiveID = tabManager.activeTabID {
            handleTabSwitch(to: newActiveID)
        }
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
            // Snapshot child PIDs before surface creation so we can
            // identify the new shell process spawned for this tab.
            let childrenBefore = snapshotChildPIDs()

            let surfaceID = try bridge.createSurface(
                in: surfaceView,
                workingDirectory: workingDirectory,
                command: nil
            )
            viewModel.markRunning(surfaceID: surfaceID)
            surfaceView.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
            surfaceView.syncSizeWithTerminal()
            tabSurfaceMap[tabID] = surfaceID

            // Register the tab with the process monitor for SSH detection.
            let childrenAfter = snapshotChildPIDs()
            if let shellPID = findNewShellPID(current: childrenAfter, previous: childrenBefore) {
                processMonitor?.registerTab(tabID, shellPID: shellPID)
            }
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
