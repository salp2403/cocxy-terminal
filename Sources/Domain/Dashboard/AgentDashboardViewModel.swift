// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardViewModel.swift - ViewModel for the multi-agent dashboard.

import Foundation
import Combine

// MARK: - Agent Dashboard ViewModel

/// ViewModel that aggregates agent sessions from hook events and detection signals.
///
/// Subscribes to:
/// - `HookEventReceiver.eventPublisher` for Claude Code lifecycle events.
/// - `AgentDetectionEngine.stateChanged` for pattern-based agent detection.
///
/// Maintains a sorted list of `AgentSessionInfo` instances and publishes
/// changes via Combine for reactive UI binding.
///
/// ## Sorting
///
/// Sessions are sorted by:
/// 1. Priority (focus > priority > standard)
/// 2. State urgency (error > blocked > waitingForInput > working > launching > idle > finished)
/// 3. Last activity time (oldest first within the same group)
///
/// ## Thread Safety
///
/// All state mutations happen on the main thread via `@MainActor`.
/// The `HookEventReceiver` publishes from background threads; this ViewModel
/// uses `receive(on: DispatchQueue.main)` to ensure thread safety.
///
/// - SeeAlso: ADR-008 Section 5.1 (Dashboard)
/// - SeeAlso: `AgentDashboardProviding` protocol
@MainActor
final class AgentDashboardViewModel: AgentDashboardProviding, ObservableObject {

    // MARK: - Published State

    /// All current sessions, sorted by priority then urgency.
    @Published private(set) var sessions: [AgentSessionInfo] = [] {
        didSet {
            sessionsSubject.send(sessions)
        }
    }

    /// Whether the dashboard panel is visible.
    @Published var isVisible: Bool = false

    // MARK: - Publishers

    var sessionsPublisher: AnyPublisher<[AgentSessionInfo], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    // MARK: - Private State

    /// Mutable session data keyed by session ID.
    /// The `AgentSessionInfo` structs are immutable; this dictionary holds
    /// the mutable internal representation that gets rebuilt on each change.
    ///
    /// Module-internal so the FileChanged extension (and tests) can mutate
    /// it. External code never sees this — `sessions` remains the read-only
    /// public surface.
    var sessionDataStore: [String: MutableSessionData] = [:]

    /// Subject that emits the full session list on every change.
    private let sessionsSubject = CurrentValueSubject<[AgentSessionInfo], Never>([])

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Optional navigator for focusing tabs from dashboard row clicks.
    ///
    /// Injected after initialization to avoid circular dependencies.
    /// When nil, navigation calls are silently ignored.
    weak var tabNavigator: DashboardTabNavigating?

    /// Callback for cross-window navigation. When set and the local
    /// `tabNavigator` cannot find the tab, this callback is invoked
    /// with the tab UUID to broadcast a focusSession event.
    var onCrossWindowNavigate: ((UUID) -> Void)?

    /// Reference to the hook event receiver for accessing session context
    /// (cwd, session_id) when auto-creating sessions from tool use events.
    private weak var hookEventReceiver: HookEventReceiverImpl?

    /// Returns the working directories of all Cocxy tabs. Used to filter
    /// out hook events from Claude sessions running outside Cocxy.
    /// Injected by AppDelegate after initialization.
    var tabCwdProvider: (() -> [String])?

    /// Resolves a working directory to the tab ID that owns it.
    var tabIdForCwdProvider: ((String) -> UUID?)?

    /// Resolves a hook session ID plus optional working directory to the
    /// tab that currently owns the session. Used for multi-window routing
    /// when multiple tabs may share the same working directory.
    var tabIdResolver: ((String, String?) -> UUID?)?

    /// Resolves a tab UUID to the window that currently owns it.
    /// Injected by AppDelegate for cross-window dashboard presentation.
    var windowIDForTabProvider: ((UUID) -> WindowID?)?

    /// Resolves a stable window label for UI display.
    var windowLabelProvider: ((WindowID?) -> String?)?

