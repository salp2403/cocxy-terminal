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
    private(set) var sessions: [AgentSessionInfo] = [] {
        didSet {
            sessionsSubject.send(sessions)
        }
    }

    /// Whether the dashboard panel is visible.
    var isVisible: Bool = false

    // MARK: - Publishers

    var sessionsPublisher: AnyPublisher<[AgentSessionInfo], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    // MARK: - Private State

    /// Mutable session data keyed by session ID.
    /// The `AgentSessionInfo` structs are immutable; this dictionary holds
    /// the mutable internal representation that gets rebuilt on each change.
    private var sessionDataStore: [String: MutableSessionData] = [:]

    /// Subject that emits the full session list on every change.
    private let sessionsSubject = CurrentValueSubject<[AgentSessionInfo], Never>([])

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Optional navigator for focusing tabs from dashboard row clicks.
    ///
    /// Injected after initialization to avoid circular dependencies.
    /// When nil, navigation calls are silently ignored.
    weak var tabNavigator: DashboardTabNavigating?

    /// Reference to the hook event receiver for accessing session context
    /// (cwd, session_id) when auto-creating sessions from tool use events.
    private weak var hookEventReceiver: HookEventReceiverImpl?

    /// Returns the working directories of all Cocxy tabs. Used to filter
    /// out hook events from Claude sessions running outside Cocxy.
    /// Injected by AppDelegate after initialization.
    var tabCwdProvider: (() -> [String])?

    /// Resolves a working directory to the tab ID that owns it.
    var tabIdForCwdProvider: ((String) -> UUID?)?

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
        tabNavigator?.focusTab(id: tabId)
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
        tabId: UUID
    ) {
        let syntheticSessionId = "pattern-\(tabId.uuidString)"

        if sessionDataStore[syntheticSessionId] == nil {
            let cwd = hookEventReceiver?.lastReceivedCwd
            let projectName = extractProjectName(from: cwd)
            let data = MutableSessionData(
                id: syntheticSessionId,
                projectName: projectName != "Unknown" ? projectName : agentName,
                tabId: tabId,
                state: mapStateMachineState(state),
                agentName: agentName
            )
            sessionDataStore[syntheticSessionId] = data
        } else {
            sessionDataStore[syntheticSessionId]?.state = mapStateMachineState(state)
            sessionDataStore[syntheticSessionId]?.lastActivityTime = Date()
        }

        rebuildSessions()
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
        let resolvedTabId = workingDirectory.flatMap { tabIdForCwdProvider?($0) } ?? UUID()

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
            let resolvedTabId = event.cwd.flatMap { tabIdForCwdProvider?($0) } ?? UUID()
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
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleToolUseFailure(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }

        sessionDataStore[event.sessionId]?.state = .error

        if case .toolUse(let toolData) = event.data {
            let activity = "Error: \(toolData.error ?? toolData.toolName)"
            sessionDataStore[event.sessionId]?.lastActivity = activity
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleSubagentStart(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }

        if case .subagent(let subagentData) = event.data {
            let subagent = SubagentInfo(
                id: subagentData.subagentId,
                type: subagentData.subagentType,
                state: .working
            )
            sessionDataStore[event.sessionId]?.subagents.append(subagent)
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleSubagentStop(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }

        if case .subagent(let subagentData) = event.data {
            sessionDataStore[event.sessionId]?.subagents.removeAll {
                $0.id == subagentData.subagentId
            }
        }

        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp
        rebuildSessions()
    }

    private func handleTeammateIdle(_ event: HookEvent) {
        guard sessionDataStore[event.sessionId] != nil else { return }
        sessionDataStore[event.sessionId]?.state = .idle
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

    // MARK: - Private: Subscriptions

    private func subscribeToHookEvents(_ receiver: HookEventReceiving?) {
        guard let receiver = receiver else { return }

        receiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                // Only process events from sessions running inside Cocxy tabs.
                if let cwd = event.cwd,
                   let tabCwds = self.tabCwdProvider?() {
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
                // Read agentName from the context itself, not from the engine,
                // to avoid a strong capture and ensure data consistency.
                guard let agentName = context.agentName else { return }
                self?.processDetectionSignal(
                    agentName: agentName,
                    state: context.state,
                    tabId: UUID()
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Private: Session Rebuild

    /// Rebuilds the sorted `sessions` array from the mutable data store.
    private func rebuildSessions() {
        sessions = sessionDataStore.values
            .map { $0.toAgentSessionInfo() }
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
}

// MARK: - Mutable Session Data

/// Internal mutable representation of a session.
///
/// The `AgentSessionInfo` struct is immutable (value type). This class holds
/// the mutable state that gets rebuilt into `AgentSessionInfo` on every change.
private struct MutableSessionData {
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

    func toAgentSessionInfo() -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: projectName,
            gitBranch: gitBranch,
            agentName: agentName,
            state: state,
            lastActivity: lastActivity,
            lastActivityTime: lastActivityTime,
            tabId: tabId,
            subagents: subagents,
            priority: priority,
            model: model
        )
    }
}
