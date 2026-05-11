// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+SessionManagement.swift - Session persistence and restoration.

import AppKit
import Combine

// MARK: - Session Management

/// Extension that handles session save/restore: capturing current state,
/// persisting to disk, and restoring tabs on launch.
extension AppDelegate {

    /// Returns true when the deferred launch restore pass has a persisted
    /// session with real tabs available to restore.
    ///
    /// The decoded snapshot is cached so the restore pass can show an opaque
    /// shell and rebuild from the same data without reading `last.json` again.
    func hasRestorableSessionOnLaunch() -> Bool {
        if let pendingRestorableLaunchSession,
           Self.sessionContainsRestorableTabs(pendingRestorableLaunchSession) {
            return true
        }

        let config = configService?.current ?? .defaults
        guard config.sessions.restoreOnLaunch, let sessionManager else {
            pendingRestorableLaunchSession = nil
            return false
        }

        let session: Session
        do {
            guard let loaded = try sessionManager.loadLastSession() else {
                pendingRestorableLaunchSession = nil
                return false
            }
            session = loaded
        } catch {
            pendingRestorableLaunchSession = nil
            NSLog("[AppDelegate] Failed to load session for restore: %@",
                  String(describing: error))
            return false
        }

        guard Self.sessionContainsRestorableTabs(session) else {
            pendingRestorableLaunchSession = nil
            return false
        }

        pendingRestorableLaunchSession = session
        return true
    }

    // MARK: - Session Manager Initialization

    /// Initializes the session manager for persistence and restoration.
    func initializeSessionManager() {
        sessionManager = SessionManagerImpl()
        quickTerminalViewModel = QuickTerminalViewModel()
    }

    /// Starts or stops periodic auto-save according to the current sessions config.
    ///
    /// The timer captures session state on the main actor and persists it as the
    /// unnamed `last.json` snapshot used for restore-on-launch.
    func startSessionAutoSaveIfNeeded(using config: CocxyConfig? = nil) {
        guard let sessionManager = sessionManager else { return }
        let resolvedConfig = config ?? configService?.current ?? .defaults

        guard resolvedConfig.sessions.autoSave else {
            sessionManager.stopAutoSave()
            return
        }

        sessionManager.startAutoSave(intervalSeconds: TimeInterval(resolvedConfig.sessions.autoSaveInterval)) { [weak self] in
            syncOnMainActor {
                self?.captureCurrentSession() ?? Self.emptySessionSnapshot()
            }
        }
    }

    /// Stops periodic auto-save if it is active.
    func stopSessionAutoSave() {
        sessionManager?.stopAutoSave()
    }

