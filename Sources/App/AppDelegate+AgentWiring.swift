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

        let engine = AgentDetectionEngineImpl(
            compiledConfigs: compiledConfigs,
            debounceInterval: 0.2
        )
        self.agentDetectionEngine = engine

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
            .sink { [weak engine] newConfigs in
                engine?.updateAgentConfigs(newConfigs)
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
        wireHookReceiverToEngine(engine)
        wireAgentDetectionToTabs(engine)
        wireAgentDashboardAndTimeline(engine)
    }

    // MARK: - Hook Event Wiring

    /// Connects the hook event receiver to the agent detection engine.
    ///
    /// Forwards events whose `cwd` matches a Cocxy tab. When no exact match
    /// is found, falls back to parent-directory matching (the tab's CWD is a
    /// prefix of the event's CWD) and then to the active tab. This handles
    /// the common production case where shell integration hasn't updated the
    /// tab's working directory via OSC 7.
    ///
    /// Uses a weak capture of `self` and resolves `windowController?.tabManager`
    /// lazily inside the sink closure to avoid retaining the tab manager eagerly.
    func wireHookReceiverToEngine(_ engine: AgentDetectionEngineImpl) {
        guard let receiver = hookEventReceiver else { return }

        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak engine, weak receiver, weak self] event in
                guard let tabManager = self?.windowController?.tabManager else {
                    // Window not yet available; forward the event to the engine
                    // without tab filtering.
                    engine?.processHookEvent(event)
                    return
                }

                // Match the event to a Cocxy tab by working directory.
                if let cwd = event.cwd {
                    let matchingTab = Self.findMatchingTab(
                        cwd: cwd,
                        tabs: tabManager.tabs,
                        activeTabID: tabManager.activeTabID
                    )
                    guard let matchingTab else { return }

                    // Update the tab's agentActivity with tool details for
                    // real-time visibility in the sidebar.
                    if case .toolUse(let toolData) = event.data {
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
                        tabManager.updateTab(id: matchingTab.id) { tab in
                            tab.agentActivity = activity
                        }
                    }
                }
                engine?.processHookEvent(event)
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
        guard windowController != nil else { return }

        // Map session IDs to tab IDs for accurate routing.
        var sessionToTab: [String: TabID] = [:]

        engine.stateChanged
            .sink { [weak windowController, weak self] context in
                guard let tabManager = windowController?.tabManager else { return }
                let agentState = context.state.toTabAgentState

                // Determine which tab this state change belongs to.
                // Hook-triggered transitions carry sessionId/cwd per-context
                // (race-free). Pattern/timing transitions fall back to active tab.
                let targetTabID: TabID?
                if let hookSessionId = context.hookSessionId,
                   let hookCwd = context.hookCwd {
                    if let cached = sessionToTab[hookSessionId] {
                        targetTabID = cached
                    } else {
                        let matchingTab = Self.findMatchingTab(
                            cwd: hookCwd,
                            tabs: tabManager.tabs,
                            activeTabID: tabManager.activeTabID
                        )
                        if let tab = matchingTab {
                            sessionToTab[hookSessionId] = tab.id
                            targetTabID = tab.id
                        } else {
                            return
                        }
                    }
                } else {
                    // No hook context — this is a pattern-based detection.
                    // Only apply to the active tab (pattern detection reads
                    // the active surface's output).
                    targetTabID = tabManager.activeTabID
                }

                guard let tabID = targetTabID else { return }

                tabManager.updateTab(id: tabID) { tab in
                    tab.agentState = agentState
                }
                windowController?.tabBarViewModel?.syncWithManager()
                windowController?.refreshStatusBar()

                windowController?.updateNotificationRing(
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

        // Provide tab CWDs so the dashboard can filter out external sessions.
        dashboardVM.tabCwdProvider = { [weak self] in
            self?.windowController?.tabManager.tabs.map { $0.workingDirectory.path } ?? []
        }

        // Resolve CWD → tab ID for accurate dashboard navigation.
        dashboardVM.tabIdForCwdProvider = { [weak self] cwd in
            let cwdStd = URL(fileURLWithPath: cwd).standardized.path
            return self?.windowController?.tabManager.tabs.first {
                $0.workingDirectory.standardized.path == cwdStd
            }?.id.rawValue
        }

        // Inject the dashboard VM into the window controller so
        // Cmd+Option+A shows real data instead of an empty view.
        windowController?.injectedDashboardViewModel = dashboardVM

        // Timeline: subscribes to hook events.
        let timelineStore = AgentTimelineStoreImpl()
        self.agentTimelineStore = timelineStore

        // Inject the timeline store into the window controller so
        // Cmd+Shift+T shows real events.
        windowController?.injectedTimelineStore = timelineStore

        guard let receiver = hookEventReceiver else { return }

        let timelineTabManager = windowController?.tabManager
        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak timelineStore, weak timelineTabManager] hookEvent in
                guard let store = timelineStore else { return }
                // Only log events from sessions running inside Cocxy tabs.
                if let cwd = hookEvent.cwd,
                   let tabs = timelineTabManager?.tabs {
                    let cwdURL = URL(fileURLWithPath: cwd).standardized
                    let hasMatchingTab = tabs.contains { tab in
                        tab.workingDirectory.standardized.path == cwdURL.path
                    }
                    guard hasMatchingTab else { return }
                }
                let timelineEvent = TimelineEvent.from(hookEvent: hookEvent)
                store.addEvent(timelineEvent)
            }
            .store(in: &hookCancellables)

        // Auto-split subagent panels: when SubagentStart arrives, spawn a
        // live activity panel on the right side. When SubagentStop arrives,
        // the panel stays visible (showing finished state) until dismissed.
        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hookEvent in
                guard hookEvent.type == .subagentStart else { return }
                guard case .subagent(let data) = hookEvent.data else { return }
                self?.windowController?.spawnSubagentPanel(
                    subagentId: data.subagentId,
                    sessionId: hookEvent.sessionId,
                    agentType: data.subagentType
                )
            }
            .store(in: &hookCancellables)
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
              let notificationManager = notificationManager,
              let windowController = windowController else { return }

        var previousStateByTab: [TabID: AgentState] = [:]

        engine.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak windowController, weak notificationManager] context in
                guard let tabManager = windowController?.tabManager,
                      let manager = notificationManager else { return }

                let agentState = context.state.toTabAgentState

                // Determine the target tab (same logic as wireAgentDetectionToTabs).
                let targetTabID: TabID?
                if let hookCwd = context.hookCwd {
                    targetTabID = Self.findMatchingTab(
                        cwd: hookCwd,
                        tabs: tabManager.tabs,
                        activeTabID: tabManager.activeTabID
                    )?.id
                } else {
                    targetTabID = tabManager.activeTabID
                }

                guard let tabID = targetTabID,
                      let tab = tabManager.tab(for: tabID) else { return }

                let previousState = previousStateByTab[tabID] ?? .idle
                previousStateByTab[tabID] = agentState

                // Only notify on meaningful transitions (skip idle→idle, etc.).
                guard agentState != previousState else { return }

                manager.handleStateChange(
                    state: agentState,
                    previousState: previousState,
                    for: tabID,
                    tabTitle: tab.title,
                    agentName: context.agentName
                )
            }
            .store(in: &hookCancellables)
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