    /// Resolves the tab and working directory currently feeding pattern-based
    /// detection. Unlike hook events, pattern detection has no stable session
    /// payload of its own, so it must be anchored to the focused visible tab.
    var activePatternContextProvider: (() -> (tabId: UUID, workingDirectory: String?)?)?

    /// Resolves the tab, surface, and working directory for a pattern-based
    /// transition emitted by the detection engine. When `surfaceID` is
    /// non-nil this provider must prefer the owning tab of that concrete
    /// surface, not merely the focused tab, so split panes running different
    /// agents in the same tab do not collapse into one dashboard session.
    var patternContextProvider: ((SurfaceID?) -> (tabId: UUID, surfaceID: SurfaceID?, workingDirectory: String?)?)?

    // MARK: - Initialization

    /// Creates a dashboard ViewModel and subscribes to event sources.
    ///
    /// - Parameters:
    ///   - hookEventReceiver: The hook event receiver to subscribe to.
    ///   - detectionEngine: Optional detection engine for non-hook agents.
    init(
        hookEventReceiver: HookEventReceiving? = nil,
        detectionEngine: AgentDetectionEngineImpl? = nil
    ) {
        self.hookEventReceiver = hookEventReceiver as? HookEventReceiverImpl
        subscribeToHookEvents(hookEventReceiver)
        subscribeToDetectionEngine(detectionEngine)
    }

    // MARK: - AgentDashboardProviding

    func toggleVisibility() {
        isVisible.toggle()
    }

    func setPriority(_ priority: AgentPriority, for sessionId: String) {
        guard sessionDataStore[sessionId] != nil else { return }
        sessionDataStore[sessionId]?.priority = priority
        rebuildSessions()
    }

    func mostUrgentSession() -> AgentSessionInfo? {
        sessions.first
    }

    func sessions(withState state: AgentDashboardState) -> [AgentSessionInfo] {
        sessions.filter { $0.state == state }
    }

    func activitySummary(for sessionId: String) -> String? {
        guard let data = sessionDataStore[sessionId] else { return nil }
        guard let activity = data.lastActivity else { return nil }
        return truncateActivity(activity)
    }

    // MARK: - Navigation

    /// Navigates to the tab associated with a dashboard session.
    ///
    /// Looks up the session by ID and delegates to `tabNavigator.focusTab(id:)`.
    /// If the session does not exist or no navigator is set, the call is silently ignored.
    ///
    /// - Parameter sessionId: The ID of the session to navigate to.
    func navigateToSession(_ sessionId: String) {
        guard let data = sessionDataStore[sessionId] else { return }
        let tabId = TabID(rawValue: data.tabId)

        // Try local navigation first. If this window owns the tab,
        // focusTab will switch to it directly.
        let handledLocally = tabNavigator?.focusTab(id: tabId) ?? false
        guard !handledLocally else { return }

        // For cross-window sessions, the local navigator may not find
        // the tab. Broadcast via the callback so the owning window
        // can activate and switch to the tab.
        onCrossWindowNavigate?(data.tabId)
    }

    /// Returns whether a concrete subagent is already tracked under a parent session.
    func hasSubagent(id subagentId: String, in sessionId: String) -> Bool {
        sessionDataStore[sessionId]?.subagents.contains(where: { $0.id == subagentId }) == true
    }

    /// Returns the tab UUID associated with a session, for targeting splits.
    func tabIdForSession(_ sessionId: String) -> UUID? {
        sessionDataStore[sessionId]?.tabId
    }

    // MARK: - Hook Event Processing

    /// Processes a single hook event and updates the session store.
    ///
    /// This is the core method that maps hook events to dashboard state changes.
    /// Called from the Combine subscription on the main thread.
    func processHookEvent(_ event: HookEvent) {
        switch event.type {
        case .sessionStart:
            handleSessionStart(event)
        case .sessionEnd:
            handleSessionEnd(event)
        case .stop:
            handleStop(event)
        case .preToolUse, .postToolUse:
            handleToolUse(event)
        case .postToolUseFailure:
            handleToolUseFailure(event)
        case .subagentStart:
            handleSubagentStart(event)
        case .subagentStop:
            handleSubagentStop(event)
        case .teammateIdle:
            handleTeammateIdle(event)
        case .taskCompleted:
            handleTaskCompleted(event)
        case .notification, .userPromptSubmit:
            // Informational events -- no dashboard state change.
            break
        case .cwdChanged:
            // CwdChanged is consumed by the tab wiring layer
            // (updates `Tab.workingDirectory`). No dashboard effect.
            break
        case .fileChanged:
            // Routed through the `+FileChanged` extension so that Phase 1
            // keeps this switch exhaustive even before Phase 3 wires the
            // real attribution logic. The default dispatch is a no-op.
            handleFileChangedEvent(event)
        }
    }