    /// Observes config hot-reloads and keeps the auto-save timer aligned with
    /// the latest `[sessions]` settings.
    func observeSessionAutoSaveConfigChanges() {
        sessionAutoSaveConfigCancellable?.cancel()
        guard let configService else { return }

        sessionAutoSaveConfigCancellable = configService.configChangedPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                self?.startSessionAutoSaveIfNeeded(using: newConfig)
            }
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
    /// Gathers window frames, tab lists, split trees for ALL windows.
    /// Used both for auto-save and for the final save before termination.
    func captureCurrentSession() -> Session {
        let allControllers = [windowController].compactMap { $0 } + additionalWindowControllers
        var windowStates: [WindowState] = []
        var focusedIndex = 0

        for (windowIndex, controller) in allControllers.enumerated() {
            let state = captureWindowState(controller)
            windowStates.append(state)

            // Track which window is the key window.
            if controller.window?.isKeyWindow == true {
                focusedIndex = windowIndex
            }
        }

        // If no controllers, produce a single empty window state.
        if windowStates.isEmpty {
            windowStates.append(WindowState(
                frame: CodableRect(x: 100, y: 100, width: 1200, height: 800),
                isFullScreen: false,
                tabs: [],
                activeTabIndex: 0
            ))
        }

        return Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: windowStates,
            focusedWindowIndex: focusedIndex
        )
    }

    /// Captures the state of a single window controller.
    private func captureWindowState(_ controller: MainWindowController) -> WindowState {
        let tabManager = controller.tabManager
        let splitCoordinator = controller.tabSplitCoordinator
        var tabStates: [TabState] = []
        var activeTabIndex = 0

        for (index, tab) in tabManager.tabs.enumerated() {
            if tab.isActive {
                activeTabIndex = index
            }

            let splitManager = splitCoordinator.splitManager(for: tab.id)
            let splitState = splitManager.rootNode.toSessionState(
                workingDirectoryResolver: { terminalID in
                    leafDirectoryMap(
                        for: tab.id,
                        in: controller,
                        rootNode: splitManager.rootNode,
                        fallbackDirectory: tab.workingDirectory
                    )[terminalID] ?? tab.workingDirectory
                }
            )
            let paneStates = capturePaneStates(
                for: tab.id,
                in: controller,
                rootNode: splitManager.rootNode,
                splitManager: splitManager
            )

            tabStates.append(TabState(
                id: tab.id,
                sessionID: controller.sessionIDForTab(tab.id),
                title: tab.title,
                customTitle: tab.customTitle,
                workspaceCustomTitle: tab.workspaceCustomTitle,
                workingDirectory: tab.workingDirectory,
                splitTree: splitState,
                // Preserve worktree metadata across app restarts so the
                // origin-repo fallback, badge, and cleanup plumbing
                // continue to function after restore.
                worktreeID: tab.worktreeID,
                worktreeRoot: tab.worktreeRoot,
                worktreeOriginRepo: tab.worktreeOriginRepo,
                worktreeBranch: tab.worktreeBranch,
                terminalEnginePreference: tab.terminalEnginePreference,
                paneStates: paneStates
            ))
        }

        let windowFrame: CodableRect
        if let window = controller.window {
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

        let isFullScreen = controller.window?.styleMask.contains(.fullScreen) ?? false
        let displayIndex = displayIndex(for: controller.window?.screen)

        return WindowState(
            frame: windowFrame,
            isFullScreen: isFullScreen,
            tabs: tabStates,
            activeTabIndex: activeTabIndex,
            windowID: controller.windowID,
            displayIndex: displayIndex
        )
    }

    // MARK: - Session Restore

    /// Restores the last saved session on launch, if configured.
    ///
    /// Preflights and consumes the cached last session, validates it via
    /// SessionRestorer, and recreates tabs with their working directories.
    /// For multi-window sessions, creates additional window controllers.
    func restoreSessionOnLaunch() {
        let config = configService?.current ?? .defaults
        guard let windowController = windowController else { return }
        guard config.sessions.restoreOnLaunch else {
            pendingRestorableLaunchSession = nil
            bootstrapInitialSurfaceIfNeeded(windowController)
            return
        }
        guard sessionManager != nil else {
            pendingRestorableLaunchSession = nil
            bootstrapInitialSurfaceIfNeeded(windowController)
            return
        }
        guard pendingCrashRecoverySnapshot == nil else {
            pendingRestorableLaunchSession = nil
            bootstrapInitialSurfaceIfNeeded(windowController)
            return
        }

        guard hasRestorableSessionOnLaunch(),
              let session = takePendingRestorableLaunchSession() else {
            bootstrapInitialSurfaceIfNeeded(windowController)
            return
        }

        let restorationPairs = session.windows.map { windowState in
            (
                windowState,
                SessionRestorer.restoreWindow(
                    from: windowState,
                    screenBounds: screenBounds(forDisplayIndex: windowState.displayIndex)
                )
            )
        }

        // Restore the primary window (index 0) — it already exists.
        if let primaryResult = restorationPairs.first?.1,
           !primaryResult.restoredTabs.isEmpty {
            prepareVisibleSessionRestoreShell(windowController, from: primaryResult)
            restoreTabsIntoController(windowController, from: primaryResult)
        } else {
            bootstrapInitialSurfaceIfNeeded(windowController)
        }

        // Restore additional windows (index 1+).
        for (_, result) in restorationPairs.dropFirst() {
            guard !result.restoredTabs.isEmpty else { continue }
            guard let controller = makeWindowController(registerInitialSession: false) else { continue }

            restoreTabsIntoController(controller, from: result)
            controller.showWindow(nil)

            additionalWindowControllers.append(controller)
        }

        // Focus the correct window.
        let allControllers = [windowController] + additionalWindowControllers
        let focusedIndex = min(max(session.focusedWindowIndex, 0), max(allControllers.count - 1, 0))
        if focusedIndex >= 0, focusedIndex < allControllers.count {
            allControllers[focusedIndex].window?.makeKeyAndOrderFront(nil)
        }
    }

    private func takePendingRestorableLaunchSession() -> Session? {
        defer { pendingRestorableLaunchSession = nil }
        return pendingRestorableLaunchSession
    }

    private static func sessionContainsRestorableTabs(_ session: Session) -> Bool {
        session.windows.contains { !$0.tabs.isEmpty }
    }

    private func prepareVisibleSessionRestoreShell(
        _ controller: MainWindowController,
        from result: RestorationResult
    ) {
        let frame = NSRect(
            x: result.windowFrame.x,
            y: result.windowFrame.y,
            width: result.windowFrame.width,
            height: result.windowFrame.height
        )
        controller.window?.setFrame(frame, display: false)
        controller.refreshTerminalContainerBackingBackground()
        controller.installSessionRestoreShield()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func bootstrapInitialSurfaceIfNeeded(_ controller: MainWindowController) {
        guard controller.tabSurfaceMap.isEmpty,
              controller.terminalViewModel.surfaceID == nil else {
            return
        }

        if let initialTab = controller.tabManager.tabs.first {
            registerSession(for: initialTab, in: controller)
        }

        controller.window?.center()
        controller.createTerminalSurface()
        controller.tabBarViewModel?.syncWithManager()
        controller.showWindow(nil)
        controller.focusActiveTerminalSurface()
    }

    // MARK: - Restore Helpers

    /// Returns the current main screen bounds as a `CodableRect`.
    private func currentScreenBounds() -> CodableRect {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            return CodableRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        }
        return CodableRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func screenBounds(forDisplayIndex displayIndex: Int?) -> CodableRect {
        if let displayIndex,
           displayIndex >= 0,
           displayIndex < NSScreen.screens.count {
            let frame = NSScreen.screens[displayIndex].visibleFrame
            return CodableRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        }
        return currentScreenBounds()
    }

    private static func emptySessionSnapshot() -> Session {
        Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 100, y: 100, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [],
                    activeTabIndex: 0
                ),
            ]
        )
    }

    /// Restores tabs from a `RestorationResult` into an existing controller.
    ///
    /// The controller must already have one tab (from `createMainWindow`).
    /// Additional restored tabs are created with surfaces and handlers.
    func restoreSession(_ session: Session, into controller: MainWindowController) -> Bool {
        guard let windowState = session.windows.first else { return false }

        let result = SessionRestorer.restoreWindow(
            from: windowState,
            screenBounds: screenBounds(forDisplayIndex: windowState.displayIndex)
        )
        guard !result.restoredTabs.isEmpty else { return false }

        restoreTabsIntoController(controller, from: result)
        return true
    }

    func restoreTabsIntoController(
        _ controller: MainWindowController,
        from result: RestorationResult
    ) {
        guard !result.restoredTabs.isEmpty else { return }
        guard bridge != nil else { return }
        controller.window?.disableScreenUpdatesUntilFlush()
        controller.installSessionRestoreShield()
        controller.isPerformingProgrammaticTabRestore = true
        defer { controller.isPerformingProgrammaticTabRestore = false }

        // Restore window frame.
        let frame = NSRect(
            x: result.windowFrame.x,
            y: result.windowFrame.y,
            width: result.windowFrame.width,
            height: result.windowFrame.height
        )
        controller.refreshTerminalContainerBackingBackground()
        controller.window?.setFrame(frame, display: false)

        resetControllerForRestore(controller)
        controller.deferredRestoredTabLoader = { [weak self, weak controller] tabID in
            guard let self,
                  let controller,
                  let restoredTab = controller.deferredRestoredTabs.removeValue(forKey: tabID) else {
                return
            }
            self.restoreSurfaces(for: restoredTab, in: controller)
        }

        let gitProvider = GitInfoProviderImpl()
        let projectConfigService = ProjectConfigService()
        let safeActiveIndex = min(max(result.activeTabIndex, 0), result.restoredTabs.count - 1)
        let activeTabID = result.restoredTabs[safeActiveIndex].tabID

        for restoredTab in result.restoredTabs {
            let isActiveRestoredTab = restoredTab.tabID == activeTabID
            let gitBranch = isActiveRestoredTab
                ? gitProvider.currentBranch(at: restoredTab.workingDirectory)
                : nil
            let restoredModel = Tab(
                id: restoredTab.tabID,
                title: restoredTab.title,
                workingDirectory: restoredTab.workingDirectory,
                gitBranch: gitBranch,
                customTitle: restoredTab.customTitle,
                workspaceCustomTitle: restoredTab.workspaceCustomTitle,
                // Carry worktree metadata forward from the saved session
                // so the tab keeps pointing at the same worktree on disk
                // after restore. The `worktreeRoot` anchor survives even
                // if the shell `cd`'s elsewhere later.
                worktreeID: restoredTab.worktreeID,
                worktreeRoot: restoredTab.worktreeRoot,
                worktreeOriginRepo: restoredTab.worktreeOriginRepo,
                worktreeBranch: restoredTab.worktreeBranch,
                terminalEnginePreference: restoredTab.terminalEnginePreference
            )
            controller.tabManager.insertExternalTab(restoredModel, activate: false)
            registerSession(
                for: restoredModel,
                in: controller,
                sessionID: restoredTab.sessionID,
                titleOverride: restoredTab.title
            )

            // Apply origin-repo fallback when the user opted in and the
            // tab actually has a worktree origin. For tabs without a
            // worktree the gate short-circuits to nil, preserving the
            // legacy single-walk behaviour.
            let inheritProjectConfig = configService?.current.worktree.inheritProjectConfig ?? true
            let originRepo = inheritProjectConfig ? restoredTab.worktreeOriginRepo : nil
            if isActiveRestoredTab {
                if let projectConfig = projectConfigService.loadConfig(
                    for: restoredTab.workingDirectory,
                    originRepo: originRepo
                ) {
                    controller.tabManager.updateTab(id: restoredTab.tabID) { tab in
                        tab.projectConfig = projectConfig
                    }
                }
            } else {
                controller.deferredRestoredTabMetadataIDs.insert(restoredTab.tabID)
            }

            if restoredTab.tabID == activeTabID {
                restoreSurfaces(
                    for: restoredTab,
                    in: controller
                )
            } else {
                restoreSplitMetadataOnly(
                    for: restoredTab,
                    in: controller
                )
                controller.deferredRestoredTabs[restoredTab.tabID] = restoredTab
            }
        }

        controller.tabManager.setActive(id: activeTabID)
        controller.handleTabSwitch(to: activeTabID)
        controller.refreshVisibleTerminalInteractionState()

        // Enter full screen if saved.
        if result.isFullScreen, controller.window?.styleMask.contains(.fullScreen) == false {
            controller.window?.toggleFullScreen(nil)
        }

        controller.tabBarViewModel?.syncWithManager()
        controller.focusActiveTerminalSurface()
        controller.activeTerminalSurfaceView?.requestImmediateRedraw()
        controller.scheduleSessionRestoreShieldRemoval()
        controller.scheduleDeferredRestoredTabMetadataHydration()
    }

    private func restoreSplitMetadataOnly(
        for restoredTab: RestoredTab,
        in controller: MainWindowController
    ) {
        let restoredSplitNode = controller.readableRestoredSplitNode(restoredTab.splitNode)
        let leafInfos = restoredSplitNode.allLeafIDs()
        guard !leafInfos.isEmpty else { return }

        var restoredPanelTypes: [UUID: PanelInfo] = [:]
        var restoredPanelTitles: [UUID: String] = [:]

        for (index, leafInfo) in leafInfos.enumerated() {
            let paneState = index < restoredTab.paneStates.count
                ? restoredTab.paneStates[index]
                : SplitPaneState()
            let panelInfo = paneState.panelInfo

            if panelInfo.type != .terminal {
                restoredPanelTypes[leafInfo.terminalID] = panelInfo
            }
            if let title = paneState.title, !title.isEmpty {
                restoredPanelTitles[leafInfo.terminalID] = title
            }
        }

        controller.tabSplitCoordinator.splitManager(for: restoredTab.tabID).restoreLayout(
            rootNode: restoredSplitNode,
            focusedLeafID: leafInfos.first?.leafID,
            panelTypes: restoredPanelTypes,
            panelTitles: restoredPanelTitles
        )
    }

    private func restoreSurfaces(
        for restoredTab: RestoredTab,
        in controller: MainWindowController
    ) {
        let restoredSplitNode = controller.readableRestoredSplitNode(restoredTab.splitNode)
        let leafInfos = restoredSplitNode.allLeafIDs()
        guard !leafInfos.isEmpty else { return }

        let leafDirectories = leafWorkingDirectories(in: restoredTab.splitTreeState)
        let engine = controller.makeTerminalEngine(for: restoredTab.terminalEnginePreference)
        let configuredFontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize

        var viewsByTerminalID: [UUID: NSView] = [:]
        var storedSplitSurfaces: [SurfaceID: TerminalHostView] = [:]
        var storedSplitViewModels: [SurfaceID: TerminalViewModel] = [:]
        var tabPanelContentViews: [UUID: NSView] = [:]
        var restoredPanelTypes: [UUID: PanelInfo] = [:]
        var restoredPanelTitles: [UUID: String] = [:]

        for (index, leafInfo) in leafInfos.enumerated() {
            let paneState = index < restoredTab.paneStates.count
                ? restoredTab.paneStates[index]
                : SplitPaneState()
            let panelInfo = paneState.panelInfo

            if panelInfo.type != .terminal {
                guard let panelView = controller.makeWorkspacePanelView(
                    panel: panelInfo,
                    contentID: leafInfo.terminalID,
                    tabID: restoredTab.tabID
                ) else {
                    continue
                }
                viewsByTerminalID[leafInfo.terminalID] = panelView
                tabPanelContentViews[leafInfo.terminalID] = panelView
                restoredPanelTypes[leafInfo.terminalID] = panelInfo
                if let title = paneState.title, !title.isEmpty {
                    restoredPanelTitles[leafInfo.terminalID] = title
                }
                continue
            }

            let workingDirectory = index < leafDirectories.count
                ? leafDirectories[index]
                : restoredTab.workingDirectory
            let isPrimaryLeaf = index == 0

            let viewModel: TerminalViewModel
            let surfaceView: TerminalHostView

            if isPrimaryLeaf,
               controller.tabViewModels.isEmpty,
               controller.splitViewModels.isEmpty {
                viewModel = controller.terminalViewModel
                viewModel.setDefaultFontSize(configuredFontSize)
                let freshPrimarySurfaceView = TerminalHostViewFactory.make(
                    viewModel: viewModel,
                    engine: engine,
                    localizer: appLocalizer()
                )
                controller.terminalSurfaceView = freshPrimarySurfaceView
                surfaceView = freshPrimarySurfaceView
            } else {
                let newViewModel = TerminalViewModel(engine: engine)
                newViewModel.setDefaultFontSize(configuredFontSize)
                viewModel = newViewModel
                surfaceView = TerminalHostViewFactory.make(
                    viewModel: newViewModel,
                    engine: engine,
                    localizer: appLocalizer()
                )
            }

            do {
                let surfaceID = try engine.createSurface(
                    in: surfaceView,
                    workingDirectory: workingDirectory,
                    command: nil
                )
                viewModel.markRunning(surfaceID: surfaceID)
                surfaceView.configureSurfaceIfNeeded(bridge: engine, surfaceID: surfaceID)
                surfaceView.syncSizeWithTerminal()
                controller.registerTerminalEngine(
                    engine,
                    tabID: restoredTab.tabID,
                    surfaceID: surfaceID
                )
                controller.wireSurfaceHandlers(
                    for: surfaceID,
                    tabID: restoredTab.tabID,
                    in: surfaceView,
                    initialWorkingDirectory: workingDirectory
                )
                controller.startAutomaticSessionReplayIfNeeded(
                    surfaceID: surfaceID,
                    tabID: restoredTab.tabID
                )

                if isPrimaryLeaf {
                    controller.tabSurfaceMap[restoredTab.tabID] = surfaceID
                    controller.tabSurfaceViews[restoredTab.tabID] = surfaceView
                    controller.tabViewModels[restoredTab.tabID] = viewModel
                    controller.attachRestoredCommandBlocksIfAvailable(
                        tabID: restoredTab.tabID,
                        surfaceID: surfaceID,
                        in: surfaceView
                    )
                } else {
                    storedSplitSurfaces[surfaceID] = surfaceView
                    storedSplitViewModels[surfaceID] = viewModel
                }

                if let scrollPosition = paneState.scrollPosition {
                    _ = controller.cocxyCoreBridge(forSurface: surfaceID)?
                        .setHistoryVisibleStart(scrollPosition.visibleStartRow, for: surfaceID)
                }
                viewsByTerminalID[leafInfo.terminalID] = surfaceView
            } catch {
                NSLog(
                    "[AppDelegate] Failed to restore surface for tab %@ pane %d: %@",
                    restoredTab.tabID.rawValue.uuidString,
                    index,
                    String(describing: error)
                )
            }
        }

        let splitManager = controller.tabSplitCoordinator.splitManager(for: restoredTab.tabID)
        splitManager.restoreLayout(
            rootNode: restoredSplitNode,
            focusedLeafID: leafInfos.first?.leafID,
            panelTypes: restoredPanelTypes,
            panelTitles: restoredPanelTitles
        )

        if !tabPanelContentViews.isEmpty {
            controller.savedTabPanelContentViews[restoredTab.tabID] = tabPanelContentViews
        }

        guard leafInfos.count > 1 else { return }

        if let splitView = controller.makeStoredSplitView(
            from: restoredSplitNode,
            viewsByTerminalID: viewsByTerminalID
        ) {
            controller.savedTabSplitViews[restoredTab.tabID] = splitView
        }
        if !storedSplitSurfaces.isEmpty {
            controller.savedTabSplitSurfaceViews[restoredTab.tabID] = storedSplitSurfaces
        }
        if !storedSplitViewModels.isEmpty {
            controller.savedTabSplitViewModels[restoredTab.tabID] = storedSplitViewModels
        }
    }

    private func resetControllerForRestore(_ controller: MainWindowController) {
        if let registry = sessionRegistry {
            let ownedSessionIDs = registry.sessions(in: controller.windowID).map(\.sessionID)
            for sessionID in ownedSessionIDs {
                registry.removeSession(sessionID)
            }
        }

        let existingTabIDs = controller.tabManager.tabs.map(\.id)
        for tabID in existingTabIDs {
            controller.processMonitor?.unregisterTab(tabID)
            controller.tabSplitCoordinator.removeSplitManager(for: tabID)
        }

        controller.refreshTerminalContainerBackingBackground()
        controller.destroyAllSurfaces()
        controller.refreshTerminalContainerBackingBackground()
        controller.deferredRestoredTabs.removeAll()
        controller.deferredRestoredTabLoader = nil
        controller.terminalContainerView?.subviews.forEach { subview in
            if subview !== controller.sessionRestoreShieldView {
                subview.removeFromSuperview()
            }
        }
        controller.tabSessionMap.removeAll()
        controller.tabSurfaceMap.removeAll()
        controller.tabSurfaceViews.removeAll()
        controller.tabViewModels.removeAll()
        controller.tabOutputBuffers.removeAll()
        controller.tabCommandTrackers.removeAll()
        controller.surfaceWorkingDirectories.removeAll()
        controller.deferredRestoredTabMetadataIDs.removeAll()
        controller.savedTabSplitViews.removeAll()
        controller.savedTabSplitSurfaceViews.removeAll()
        controller.savedTabSplitViewModels.removeAll()
        controller.savedTabPanelContentViews.removeAll()
        controller.splitSurfaceViews.removeAll()
        controller.splitViewModels.removeAll()
        controller.panelContentViews.removeAll()
        controller.activeSplitView = nil
        controller.displayedTabID = nil
        controller.terminalSurfaceView?.removeFromSuperview()
        controller.terminalSurfaceView = nil
        controller.refreshTerminalContainerBackingBackground()
        controller.terminalOutputBuffer = TerminalOutputBuffer()

        while let tabID = controller.tabManager.tabs.first?.id {
            _ = controller.tabManager.detachTab(id: tabID)
        }
    }

    private func leafWorkingDirectories(in state: SplitNodeState) -> [URL] {
        switch state {
        case .leaf(let workingDirectory, _):
            return [workingDirectory]
        case .split(_, let first, let second, _):
            return leafWorkingDirectories(in: first) + leafWorkingDirectories(in: second)
        }
    }

    private func capturePaneStates(
        for tabID: TabID,
        in controller: MainWindowController,
        rootNode: SplitNode,
        splitManager: SplitManager
    ) -> [SplitPaneState] {
        let surfaceMap = leafSurfaceMap(for: tabID, in: controller, rootNode: rootNode)

        return rootNode.allLeafIDs().map { leafInfo in
            let panelInfo = splitManager.panelInfo(for: leafInfo.terminalID)
            let scrollPosition: TerminalScrollPosition?
            if panelInfo.type == .terminal,
               let surfaceID = surfaceMap[leafInfo.terminalID],
               let visibleStart = controller.cocxyCoreBridge(forSurface: surfaceID)?
                .historyVisibleStart(for: surfaceID) {
                scrollPosition = TerminalScrollPosition(visibleStartRow: visibleStart)
            } else {
                scrollPosition = nil
            }

            return SplitPaneState(
                panelInfo: panelInfo,
                title: splitManager.panelTitle(for: leafInfo.terminalID),
                scrollPosition: scrollPosition
            )
        }
    }

    private func leafDirectoryMap(
        for tabID: TabID,
        in controller: MainWindowController,
        rootNode: SplitNode,
        fallbackDirectory: URL
    ) -> [UUID: URL] {
        let leafInfos = rootNode.allLeafIDs()
        guard !leafInfos.isEmpty else { return [:] }

        let isDisplayed = controller.displayedTabID == tabID
        let primaryView = controller.tabSurfaceViews[tabID]
        let primarySurfaceID = controller.tabSurfaceMap[tabID]
        let splitSurfaces = isDisplayed
            ? controller.splitSurfaceViews
            : (controller.savedTabSplitSurfaceViews[tabID] ?? [:])

        let orderedViews: [NSView]
        if isDisplayed {
            orderedViews = controller.collectLeafViews()
        } else if let savedSplitView = controller.savedTabSplitViews[tabID] {
            orderedViews = collectLeafViews(from: savedSplitView)
        } else if let primaryView {
            orderedViews = [primaryView]
        } else {
            orderedViews = []
        }

        var mapping: [UUID: URL] = [:]

        for (leafInfo, view) in zip(leafInfos, orderedViews) {
            let directory: URL
            if let terminalView = view as? TerminalHostView {
                let surfaceID: SurfaceID?
                if let primaryView, terminalView === primaryView {
                    surfaceID = primarySurfaceID
                } else {
                    surfaceID = splitSurfaces.first(where: { $0.value === terminalView })?.key
                }
                directory = surfaceID.flatMap { controller.surfaceWorkingDirectories[$0] }
                    ?? fallbackDirectory
            } else {
                directory = fallbackDirectory
            }
            mapping[leafInfo.terminalID] = directory
        }

        for leafInfo in leafInfos where mapping[leafInfo.terminalID] == nil {
            mapping[leafInfo.terminalID] = fallbackDirectory
        }

        return mapping
    }

    private func leafSurfaceMap(
        for tabID: TabID,
        in controller: MainWindowController,
        rootNode: SplitNode
    ) -> [UUID: SurfaceID] {
        let leafInfos = rootNode.allLeafIDs()
        guard !leafInfos.isEmpty else { return [:] }

        let isDisplayed = controller.displayedTabID == tabID
        let primaryView = controller.tabSurfaceViews[tabID]
        let primarySurfaceID = controller.tabSurfaceMap[tabID]
        let splitSurfaces = isDisplayed
            ? controller.splitSurfaceViews
            : (controller.savedTabSplitSurfaceViews[tabID] ?? [:])

        let orderedViews: [NSView]
        if isDisplayed {
            orderedViews = controller.collectLeafViews()
        } else if let savedSplitView = controller.savedTabSplitViews[tabID] {
            orderedViews = collectLeafViews(from: savedSplitView)
        } else if let primaryView {
            orderedViews = [primaryView]
        } else {
            orderedViews = []
        }

        var mapping: [UUID: SurfaceID] = [:]
        for (leafInfo, view) in zip(leafInfos, orderedViews) {
            guard let terminalView = view as? TerminalHostView else { continue }
            if let primaryView,
               terminalView === primaryView,
               let primarySurfaceID {
                mapping[leafInfo.terminalID] = primarySurfaceID
                continue
            }
            if let surfaceID = splitSurfaces.first(where: { $0.value === terminalView })?.key {
                mapping[leafInfo.terminalID] = surfaceID
            }
        }
        return mapping
    }

    private func collectLeafViews(from rootView: NSView) -> [NSView] {
        if let splitView = rootView as? NSSplitView {
            return splitView.subviews.flatMap { collectLeafViews(from: $0) }
        }
        return [rootView]
    }

    private func displayIndex(for screen: NSScreen?) -> Int? {
        guard let screen else { return nil }
        return NSScreen.screens.firstIndex(where: { $0 === screen })
    }
}
