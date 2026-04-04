// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+SessionManagement.swift - Session persistence and restoration.

import AppKit

// MARK: - Session Management

/// Extension that handles session save/restore: capturing current state,
/// persisting to disk, and restoring tabs on launch.
extension AppDelegate {

    // MARK: - Session Manager Initialization

    /// Initializes the session manager for persistence and restoration.
    func initializeSessionManager() {
        sessionManager = SessionManagerImpl()
        quickTerminalViewModel = QuickTerminalViewModel()
    }

    // MARK: - Session Save

    /// Saves the current session synchronously before app termination.
    ///
    /// This is a best-effort operation. If saving fails, the app terminates
    /// anyway -- losing the session is preferable to preventing shutdown.
    func saveSessionBeforeTermination() {
        guard let sessionManager = sessionManager else { return }

        let config = configService?.current ?? .defaults
        guard config.sessions.autoSave else { return }

        // Capture the current state.
        let session = captureCurrentSession()

        do {
            try sessionManager.saveSession(session, named: nil)
        } catch {
            NSLog("[AppDelegate] Failed to save session on termination: %@",
                  String(describing: error))
        }
    }

    /// Captures the current application state as a `Session`.
    ///
    /// Gathers window frame, tab list, split trees and quick terminal state.
    /// Used both for auto-save and for the final save before termination.
    func captureCurrentSession() -> Session {
        // Build tab states from the window controller if available.
        var tabStates: [TabState] = []
        var activeTabIndex = 0

        if let windowController = windowController {
            let tabManager = windowController.tabManager
            let splitCoordinator = windowController.tabSplitCoordinator

            for (index, tab) in tabManager.tabs.enumerated() {
                if tab.isActive {
                    activeTabIndex = index
                }

                let splitManager = splitCoordinator.splitManager(for: tab.id)
                let splitState = splitManager.rootNode.toSessionState(
                    workingDirectoryResolver: { _ in tab.workingDirectory }
                )

                tabStates.append(TabState(
                    id: tab.id,
                    title: tab.title,
                    workingDirectory: tab.workingDirectory,
                    splitTree: splitState
                ))
            }
        }

        // Build window frame from the current window position.
        let windowFrame: CodableRect
        if let window = windowController?.window {
            let frame = window.frame
            windowFrame = CodableRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        } else {
            windowFrame = CodableRect(x: 100, y: 100, width: 1200, height: 800)
        }

        let isFullScreen = windowController?.window?.styleMask.contains(.fullScreen) ?? false

        let windowState = WindowState(
            frame: windowFrame,
            isFullScreen: isFullScreen,
            tabs: tabStates,
            activeTabIndex: activeTabIndex
        )

        return Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [windowState]
        )
    }

    // MARK: - Session Restore

    /// Restores the last saved session on launch, if configured.
    ///
    /// Loads the last session from SessionManager, validates it via
    /// SessionRestorer, and recreates tabs with their working directories.
    func restoreSessionOnLaunch() {
        let config = configService?.current ?? .defaults
        guard config.sessions.restoreOnLaunch else { return }
        guard let sessionManager = sessionManager else { return }
        guard let windowController = windowController else { return }

        guard let session = try? sessionManager.loadLastSession() else { return }

        let screenBounds: CodableRect
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            screenBounds = CodableRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        } else {
            screenBounds = CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        }

        let result = SessionRestorer.restore(
            from: session,
            into: windowController.tabManager,
            splitCoordinator: windowController.tabSplitCoordinator,
            screenBounds: screenBounds
        )

        // Restore window frame.
        let frame = NSRect(
            x: result.windowFrame.x,
            y: result.windowFrame.y,
            width: result.windowFrame.width,
            height: result.windowFrame.height
        )
        windowController.window?.setFrame(frame, display: true)

        // Restore additional tabs (the first tab already exists from createMainWindow).
        // Skip the first restored tab since it maps to the existing initial tab.
        for (index, restoredTab) in result.restoredTabs.dropFirst().enumerated() {
            let newTab = windowController.tabManager.addTab(
                workingDirectory: restoredTab.workingDirectory
            )
            windowController.tabManager.updateTab(id: newTab.id) { tab in
                tab.title = restoredTab.title
            }

            // Create ViewModel, SurfaceView, and wire handlers for restored tab.
            if let bridge = bridge {
                let viewModel = TerminalViewModel(engine: bridge)
                let configuredFontSize = configService?.current.appearance.fontSize
                    ?? AppearanceConfig.defaults.fontSize
                viewModel.setDefaultFontSize(configuredFontSize)
                let surfaceView = TerminalHostViewFactory.makeView(
                    engine: bridge,
                    viewModel: viewModel
                )
                windowController.tabViewModels[newTab.id] = viewModel
                windowController.tabSurfaceViews[newTab.id] = surfaceView

                do {
                    let surfaceID = try bridge.createSurface(
                        in: surfaceView,
                        workingDirectory: restoredTab.workingDirectory,
                        command: nil
                    )
                    viewModel.markRunning(surfaceID: surfaceID)
                    surfaceView.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
                    surfaceView.syncSizeWithTerminal()
                    windowController.tabSurfaceMap[newTab.id] = surfaceID

                    // Wire OSC + output handlers via the public API.
                    windowController.wireHandlersForRestoredTab(
                        tabID: newTab.id,
                        surfaceID: surfaceID
                    )
                } catch {
                    NSLog("[AppDelegate] Failed to create surface for restored tab %d: %@",
                          index + 1, String(describing: error))
                }
            }
        }

        // Update the first tab's title if we have restored tabs.
        if let firstRestoredTab = result.restoredTabs.first,
           let firstTabID = windowController.tabManager.tabs.first?.id {
            windowController.tabManager.updateTab(id: firstTabID) { tab in
                tab.title = firstRestoredTab.title
            }
        }

        // Activate the correct tab.
        if result.activeTabIndex < windowController.tabManager.tabs.count {
            let targetTab = windowController.tabManager.tabs[result.activeTabIndex]
            windowController.tabManager.setActive(id: targetTab.id)
        }

        // Enter full screen if the session was full screen.
        if result.isFullScreen {
            windowController.window?.toggleFullScreen(nil)
        }

        windowController.tabBarViewModel?.syncWithManager()
    }
}