    // MARK: - Detection Engine Signal Processing

    /// Processes a detection engine state change for non-hook agents.
    ///
    /// Creates or updates a session based on pattern-detected agent activity.
    /// Uses a synthetic session ID derived from the agent name.
    func processDetectionSignal(
        agentName: String,
        state: AgentStateMachine.State,
        tabId: UUID,
        surfaceID: SurfaceID? = nil,
        workingDirectory: String? = nil
    ) {
        guard let agentName = normalizedDashboardAgentName(agentName) else {
            return
        }
        let patternContext = activePatternContextProvider?()
        let resolvedWorkingDirectory = workingDirectory
            ?? (patternContext?.tabId == tabId ? patternContext?.workingDirectory : nil)

        upsertPatternSession(
            agentName: agentName,
            state: state,
            tabId: tabId,
            surfaceID: surfaceID,
            workingDirectory: resolvedWorkingDirectory
        )
        rebuildSessions()
    }

    /// Mirrors the per-surface store into dashboard sessions.
    ///
    /// After the per-surface migration, `AgentStatePerSurfaceStore` is the
    /// source of truth for live agent state. The dashboard still needs its
    /// richer session model (subagents, file impact, priority), so this sync
    /// updates only the synthetic `pattern-<tab>-<surface>` rows owned by
    /// pattern/native detection and leaves hook-native rows untouched.
    func syncSurfaceAgentStates(_ states: [SurfaceID: SurfaceAgentState]) {
        var liveSurfaceSessionIDs = Set<String>()

        for (surfaceID, surfaceState) in states {
            guard surfaceState.isActive || surfaceState.hasAgent else {
                continue
            }
            guard let detectedAgent = surfaceState.detectedAgent,
                  let agentName = dashboardAgentName(for: detectedAgent) else {
                continue
            }
            guard let context = patternContextProvider?(surfaceID) else {
                continue
            }

            let sessionID = patternSessionID(
                tabId: context.tabId,
                surfaceID: context.surfaceID ?? surfaceID
            )
            liveSurfaceSessionIDs.insert(sessionID)

            let dashboardState = mapAgentState(surfaceState.agentState)
            let projectName = extractProjectName(from: context.workingDirectory)
            let activity = surfaceState.agentActivity

            if sessionDataStore[sessionID] == nil {
                sessionDataStore[sessionID] = MutableSessionData(
                    id: sessionID,
                    projectName: projectName != "Unknown" ? projectName : agentName,
                    tabId: context.tabId,
                    state: dashboardState,
                    agentName: agentName,
                    lastActivity: activity,
                    lastActivityTime: Date(),
                    totalToolCalls: surfaceState.agentToolCount,
                    totalErrors: surfaceState.agentErrorCount
                )
            } else {
                sessionDataStore[sessionID]?.state = dashboardState
                sessionDataStore[sessionID]?.agentName = agentName
                sessionDataStore[sessionID]?.lastActivity = activity
                sessionDataStore[sessionID]?.lastActivityTime = Date()
                sessionDataStore[sessionID]?.totalToolCalls = surfaceState.agentToolCount
                sessionDataStore[sessionID]?.totalErrors = surfaceState.agentErrorCount
            }
        }

        let staleSurfaceSessionIDs = sessionDataStore.keys.filter {
            $0.hasPrefix("pattern-") && !liveSurfaceSessionIDs.contains($0)
        }
        for sessionID in staleSurfaceSessionIDs {
            sessionDataStore.removeValue(forKey: sessionID)
        }

        rebuildSessions()
    }

