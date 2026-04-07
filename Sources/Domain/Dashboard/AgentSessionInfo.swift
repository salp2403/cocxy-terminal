// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSessionInfo.swift - Domain models for the agent dashboard.

import Foundation

// MARK: - Agent Dashboard State

/// The state of an agent session as displayed in the dashboard.
///
/// States are ordered by urgency for sorting purposes:
/// error > blocked > waitingForInput > working > launching > idle > finished.
///
/// - SeeAlso: ADR-008 Section 5.1 (Dashboard states)
enum AgentDashboardState: String, Codable, Sendable, CaseIterable {
    /// Agent is actively processing (tool calls, output generation).
    case working
    /// Agent is waiting for user response (question, confirmation).
    case waitingForInput
    /// Agent is blocked (permission request or error during tool execution).
    case blocked
    /// Agent has been idle for a while (no recent activity).
    case idle
    /// Agent has completed its task successfully.
    case finished
    /// Agent encountered a fatal error.
    case error
    /// Agent session is starting up.
    case launching
}

// MARK: - Agent Dashboard State Urgency

extension AgentDashboardState: Comparable {
    /// Urgency order for sorting: lower raw value = higher urgency.
    ///
    /// Error and blocked sessions appear first in the dashboard,
    /// followed by those waiting for input, then active, then completed.
    private var urgencyOrder: Int {
        switch self {
        case .error:           return 0
        case .blocked:         return 1
        case .waitingForInput: return 2
        case .working:         return 3
        case .launching:       return 4
        case .idle:            return 5
        case .finished:        return 6
        }
    }

    static func < (lhs: AgentDashboardState, rhs: AgentDashboardState) -> Bool {
        lhs.urgencyOrder < rhs.urgencyOrder
    }
}

// MARK: - Agent Priority

/// Priority level for agent sessions in the dashboard.
///
/// Users can pin sessions to the top (focus) or mark them as important (priority).
/// Sorting: focus first, then priority, then standard.
enum AgentPriority: Int, Codable, Sendable, Comparable {
    /// Highest priority -- pinned to the top of the dashboard.
    case focus = 0
    /// Important -- shown above standard sessions.
    case priority = 1
    /// Default priority for new sessions.
    case standard = 2

    static func < (lhs: AgentPriority, rhs: AgentPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Subagent Info

/// Information about a nested subagent within a parent agent session.
///
/// Claude Code can spawn subagents (e.g., for research or code review).
/// These are displayed as nested items in the dashboard with rich status
/// including duration, tool activity, and error tracking.
struct SubagentInfo: Identifiable, Equatable, Sendable {
    /// Unique identifier for the subagent (matches hook event subagentId).
    let id: String
    /// The type of subagent (e.g., "Explore", "Plan", "general-purpose").
    let type: String?
    /// Current state of the subagent.
    var state: AgentDashboardState
    /// When the subagent started running.
    let startTime: Date
    /// When the subagent finished (nil if still running).
    var endTime: Date?
    /// Description of the last tool activity (e.g., "Read: AppDelegate.swift").
    var lastActivity: String?
    /// Timestamp of the last tool activity.
    var lastActivityTime: Date?
    /// Number of tool calls attributed to this subagent.
    var toolUseCount: Int = 0
    /// Number of tool errors encountered.
    var errorCount: Int = 0
    /// Description of the last error, if any.
    var lastError: String?
    /// Recent tool activities for this subagent (max 20, FIFO).
    var activities: [ToolActivity] = []
    /// File paths touched by this subagent (for conflict detection).
    var touchedFilePaths: Set<String> = []

    /// Maximum activities kept per subagent to bound memory.
    static let maxActivities = 20

    /// Duration the subagent has been running, or total duration if finished.
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    /// Whether the subagent is still actively running.
    var isActive: Bool {
        state == .working || state == .launching
    }
}

// MARK: - Tool Activity

/// A single tool call recorded in the activity feed.
///
/// Provides the structured equivalent of "raw output" — each tool call
/// with its target and result, organized and filterable.
struct ToolActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let summary: String
    let timestamp: Date
    let isError: Bool

    init(toolName: String, summary: String, timestamp: Date, isError: Bool = false) {
        self.id = UUID()
        self.toolName = toolName
        self.summary = summary
        self.timestamp = timestamp
        self.isError = isError
    }

    /// Value-based equality excluding the auto-generated `id`.
    /// Prevents unnecessary SwiftUI re-renders when activities have
    /// identical content but different UUIDs.
    static func == (lhs: ToolActivity, rhs: ToolActivity) -> Bool {
        lhs.toolName == rhs.toolName
        && lhs.summary == rhs.summary
        && lhs.timestamp == rhs.timestamp
        && lhs.isError == rhs.isError
    }
}

// MARK: - File Impact

/// Tracks how a file was accessed during a session.
struct FileImpact: Equatable, Sendable {
    let path: String
    let fileName: String
    var operations: Set<FileOperation>

