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
/// These are displayed as nested items in the dashboard.
struct SubagentInfo: Identifiable, Equatable, Sendable {
    /// Unique identifier for the subagent (matches hook event subagentId).
    let id: String
    /// The type of subagent (e.g., "research", "code-review").
    let type: String?
    /// Current state of the subagent.
    let state: AgentDashboardState
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
}