    /// Processes a detection engine state change using a stable session ID.
    ///
    /// Pattern detection now emits the originating surface for every
    /// identified terminal pane. We anchor synthetic sessions to that
    /// surface whenever available. Without the surface component, two
    /// splits in the same tab (for example Claude on the left and Codex
    /// on the right) would both write to `pattern-<tabID>` and the later
    /// transition would overwrite the earlier dashboard row.
    private func processPatternDetectionSignal(
        agentName: String,
        state: AgentStateMachine.State,
        surfaceID: SurfaceID?
    ) {
        guard let agentName = normalizedDashboardAgentName(agentName) else {
            return
        }
        if let context = patternContextProvider?(surfaceID) {
            upsertPatternSession(
                agentName: agentName,
                state: state,
                tabId: context.tabId,
                surfaceID: surfaceID ?? context.surfaceID,
                workingDirectory: context.workingDirectory
            )
        } else if let context = activePatternContextProvider?() {
            upsertPatternSession(
                agentName: agentName,
                state: state,
                tabId: context.tabId,
                surfaceID: surfaceID,
                workingDirectory: context.workingDirectory
            )
        } else {
            // Degrade gracefully when the host has not injected focused-tab
            // context yet (for example isolated tests or early bootstrap).
            // The app wiring still prefers the tab-bound path above.
            let syntheticSessionId = "pattern-\(agentName)"
            if sessionDataStore[syntheticSessionId] == nil {
                let data = MutableSessionData(
                    id: syntheticSessionId,
                    projectName: agentName,
                    tabId: UUID(),
                    state: mapStateMachineState(state),
                    agentName: agentName
                )
                sessionDataStore[syntheticSessionId] = data
            } else {
                sessionDataStore[syntheticSessionId]?.state = mapStateMachineState(state)
                sessionDataStore[syntheticSessionId]?.lastActivityTime = Date()
                sessionDataStore[syntheticSessionId]?.agentName = agentName
            }
        }

        rebuildSessions()
    }

    private func dashboardAgentName(for detectedAgent: DetectedAgent) -> String? {
        normalizedDashboardAgentName(detectedAgent.displayName)
            ?? normalizedDashboardAgentName(detectedAgent.name)
    }

    /// Dashboard rows should represent a resolved agent identity, not a
    /// placeholder emitted while detection is still converging. Letting
    /// "Unknown" through creates the stale ghost row users saw in the
    /// Agent Dashboard even after Aurora's per-surface store was correct.
    private func normalizedDashboardAgentName(_ rawName: String?) -> String? {
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        guard name.localizedCaseInsensitiveCompare("unknown") != .orderedSame else {
            return nil
        }
        return name
    }

    private func upsertPatternSession(
        agentName: String,
        state: AgentStateMachine.State,
        tabId: UUID,
        surfaceID: SurfaceID?,
        workingDirectory: String?
    ) {
        let syntheticSessionId = patternSessionID(tabId: tabId, surfaceID: surfaceID)
        let dashboardState = mapStateMachineState(state)

        if sessionDataStore[syntheticSessionId] == nil {
            let projectName = extractProjectName(from: workingDirectory)
            let data = MutableSessionData(
                id: syntheticSessionId,
                projectName: projectName != "Unknown" ? projectName : agentName,
                tabId: tabId,
                state: dashboardState,
                agentName: agentName
            )
            sessionDataStore[syntheticSessionId] = data
        } else {
            sessionDataStore[syntheticSessionId]?.state = dashboardState
            sessionDataStore[syntheticSessionId]?.lastActivityTime = Date()
            sessionDataStore[syntheticSessionId]?.agentName = agentName
        }
    }

    private func patternSessionID(tabId: UUID, surfaceID: SurfaceID?) -> String {
        if let surfaceID {
            return "pattern-\(tabId.uuidString)-\(surfaceID.rawValue.uuidString)"
        }
        return "pattern-\(tabId.uuidString)"
    }

    // MARK: - Private: Event Handlers