    enum FileOperation: String, Sendable, Hashable {
        case read
        case write
        case edit
        case bash
    }

    init(path: String, operations: Set<FileOperation> = []) {
        self.path = path
        self.fileName = URL(fileURLWithPath: path).lastPathComponent
        self.operations = operations
    }
}

// MARK: - Agent Session Info

/// Represents a single agent session visible in the dashboard.
///
/// Each session maps to a Claude Code (or other agent) process running
/// in a Cocxy tab. The dashboard aggregates these sessions and presents
/// them sorted by urgency.
///
/// - SeeAlso: HU-101, HU-102 in PRD-002
struct AgentSessionInfo: Identifiable, Equatable, Sendable {
    /// Unique identifier for this session (matches Claude Code sessionId).
    let id: String
    /// Name of the project directory where the agent is working.
    let projectName: String
    /// The window currently owning the tab for this session, when known.
    let windowID: WindowID?
    /// Human-readable window label for dashboard display.
    let windowLabel: String?
    /// Current git branch in the working directory, if any.
    let gitBranch: String?
    /// Name of the detected agent (e.g., "Claude Code", "Codex").
    let agentName: String?
    /// Current state of the agent session.
    let state: AgentDashboardState
    /// Description of the last activity (e.g., "Write: Sources/App.swift").
    let lastActivity: String?
    /// Timestamp of the last activity.
    let lastActivityTime: Date?
    /// ID of the Cocxy tab where this session is running.
    let tabId: UUID
    /// Nested subagents spawned by this session.
    let subagents: [SubagentInfo]
    /// User-assigned priority for this session.
    let priority: AgentPriority
    /// Model name used by the agent (e.g., "claude-sonnet-4").
    let model: String?
    /// Files touched during this session with operation types.
    /// Populated by `toAgentSessionInfo()`; treat as immutable after construction.
    var filesTouched: [FileImpact] = []
    /// File paths touched by multiple subagents (conflict risk).
    /// Populated by `toAgentSessionInfo()`; treat as immutable after construction.
    var fileConflicts: [String] = []
    /// Total tool calls across the session.
    var totalToolCalls: Int = 0
    /// Total errors across the session.
    var totalErrors: Int = 0

    init(
        id: String,
        projectName: String,
        windowID: WindowID? = nil,
        windowLabel: String? = nil,
        gitBranch: String?,
        agentName: String?,
        state: AgentDashboardState,
        lastActivity: String?,
        lastActivityTime: Date?,
        tabId: UUID,
        subagents: [SubagentInfo],
        priority: AgentPriority,
        model: String?,
        filesTouched: [FileImpact] = [],
        fileConflicts: [String] = [],
        totalToolCalls: Int = 0,
        totalErrors: Int = 0
    ) {
        self.id = id
        self.projectName = projectName
        self.windowID = windowID
        self.windowLabel = windowLabel
        self.gitBranch = gitBranch
        self.agentName = agentName
        self.state = state
        self.lastActivity = lastActivity
        self.lastActivityTime = lastActivityTime
        self.tabId = tabId
        self.subagents = subagents
        self.priority = priority
        self.model = model
        self.filesTouched = filesTouched
        self.fileConflicts = fileConflicts
        self.totalToolCalls = totalToolCalls
        self.totalErrors = totalErrors
    }
}
