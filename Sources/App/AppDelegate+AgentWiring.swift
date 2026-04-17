// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+AgentWiring.swift - Agent detection engine setup and event wiring.

import AppKit
import Combine

// MARK: - Agent Detection Wiring

/// Extension that initializes the agent detection engine and wires it
/// to tabs, dashboard, timeline, and hook events.
///
/// Extracted from AppDelegate to isolate the complex agent detection
/// subsystem wiring from app lifecycle management.
extension AppDelegate {

    // MARK: - Engine Initialization

    /// Initializes the agent detection engine and hook receiver.
    ///
    /// Creates the engine with compiled agent configurations and the hook
    /// event receiver. This method has NO window dependency and MUST be
    /// called BEFORE `createMainWindow()` so the engine is ready to
    /// receive terminal output from the very first surface.
    ///
    /// Window-dependent wiring is deferred to `wireAgentDetectionToWindow()`.
    func initializeAgentDetectionEngine() {
        let config = configService?.current ?? .defaults
        guard config.agentDetection.enabled else { return }

        // Load agent configs from the service and retain for hot-reload.
        let agentConfigService = AgentConfigService()
        try? agentConfigService.reload()
        self.agentConfigService = agentConfigService
        let compiledConfigs = agentConfigService.currentConfigs
        if let cocxyBridge = bridge as? CocxyCoreBridge {
            cocxyBridge.updateNativeAgentPatterns(from: compiledConfigs)
        }

        let engine = AgentDetectionEngineImpl(
            compiledConfigs: compiledConfigs,
            debounceInterval: 0.2
        )
        self.agentDetectionEngine = engine

        // Allocate the per-surface store alongside the engine so downstream
        // wiring (wireHookReceiverToEngine, wireAgentDetectionToTabs) can
        // dual-write agent state per split while `Tab` keeps mirroring the
        // same fields for the existing UI consumers.
        self.agentStatePerSurfaceStore = AgentStatePerSurfaceStore()

        // Inject per-agent idle timeout overrides from the compiled configs.
        // Agents like Aider and Gemini CLI are slower and need longer timeouts
        // to avoid false completion signals from the timing detector.
        for compiled in compiledConfigs {
            if let timeout = compiled.config.idleTimeoutOverride {
                engine.setAgentTimeout(
                    agentName: compiled.config.name,
                    timeout: timeout
                )
            }
        }

        hookEventReceiver = HookEventReceiverImpl()
        let sessionDiffTracker = SessionDiffTrackerImpl()
        self.sessionDiffTracker = sessionDiffTracker

        hookEventReceiver?.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak sessionDiffTracker] event in
                sessionDiffTracker?.handleHookEvent(event)
            }
            .store(in: &hookCancellables)

        // Start watching agents.toml for hot-reload. File changes are
        // debounced (500ms) and routed through the config service's
        // Combine publisher to update the pattern detector live.
        let watcher = AgentConfigWatcher(
            agentConfigService: agentConfigService,
            fileProvider: DiskAgentConfigFileProvider()
        )
        watcher.startWatching()
        self.agentConfigWatcher = watcher

        agentConfigService.configChangedPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak engine, weak self] newConfigs in
                engine?.updateAgentConfigs(newConfigs)
                if let cocxyBridge = self?.bridge as? CocxyCoreBridge {
                    cocxyBridge.updateNativeAgentPatterns(from: newConfigs)
                }
            }
            .store(in: &hookCancellables)
    }

    /// Wires the agent detection engine to the main window controller.
    ///
    /// Injects the engine into the window controller so all surfaces
    /// route output to the detection engine. Also wires hook events,
    /// tab state indicators, dashboard, and timeline.
    ///
    /// MUST be called AFTER `createMainWindow()` since it depends on
    /// the window controller and its tab manager.
    func wireAgentDetectionToWindow() {
        guard let engine = agentDetectionEngine,
              let windowController = windowController else { return }

        windowController.injectedAgentDetectionEngine = engine
        wireCocxyCoreBridgeIfNeeded()
        wireHookReceiverToEngine(engine)
        wireAgentDetectionToTabs(engine)
        wireAgentDashboardAndTimeline(engine)
        wireCocxyCoreSemanticTimelineIfNeeded()
    }

    // MARK: - Hook Event Wiring

    /// Connects the hook event receiver to the agent detection engine.
    ///
    /// Forwards events whose session/CWD resolve to a Cocxy tab across ANY window.
    /// The first successful resolution binds the Claude hook session ID to that
    /// tab so later events can route without repeatedly falling back to CWD scans.
    func wireHookReceiverToEngine(_ engine: AgentDetectionEngineImpl) {
        guard let receiver = hookEventReceiver else { return }

        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak engine, weak self] event in
                guard let self else {
                    engine?.processHookEvent(event)
                    return
                }

                let resolved = self.resolvedControllerAndTab(
                    forHookSessionID: event.sessionId,
                    cwd: event.cwd
                )

                // Drop hook events from sessions not running inside Cocxy tabs.
                if event.cwd != nil, resolved == nil {
                    return
                }

                // Update the tab's agentActivity and stats with tool details
                // for real-time visibility in the sidebar.
                if let resolved, case .toolUse(let toolData) = event.data {
                    let filePath = toolData.toolInput?["file_path"]
                        ?? toolData.toolInput?["path"]
                        ?? toolData.toolInput?["command"]?.prefix(40).description
                    let activity: String
                    if let file = filePath {
                        let fileName = URL(fileURLWithPath: file).lastPathComponent
                        activity = "\(toolData.toolName): \(fileName)"
                    } else {
                        activity = toolData.toolName
                    }
                    let isError = event.type == .postToolUseFailure
                    resolved.controller.tabManager.updateTab(id: resolved.tabID) { tab in
                        tab.agentActivity = activity
                        tab.agentToolCount += 1
                        tab.lastActivityAt = Date()
                        if isError {
                            tab.agentErrorCount += 1
                        }
                    }
                    // Dual-write: mirror the same mutation onto the per-surface
                    // store so UI consumers that read per-split state stay in
                    // sync while the tab-level fields remain the source of
                    // truth during the v0.1.71 migration.
                    if let targetSurfaceID = self.surfaceIDForDualWrite(
                        controller: resolved.controller,
                        tabID: resolved.tabID,
                        cwdHint: event.cwd
                    ) {
                        self.agentStatePerSurfaceStore?.update(
                            surfaceID: targetSurfaceID
                        ) { state in
                            state.agentActivity = activity
                            state.agentToolCount += 1
                            if isError {
                                state.agentErrorCount += 1
                            }
                        }
                    }
                    // Refresh progress overlay and sidebar with new tool counts.
                    resolved.controller.updateAgentProgressOverlay()
                    resolved.controller.tabBarViewModel?.syncWithManager()
                    resolved.controller.refreshStatusBar()
                }

                // CwdChanged is consumed by the dedicated tab-sync handler.
                // It runs alongside the engine dispatch (which treats it as
                // informational and returns nil) so tab.workingDirectory
                // stays in sync without needing a separate subscription.
                if event.type == .cwdChanged {
                    self.handleCwdChangedHook(event)
                }

                engine?.processHookEvent(event)

                if event.type == .sessionEnd {
                    self.unbindHookSession(event.sessionId)
                }
            }
            .store(in: &hookCancellables)
    }

    // MARK: - Agent Detection -> Tab State

    /// Subscribes to hook events and maps them to the correct tab using
    /// the event's `sessionId` and working directory.
    ///
    /// Each Claude Code session runs in a specific directory. When a hook
    /// event arrives, we find the tab whose `workingDirectory` matches the
    /// session's `cwd`. This prevents cross-tab pollution: if Claude runs
    /// in tab 1 but the user is viewing tab 2, only tab 1's indicator changes.
    func wireAgentDetectionToTabs(_ engine: AgentDetectionEngineImpl) {
        engine.stateChanged
            .sink { [weak self] context in
                guard let self else { return }
                let agentState = context.state.toTabAgentState

                let target: (controller: MainWindowController, tabID: TabID)?
                if let hookSessionId = context.hookSessionId {
                    target = self.resolvedControllerAndTab(
                        forHookSessionID: hookSessionId,
                        cwd: context.hookCwd
                    )
                } else {
                    // No hook context — this is a pattern-based detection.
                    // Only apply to the active tab (pattern detection reads
                    // the focused surface's output).
                    guard let controller = self.focusedWindowController(),
                          let activeTabID = controller.visibleTabID ?? controller.tabManager.activeTabID else {
                        return
                    }
                    target = (controller, activeTabID)
                }

                guard let target else { return }

                let controller = target.controller
                let tabID = target.tabID
                let displayName = self.resolvedAgentDisplayName(context.agentName)
                controller.tabManager.updateTab(id: tabID) { tab in
                    tab.agentState = agentState
                    tab.lastActivityAt = Date()

                    if agentState == .idle {
                        tab.agentToolCount = 0
                        tab.agentErrorCount = 0
                        tab.agentActivity = nil
                        tab.detectedAgent = nil
                    } else if let agentName = context.agentName?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !agentName.isEmpty {
                        if let existing = tab.detectedAgent,
                           existing.name == agentName {
                            // Preserve the original start time while the same
                            // agent continues across multiple state changes.
                            tab.detectedAgent = existing
                        } else {
                            tab.detectedAgent = DetectedAgent(
                                name: agentName,
                                displayName: displayName,
                                launchCommand: agentName,
                                startedAt: Date()
                            )
                        }
                    }

                    // Reset tool/error counters when agent finishes or goes idle.
                    if agentState == .finished, tab.agentActivity == nil {
                        tab.agentActivity = "Task completed"
                    } else if agentState == .error, tab.agentActivity == nil {
                        tab.agentActivity = "Error occurred"
                    } else if agentState == .waitingInput, tab.agentActivity == nil {
                        tab.agentActivity = "Waiting for input"
                    }
                }

                // Dual-write the same transition onto the per-surface store
                // so per-split UI consumers stay in sync during the v0.1.71
                // migration. Resolution priority: explicit context surfaceID
                // (pattern/timing detectors already supply it) -> bridge CWD
                // match -> tab primary surface. Tab-level fields above remain
                // the source of truth; the store shadows them until Fase 4.
                if let targetSurfaceID = self.surfaceIDForDualWrite(
                    controller: controller,
                    tabID: tabID,
                    preferred: context.surfaceID,
                    cwdHint: context.hookCwd
                ) {
                    self.agentStatePerSurfaceStore?.update(
                        surfaceID: targetSurfaceID
                    ) { state in
                        state.agentState = agentState

                        if agentState == .idle {
                            state.agentToolCount = 0
                            state.agentErrorCount = 0
                            state.agentActivity = nil
                            state.detectedAgent = nil
                        } else if let agentName = context.agentName?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                            !agentName.isEmpty {
                            if let existing = state.detectedAgent,
                               existing.name == agentName {
                                state.detectedAgent = existing
                            } else {
                                state.detectedAgent = DetectedAgent(
                                    name: agentName,
                                    displayName: displayName,
                                    launchCommand: agentName,
                                    startedAt: Date()
                                )
                            }
                        }

                        if agentState == .finished, state.agentActivity == nil {
                            state.agentActivity = "Task completed"
                        } else if agentState == .error, state.agentActivity == nil {
                            state.agentActivity = "Error occurred"
                        } else if agentState == .waitingInput, state.agentActivity == nil {
                            state.agentActivity = "Waiting for input"
                        }
                    }
                }

                // Propagate agent state to the session registry so the
                // AgentStateAggregator can provide cross-window visibility.
                let sessionID = controller.sessionIDForTab(tabID)
                controller.sessionRegistry?.updateAgentState(
                    sessionID,
                    state: agentState,
                    agentName: displayName
                )

                controller.tabBarViewModel?.syncWithManager()
                controller.refreshStatusBar()
                controller.updateAgentProgressOverlay()

                controller.updateNotificationRing(
                    for: tabID,
                    agentState: agentState
                )
            }
            .store(in: &hookCancellables)
    }

    // MARK: - Dashboard + Timeline Wiring

    /// Creates the dashboard ViewModel wired to hook receiver and detection engine,
    /// and the timeline store wired to hook events.
    func wireAgentDashboardAndTimeline(_ engine: AgentDetectionEngineImpl) {
        // Dashboard: subscribes to both hook events and detection engine signals.
        let dashboardVM = AgentDashboardViewModel(
            hookEventReceiver: hookEventReceiver,
            detectionEngine: engine
        )
        self.agentDashboardViewModel = dashboardVM

        // Provide tab CWDs from ALL windows so the dashboard can filter
        // out hook events from Claude sessions running outside Cocxy.
        dashboardVM.tabCwdProvider = { [weak self] in
            guard let self else { return [] }
            var cwds: [String] = []
            for controller in self.allWindowControllers {
                cwds.append(contentsOf: controller.tabManager.tabs.map { $0.workingDirectory.path })
                cwds.append(contentsOf: controller.surfaceWorkingDirectories.values.map(\.path))
            }
            return cwds
        }

        // Resolve CWD → tab ID searching ALL windows for accurate
        // cross-window dashboard navigation.
        dashboardVM.tabIdForCwdProvider = { [weak self] cwd in
            self?.tabIDForWorkingDirectory(cwd)?.rawValue
        }

        dashboardVM.tabIdResolver = { [weak self] sessionID, cwd in
            self?.resolvedControllerAndTab(
                forHookSessionID: sessionID,
                cwd: cwd
            )?.tabID.rawValue
        }

        dashboardVM.windowIDForTabProvider = { [weak self] tabUUID in
            self?.windowIDForTab(tabUUID)
        }

        dashboardVM.windowLabelProvider = { [weak self] windowID in
            self?.windowDisplayName(for: windowID)
        }

        dashboardVM.activePatternContextProvider = { [weak self] in
            guard let self,
                  let controller = self.focusedWindowController(),
                  let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID else {
                return nil
            }

            let surfaceDirectory = controller.activeTerminalSurfaceView?
                .terminalViewModel?
                .surfaceID
                .flatMap { controller.workingDirectory(for: $0)?.path }
            let tabDirectory = controller.tabManager.tab(for: tabID)?.workingDirectory.path

            return (tabId: tabID.rawValue, workingDirectory: surfaceDirectory ?? tabDirectory)
        }

        // Inject the dashboard VM into all windows so multi-window
        // panels render the same shared state.
        for controller in allWindowControllers {
            controller.injectedDashboardViewModel = dashboardVM
        }

        if windowTabRouter == nil {
            windowTabRouter = WindowControllerTabRouter(appDelegate: self)
        }

        // Wire tab navigation so "Go to Tab" in the dashboard works
        // across all windows, not just the main one.
        dashboardVM.tabNavigator = windowTabRouter

        // Wire cross-window navigation via the event bus so clicking
        // a session from another window still works if the shared router
        // is unavailable for any reason.
        dashboardVM.onCrossWindowNavigate = { [weak self] tabUUID in
            guard let self, self.windowTabRouter == nil, let registry = self.sessionRegistry,
                  let bus = self.windowEventBus else { return }
            let tabID = TabID(rawValue: tabUUID)
            // Look up the session by scanning the registry for this tab.
            let allSessions = registry.allSessions
            guard let entry = allSessions.first(where: { $0.tabID == tabID }) else { return }
            bus.broadcast(.focusSession(sessionID: entry.sessionID))
        }

        // Timeline: subscribes to hook events.
        let timelineStore = AgentTimelineStoreImpl()
        self.agentTimelineStore = timelineStore

        // Inject the timeline store into all windows so timeline panels
        // share a single event stream across the app.
        for controller in allWindowControllers {
            controller.injectedTimelineStore = timelineStore
        }

        guard let receiver = hookEventReceiver else { return }

        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak timelineStore] hookEvent in
                guard let self, let store = timelineStore else { return }
                let resolved = self.resolvedControllerAndTab(
                    forHookSessionID: hookEvent.sessionId,
                    cwd: hookEvent.cwd
                )

                // Only log events from sessions running inside Cocxy tabs.
                if hookEvent.cwd != nil, resolved == nil {
                    return
                }

                let eventWindowID = resolved?.controller.windowID
                let timelineEvent = TimelineEvent.from(
                    hookEvent: hookEvent,
                    windowID: eventWindowID,
                    windowLabel: self.windowDisplayName(for: eventWindowID)
                )
                store.addEvent(timelineEvent)
            }
            .store(in: &hookCancellables)

        // Auto-split subagent panels: when SubagentStart arrives, spawn a
        // live activity panel in the correct tab. When SubagentStop arrives,
        // auto-close the panel after a brief delay.
        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak dashboardVM] hookEvent in
                guard let self else { return }

                if hookEvent.type == .subagentStart,
                   case .subagent(let data) = hookEvent.data {
                    let subagentId = data.subagentId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !subagentId.isEmpty else { return }

                    Task { @MainActor [weak self, weak dashboardVM] in
                        guard let self,
                              let dashboardVM,
                              dashboardVM.hasSubagent(id: subagentId, in: hookEvent.sessionId),
                              let resolved = self.resolvedControllerAndTab(
                                  forHookSessionID: hookEvent.sessionId,
                                  cwd: hookEvent.cwd
                              ) else {
                            return
                        }

                        resolved.controller.spawnSubagentPanel(
                            subagentId: subagentId,
                            sessionId: hookEvent.sessionId,
                            agentType: data.subagentType,
                            targetTabId: resolved.tabID.rawValue
                        )
                    }
                } else if hookEvent.type == .subagentStop,
                          case .subagent(let data) = hookEvent.data {
                    let subId = data.subagentId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !subId.isEmpty,
                          let resolved = self.resolvedControllerAndTab(
                              forHookSessionID: hookEvent.sessionId,
                              cwd: hookEvent.cwd
                          ) else {
                        return
                    }
                    let sessId = hookEvent.sessionId
                    let targetController = resolved.controller
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        targetController.closeSubagentPanelBySubagentId(subId, sessionId: sessId)
                    }
                }
            }
            .store(in: &hookCancellables)
    }

    // MARK: - CocxyCore Semantic Wiring

    /// Wires CocxyCore's semantic adapter into the existing hook-based graph.
    ///
    /// Hook events feed the detection engine and dashboard, while timeline
    /// events enrich the timeline store with CocxyCore-native semantic data.
    private func wireCocxyCoreBridgeIfNeeded() {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let receiver = hookEventReceiver else { return }

        cocxyBridge.setCwdProvider { [weak self] surfaceID in
            self?.workingDirectoryForSurface(surfaceID)
        }

        cocxyBridge.semanticAdapter.windowMetadataProvider = { [weak self] surfaceID, cwd in
            guard let self else { return (nil, nil) }
            if let controller = self.controllerContainingSurface(surfaceID) {
                return (controller.windowID, self.windowDisplayName(for: controller.windowID))
            }
            if let cwd,
               let controller = self.controllerContainingWorkingDirectory(cwd) {
                return (controller.windowID, self.windowDisplayName(for: controller.windowID))
            }
            return (nil, nil)
        }

        cocxyBridge.semanticAdapter.sessionIdentifierProvider = { [weak self] surfaceID, cwd in
            guard let self else { return nil }

            if let controller = self.controllerContainingSurface(surfaceID),
               let tabID = controller.tabID(for: surfaceID) {
                return controller.sessionIDForTab(tabID).rawValue.uuidString
            }

            if let cwd,
               let resolved = self.resolvedControllerAndTab(forHookSessionID: nil, cwd: cwd) {
                return resolved.controller.sessionIDForTab(resolved.tabID).rawValue.uuidString
            }

            return nil
        }

        cocxyBridge.semanticAdapter.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak receiver] event in
                receiver?.receive(event)
            }
            .store(in: &hookCancellables)
    }

    private func wireCocxyCoreSemanticTimelineIfNeeded() {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let timelineStore = agentTimelineStore else { return }

        cocxyBridge.semanticAdapter.timelinePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak timelineStore] event in
                timelineStore?.addEvent(event)
            }
            .store(in: &hookCancellables)
    }

    private func workingDirectoryForSurface(_ surfaceID: SurfaceID) -> String? {
        if let url = windowController?.workingDirectory(for: surfaceID) {
            return url.path
        }

        for controller in additionalWindowControllers {
            if let url = controller.workingDirectory(for: surfaceID) {
                return url.path
            }
        }

        return nil
    }

    func makeTimelineNavigator() -> TimelineNavigating {
        TimelineNavigatorImpl(
            navigateHandler: { [weak self] event in
                self?.navigateTimelineEvent(event)
            },
            highlightHandler: { [weak self] filePath in
                self?.highlightTimelineFile(filePath)
            }
        )
    }

    private func navigateTimelineEvent(_ event: TimelineEvent) {
        guard let target = resolvedControllerAndTab(for: event) else { return }

        if focusedWindowController() === target.controller {
            _ = target.controller.focusTab(id: target.tabID)
        } else if let router = windowTabRouter {
            router.activateTab(id: target.tabID)
        } else if target.controller.focusTab(id: target.tabID) {
            NSApp.activate(ignoringOtherApps: true)
            target.controller.showWindow(nil)
            target.controller.window?.makeKeyAndOrderFront(nil)
        }

        scrollTimelineEvent(event, in: target.controller, tabID: target.tabID)
    }

    private func resolvedControllerAndTab(
        for event: TimelineEvent
    ) -> (controller: MainWindowController, tabID: TabID)? {
        if let boundTabID = hookSessionTabBindings[event.sessionId],
           let controller = controllerContainingTab(boundTabID) {
            return (controller, boundTabID)
        }

        if let uuid = UUID(uuidString: event.sessionId),
           let entry = sessionRegistry?.session(for: SessionID(rawValue: uuid)),
           let controller = controllerContainingTab(entry.tabID) {
            return (controller, entry.tabID)
        }

        if let windowID = event.windowID,
           let controller = allWindowControllers.first(where: { $0.windowID == windowID }) {
            if let sessions = sessionRegistry?.sessions(in: windowID),
               sessions.count == 1,
               let matchingEntry = sessions.first,
               let owner = controllerContainingTab(matchingEntry.tabID) {
                return (owner, matchingEntry.tabID)
            }

            if let activeTabID = controller.displayedTabID ?? controller.tabManager.activeTabID {
                return (controller, activeTabID)
            }
        }

        return nil
    }

    private func scrollTimelineEvent(
        _ event: TimelineEvent,
        in controller: MainWindowController,
        tabID: TabID
    ) {
        guard let cocxyBridge = controller.bridge as? CocxyCoreBridge else { return }
        let candidateSurfaceIDs = controller.surfaceIDs(for: tabID)
        guard !candidateSurfaceIDs.isEmpty else { return }

        guard let match = bestHistoryMatch(
            for: event,
            surfaceIDs: candidateSurfaceIDs,
            bridge: cocxyBridge
        ) else { return }

        cocxyBridge.scrollToSearchResult(
            surfaceID: match.surfaceID,
            lineNumber: match.lineNumber
        )
    }

    private func bestHistoryMatch(
        for event: TimelineEvent,
        surfaceIDs: [SurfaceID],
        bridge: CocxyCoreBridge
    ) -> (surfaceID: SurfaceID, lineNumber: Int)? {
        let terms = timelineSearchTerms(for: event)
        guard !terms.isEmpty else { return nil }

        var bestMatch: (surfaceID: SurfaceID, lineNumber: Int, score: Int)?

        for surfaceID in surfaceIDs {
            let lines = bridge.historyLines(for: surfaceID)
            for (lineNumber, line) in lines.enumerated() {
                let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalizedLine.isEmpty else { continue }

                let score = matchScore(for: normalizedLine, terms: terms)
                guard score > 0 else { continue }

                if let current = bestMatch {
                    if score > current.score || (score == current.score && lineNumber > current.lineNumber) {
                        bestMatch = (surfaceID, lineNumber, score)
                    }
                } else {
                    bestMatch = (surfaceID, lineNumber, score)
                }
            }
        }

        return bestMatch.map { ($0.surfaceID, $0.lineNumber) }
    }

    private func timelineSearchTerms(for event: TimelineEvent) -> [String] {
        var terms: [String] = []

        func append(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.lowercased()
            if !terms.contains(normalized) {
                terms.append(normalized)
            }
        }

        append(event.filePath)
        append(event.filePath.map { URL(fileURLWithPath: $0).lastPathComponent })
        append(event.summary)
        append(event.toolName)
        return terms
    }

    private func matchScore(for line: String, terms: [String]) -> Int {
        for (index, term) in terms.enumerated() where line.contains(term) {
            return terms.count - index
        }
        return 0
    }

    private func highlightTimelineFile(_ filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Notification Wiring

    /// Connects the agent detection engine's state changes to the notification manager.
    ///
    /// When an agent transitions to `waitingInput`, `finished`, or `error`, the
    /// notification manager creates an in-app notification and optionally a macOS
    /// push notification. This method bridges the two subsystems.
    ///
    /// MUST be called AFTER both `initializeAgentDetectionEngine()` and
    /// `initializeNotificationStack()` since it depends on both.
    func wireAgentDetectionToNotifications() {
        guard let engine = agentDetectionEngine,
              let notificationManager = notificationManager else { return }

        var previousStateByTab: [TabID: AgentState] = [:]

        engine.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notificationManager] context in
                guard let self, let manager = notificationManager else { return }

                let agentState = context.state.toTabAgentState

                let target: (controller: MainWindowController, tabID: TabID)?
                if let hookSessionId = context.hookSessionId {
                    target = self.resolvedControllerAndTab(
                        forHookSessionID: hookSessionId,
                        cwd: context.hookCwd
                    )
                } else {
                    guard let controller = self.focusedWindowController(),
                          let activeTabID = controller.visibleTabID ?? controller.tabManager.activeTabID else {
                        return
                    }
                    target = (controller, activeTabID)
                }

                guard let target,
                      let tab = target.controller.tabManager.tab(for: target.tabID) else { return }

                let previousState = previousStateByTab[target.tabID] ?? .idle
                previousStateByTab[target.tabID] = agentState

                // Only notify on meaningful transitions (skip idle→idle, etc.).
                guard agentState != previousState else { return }

                manager.handleStateChange(
                    state: agentState,
                    previousState: previousState,
                    for: target.tabID,
                    tabTitle: tab.title,
                    agentName: self.resolvedAgentDisplayName(context.agentName)
                )
            }
            .store(in: &hookCancellables)
    }

    func resolvedAgentDisplayName(_ rawName: String?) -> String? {
        guard let rawName else { return nil }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return agentConfigService?.displayName(forAgentIdentifier: trimmed) ?? trimmed
    }

    // MARK: - Per-Surface Store Routing

    /// Resolves the surface whose per-surface store entry should mirror
    /// a tab-level agent mutation during the v0.1.71 dual-write phase.
    ///
    /// Priority order:
    /// 1. An explicit `preferred` surface — used when the caller already
    ///    has a `StateContext.surfaceID` (pattern detector populates it
    ///    from the originating split, hook resolution does so after 2i).
    /// 2. CWD-based resolution through the bridge's
    ///    `resolveSurfaceID(matchingCwd:)` — used for hook events whose
    ///    `cwd` identifies the surface even when the engine context is
    ///    `nil` (legacy wiring path).
    /// 3. Tab-level fallback — the first surface registered on the tab.
    ///    This mirrors the pre-refactor semantic where a tab had exactly
    ///    one surface and keeps sidebar behavior intact for tabs without
    ///    splits.
    ///
    /// Returns `nil` only when the controller has no surfaces for the
    /// tab (unreachable in normal operation since a live tab always owns
    /// at least one surface). Callers still guard for `nil` to avoid
    /// touching the store when the tab has been torn down mid-flight.
    ///
    /// - Parameters:
    ///   - controller: The controller owning the tab being mutated.
    ///   - tabID: Tab whose primary surface is used as the final fallback.
    ///   - preferred: Explicit surfaceID supplied by the caller.
    ///   - cwdHint: CWD reported by the external event, when available.
    /// - Returns: The target surface, or `nil` if the tab has no surfaces.
    func surfaceIDForDualWrite(
        controller: MainWindowController,
        tabID: TabID,
        preferred: SurfaceID? = nil,
        cwdHint: String? = nil
    ) -> SurfaceID? {
        if let preferred {
            return preferred
        }
        if let cwdHint,
           !cwdHint.isEmpty,
           let cocxyBridge = bridge as? CocxyCoreBridge,
           let resolved = cocxyBridge.resolveSurfaceID(matchingCwd: cwdHint) {
            return resolved
        }
        return controller.surfaceIDs(for: tabID).first
    }

    // MARK: - Tab CWD Matching

    /// Finds the tab whose working directory exactly matches the given CWD.
    ///
    /// Uses **strict exact matching only**. The previous parent-directory
    /// heuristic was removed because it caused cross-terminal contamination:
    /// an agent session in another terminal at `~/project` would match
    /// a Cocxy tab whose CWD was `~/` (the home directory), polluting that
    /// tab's agent state with events from an unrelated terminal.
    ///
    /// With shell integration (ZDOTDIR) properly configured, tabs always
    /// have an up-to-date working directory via OSC 7, making exact matching
    /// both correct and sufficient.
    ///
    /// Returns `nil` when no tab's CWD matches the event. Callers handle
    /// the nil case: hook events are silently dropped (correct — the session
    /// belongs to another terminal), pattern-based events fall back to the
    /// active tab (correct — patterns are read from our own surfaces).
    ///
    /// - Parameters:
    ///   - cwd: The working directory reported by the hook event.
    ///   - tabs: All tabs in the window.
    ///   - activeTabID: Unused (kept for source compatibility). Callers that
    ///     need active-tab fallback handle it externally.
    /// - Returns: The tab with an exactly matching CWD, or `nil`.
    static func findMatchingTab(
        cwd: String,
        tabs: [Tab],
        activeTabID: TabID?
    ) -> Tab? {
        let cwdPath = URL(fileURLWithPath: cwd).standardized.path

        return tabs.first(where: {
            $0.workingDirectory.standardized.path == cwdPath
        })
    }
}