    private func handleSessionStart(_ event: HookEvent) {
        var model: String?
        var agentType: String?
        var workingDirectory: String?

        if case .sessionStart(let startData) = event.data {
            model = startData.model
            agentType = startData.agentType
            workingDirectory = startData.workingDirectory
        }

        let projectName = extractProjectName(from: workingDirectory)
        let resolvedTabId = tabIdResolver?(event.sessionId, workingDirectory)
            ?? workingDirectory.flatMap { tabIdForCwdProvider?($0) }
            ?? UUID()

        let data = MutableSessionData(
            id: event.sessionId,
            projectName: projectName,
            tabId: resolvedTabId,
            state: .launching,
            agentName: agentType,
            model: model
        )
        sessionDataStore[event.sessionId] = data
        rebuildSessions()
    }

    private func handleSessionEnd(_ event: HookEvent) {
        sessionDataStore.removeValue(forKey: event.sessionId)
        rebuildSessions()
    }

    private func handleStop(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }

        sessionDataStore[event.sessionId]?.state = .finished

        if case .stop(let stopData) = event.data {
            if let message = stopData.lastMessage {
                sessionDataStore[event.sessionId]?.lastActivity = truncateActivity(message)
            }
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleToolUse(_ event: HookEvent) {
        // Auto-create session if it doesn't exist. Claude Code may not always
        // send SessionStart before tool use events (e.g., hooks installed mid-session).
        if sessionDataStore[event.sessionId] == nil {
            let projectName = extractProjectName(from: event.cwd)
            let resolvedTabId = tabIdResolver?(event.sessionId, event.cwd)
                ?? event.cwd.flatMap { tabIdForCwdProvider?($0) }
                ?? UUID()
            let data = MutableSessionData(
                id: event.sessionId,
                projectName: projectName,
                tabId: resolvedTabId,
                state: .working,
                agentName: "Claude Code"
            )
            sessionDataStore[event.sessionId] = data
        }

        sessionDataStore[event.sessionId]?.state = .working

        if case .toolUse(let toolData) = event.data {
            let activity = formatToolActivity(toolData)
            sessionDataStore[event.sessionId]?.lastActivity = activity
            sessionDataStore[event.sessionId]?.totalToolCalls += 1

            // Track file impact.
            trackFileImpact(sessionId: event.sessionId, toolData: toolData)

            // Attribute tool use to single active subagent when unambiguous.
            let filePath = toolData.toolInput?["file_path"] ?? toolData.toolInput?["path"]
            attributeToolUseToSubagent(
                sessionId: event.sessionId,
                activity: activity,
                toolName: toolData.toolName,
                filePath: filePath,
                timestamp: event.timestamp
            )
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleToolUseFailure(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }

        sessionDataStore[event.sessionId]?.state = .error

        if case .toolUse(let toolData) = event.data {
            let errorDesc = toolData.error ?? toolData.toolName
            let activity = "Error: \(errorDesc)"
            sessionDataStore[event.sessionId]?.lastActivity = activity
            sessionDataStore[event.sessionId]?.totalToolCalls += 1
            sessionDataStore[event.sessionId]?.totalErrors += 1

            // Track file impact even on failure.
            trackFileImpact(sessionId: event.sessionId, toolData: toolData)

            // Attribute error to single active subagent when unambiguous.
            attributeErrorToSubagent(
                sessionId: event.sessionId,
                errorDescription: errorDesc,
                toolName: toolData.toolName,
                timestamp: event.timestamp
            )
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleSubagentStart(_ event: HookEvent) {
        if sessionDataStore[event.sessionId] == nil {
            let projectName = extractProjectName(from: event.cwd)
            let resolvedTabId = tabIdResolver?(event.sessionId, event.cwd)
                ?? event.cwd.flatMap { tabIdForCwdProvider?($0) }
                ?? UUID()
            let data = MutableSessionData(
                id: event.sessionId,
                projectName: projectName,
                tabId: resolvedTabId,
                state: .working,
                agentName: "Claude Code"
            )
            sessionDataStore[event.sessionId] = data
        }

        if case .subagent(let subagentData) = event.data {
            let subagentId = subagentData.subagentId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subagentId.isEmpty else {
                sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
                rebuildSessions()
                return
            }

            if let index = sessionDataStore[event.sessionId]?.subagents.firstIndex(where: { $0.id == subagentId }) {
                sessionDataStore[event.sessionId]?.subagents[index].state = .working
                sessionDataStore[event.sessionId]?.subagents[index].endTime = nil
            } else {
                let subagent = SubagentInfo(
                    id: subagentId,
                    type: subagentData.subagentType,
                    state: .working,
                    startTime: event.timestamp
                )
                sessionDataStore[event.sessionId]?.subagents.append(subagent)
            }
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleSubagentStop(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }

        if case .subagent(let subagentData) = event.data {
            if let index = sessionDataStore[event.sessionId]?.subagents.firstIndex(
                where: { $0.id == subagentData.subagentId }
            ) {
                sessionDataStore[event.sessionId]?.subagents[index].state = .finished
                sessionDataStore[event.sessionId]?.subagents[index].endTime = event.timestamp
            }
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleTeammateIdle(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }
        sessionDataStore[event.sessionId]?.state = .waitingForInput
        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleTaskCompleted(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }
        sessionDataStore[event.sessionId]?.state = .finished

        if case .taskCompleted(let taskData) = event.data {
            if let description = taskData.taskDescription {
                sessionDataStore[event.sessionId]?.lastActivity = truncateActivity(description)
            }
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    // MARK: - Private: Subagent Attribution

    /// Attributes a tool use event to the single active subagent in a session.
    ///
    /// Only attributes when exactly one subagent is actively running.
    /// When multiple subagents run in parallel, tool events cannot be
    /// reliably attributed to a specific subagent.
    private func attributeToolUseToSubagent(
        sessionId: String,
        activity: String,
        toolName: String,
        filePath: String?,
        timestamp: Date
    ) {
        guard let subagents = sessionDataStore[sessionId]?.subagents else { return }
        let activeIndices = subagents.indices.filter { subagents[$0].isActive }
        guard activeIndices.count == 1 else { return }

        let idx = activeIndices[0]
        sessionDataStore[sessionId]?.subagents[idx].lastActivity = activity
        sessionDataStore[sessionId]?.subagents[idx].lastActivityTime = timestamp
        sessionDataStore[sessionId]?.subagents[idx].toolUseCount += 1

        // Track file path for conflict detection.
        if let path = filePath {
            sessionDataStore[sessionId]?.subagents[idx].touchedFilePaths.insert(path)
        }

        // Add to activity feed with FIFO eviction.
        let entry = ToolActivity(toolName: toolName, summary: activity, timestamp: timestamp)
        sessionDataStore[sessionId]?.subagents[idx].activities.append(entry)
        if sessionDataStore[sessionId]?.subagents[idx].activities.count ?? 0 > SubagentInfo.maxActivities {
            sessionDataStore[sessionId]?.subagents[idx].activities.removeFirst()
        }
    }

    /// Attributes a tool error to the single active subagent in a session.
    private func attributeErrorToSubagent(
        sessionId: String,
        errorDescription: String,
        toolName: String,
        timestamp: Date
    ) {
        guard let subagents = sessionDataStore[sessionId]?.subagents else { return }
        let activeIndices = subagents.indices.filter { subagents[$0].isActive }
        guard activeIndices.count == 1 else { return }

        let idx = activeIndices[0]
        sessionDataStore[sessionId]?.subagents[idx].errorCount += 1
        sessionDataStore[sessionId]?.subagents[idx].lastError = errorDescription
        sessionDataStore[sessionId]?.subagents[idx].lastActivityTime = timestamp

        // Add error to activity feed.
        let entry = ToolActivity(
            toolName: toolName, summary: errorDescription, timestamp: timestamp, isError: true
        )
        sessionDataStore[sessionId]?.subagents[idx].activities.append(entry)
        if sessionDataStore[sessionId]?.subagents[idx].activities.count ?? 0 > SubagentInfo.maxActivities {
            sessionDataStore[sessionId]?.subagents[idx].activities.removeFirst()
        }
    }

    /// Tracks which files a tool call touches and what operations are performed.
    private func trackFileImpact(sessionId: String, toolData: ToolUseData) {
        guard let filePath = toolData.toolInput?["file_path"] ?? toolData.toolInput?["path"] else {
            return
        }
        let operation: FileImpact.FileOperation
        switch toolData.toolName.lowercased() {
        case "read":  operation = .read
        case "write": operation = .write
        case "edit":  operation = .edit
        case "bash":  operation = .bash
        default:      operation = .read
        }
        sessionDataStore[sessionId]?.fileImpacts[filePath, default: []].insert(operation)
    }

    // MARK: - Private: Subscriptions

    private func subscribeToHookEvents(_ receiver: HookEventReceiving?) {
        guard let receiver = receiver else { return }

        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                // Only process events from sessions running inside Cocxy tabs.
                // Events without CWD are dropped when the provider is available,
                // preventing cross-terminal leakage.
                if let tabCwds = self.tabCwdProvider?() {
                    guard let cwd = event.cwd else { return }
                    let cwdStd = URL(fileURLWithPath: cwd).standardized.path
                    let matches = tabCwds.contains { tabCwd in
                        URL(fileURLWithPath: tabCwd).standardized.path == cwdStd
                    }
                    guard matches else { return }
                }
                self.processHookEvent(event)
            }
            .store(in: &cancellables)
    }

    private func subscribeToDetectionEngine(_ engine: AgentDetectionEngineImpl?) {
        guard let engine = engine else { return }

        engine.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] context in
                guard let self else { return }
                if let agentName = context.agentName {
                    self.processPatternDetectionSignal(
                        agentName: agentName,
                        state: context.state,
                        surfaceID: context.surfaceID
                    )
                } else if context.state == .idle {
                    // Idle without agent name — the state machine cleared it.
                    // Transition the originating surface to idle when it can
                    // be resolved; otherwise fall back to the legacy broad
                    // cleanup so isolated callers do not get stuck.
                    if let surfaceID = context.surfaceID,
                       let resolved = self.patternContextProvider?(surfaceID) {
                        self.transitionPatternSessionToIdle(
                            tabId: resolved.tabId,
                            surfaceID: resolved.surfaceID ?? surfaceID
                        )
                    } else {
                        self.transitionAllPatternSessionsToIdle()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Transitions one pattern-detected session to idle.
    private func transitionPatternSessionToIdle(tabId: UUID, surfaceID: SurfaceID?) {
        let key = patternSessionID(tabId: tabId, surfaceID: surfaceID)
        guard sessionDataStore[key]?.state != .idle else { return }
        sessionDataStore[key]?.state = .idle
        sessionDataStore[key]?.lastActivityTime = Date()
        rebuildSessions()
    }

    /// Transitions all pattern-detected sessions to idle.
    private func transitionAllPatternSessionsToIdle() {
        var changed = false
        for key in sessionDataStore.keys where key.hasPrefix("pattern-") {
            if sessionDataStore[key]?.state != .idle {
                sessionDataStore[key]?.state = .idle
                sessionDataStore[key]?.lastActivityTime = Date()
                changed = true
            }
        }
        if changed { rebuildSessions() }
    }

    // MARK: - Session Rebuild

    /// Rebuilds the sorted `sessions` array from the mutable data store.
    ///
    /// Module-internal because the `+FileChanged` extension calls it after
    /// mutating `sessionDataStore`. External code observes via the
    /// `@Published var sessions` property.
    func rebuildSessions() {
        sessions = sessionDataStore.values
            .map { data in
                let windowID = windowIDForTabProvider?(data.tabId)
                let windowLabel = windowLabelProvider?(windowID)
                return data.toAgentSessionInfo(windowID: windowID, windowLabel: windowLabel)
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                if lhs.state != rhs.state {
                    return lhs.state < rhs.state
                }
                let lhsTime = lhs.lastActivityTime ?? .distantPast
                let rhsTime = rhs.lastActivityTime ?? .distantPast
                return lhsTime < rhsTime
            }
    }

    // MARK: - Private: Helpers

    /// Extracts the project name from a working directory path.
    private func extractProjectName(from path: String?) -> String {
        guard let path = path else { return "Unknown" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// Formats a tool use event into a human-readable activity string.
    private func formatToolActivity(_ toolData: ToolUseData) -> String {
        let toolName = toolData.toolName
        if let path = toolData.toolInput?["file_path"] ?? toolData.toolInput?["path"] {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return "\(toolName): \(fileName)"
        }
        if let command = toolData.toolInput?["command"] {
            let truncatedCommand = String(command.prefix(50))
            return "\(toolName): \(truncatedCommand)"
        }
        return toolName
    }

    /// Truncates an activity string to a maximum length.
    private func truncateActivity(_ activity: String, maxLength: Int = 80) -> String {
        if activity.count <= maxLength {
            return activity
        }
        return String(activity.prefix(maxLength - 3)) + "..."
    }

    /// Maps AgentStateMachine.State to AgentDashboardState.
    private func mapStateMachineState(_ state: AgentStateMachine.State) -> AgentDashboardState {
        switch state {
        case .idle:
            return .idle
        case .agentLaunched:
            return .launching
        case .working:
            return .working
        case .waitingInput:
            return .waitingForInput
        case .finished:
            return .finished
        case .error:
            return .error
        }
    }

    private func mapAgentState(_ state: AgentState) -> AgentDashboardState {
        switch state {
        case .idle:
            return .idle
        case .launched:
            return .launching
        case .working:
            return .working
        case .waitingInput:
            return .waitingForInput
        case .finished:
            return .finished
        case .error:
            return .error
        }
    }
}

// MARK: - Mutable Session Data

/// Internal mutable representation of a session.
///
/// The `AgentSessionInfo` struct is immutable (value type). This class holds
/// the mutable state that gets rebuilt into `AgentSessionInfo` on every change.
struct MutableSessionData {
    let id: String
    let projectName: String
    let tabId: UUID
    var state: AgentDashboardState
    var agentName: String?
    var model: String?
    var gitBranch: String?
    var lastActivity: String?
    var lastActivityTime: Date?
    var subagents: [SubagentInfo] = []
    var priority: AgentPriority = .standard
    /// Files touched during this session. Key is full path, value is set of operations.
    var fileImpacts: [String: Set<FileImpact.FileOperation>] = [:]
    /// Total tool calls across the session (including subagent-attributed ones).
    var totalToolCalls: Int = 0
    /// Total errors across the session.
    var totalErrors: Int = 0

    func toAgentSessionInfo(windowID: WindowID?, windowLabel: String?) -> AgentSessionInfo {
        // Build file impact list sorted by path.
        let impacts = fileImpacts.map { FileImpact(path: $0.key, operations: $0.value) }
            .sorted { $0.fileName < $1.fileName }

        // Detect file conflicts: files touched by multiple subagents.
        let conflicts = detectFileConflicts()

        return AgentSessionInfo(
            id: id,
            projectName: projectName,
            windowID: windowID,
            windowLabel: windowLabel,
            gitBranch: gitBranch,
            agentName: agentName,
            state: state,
            lastActivity: lastActivity,
            lastActivityTime: lastActivityTime,
            tabId: tabId,
            subagents: subagents,
            priority: priority,
            model: model,
            filesTouched: impacts,
            fileConflicts: conflicts,
            totalToolCalls: totalToolCalls,
            totalErrors: totalErrors
        )
    }

    /// Detects files touched by more than one subagent in this session.
    ///
    /// Uses the `touchedFilePaths` set on each subagent, which is populated
    /// from actual tool input file paths (not parsed from activity strings).
    private func detectFileConflicts() -> [String] {
        var fileToSubagents: [String: Set<String>] = [:]
        for sub in subagents {
            for path in sub.touchedFilePaths {
                fileToSubagents[path, default: []].insert(sub.id)
            }
        }
        return fileToSubagents.filter { $0.value.count > 1 }.map(\.key).sorted()
    }
}
