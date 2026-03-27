// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartAgentRouting.swift - Protocol for smart agent routing.

import Foundation

// MARK: - Smart Agent Routing Protocol

/// Contract for routing to agents that need attention.
///
/// Provides a prioritized list of agents needing user intervention,
/// filtered views by state, and navigation to specific agent tabs.
///
/// ## Priority Order
///
/// Agents are sorted by urgency:
/// 1. Error (most urgent)
/// 2. Blocked
/// 3. Waiting for input
///
/// Within the same urgency level, agents that have been waiting longest
/// appear first (oldest `lastActivityTime`).
///
/// States like `working`, `idle`, `launching`, and `finished` are NOT
/// considered "needing attention" and are excluded from the attention list.
///
/// - SeeAlso: HU-110, HU-111 in PRD-002
/// - SeeAlso: ADR-008 Section Smart Routing
@MainActor
protocol SmartAgentRouting: AnyObject {
    /// Returns all agents that need attention, sorted by urgency.
    ///
    /// Only agents in states `error`, `blocked`, or `waitingForInput`
    /// are included. Sorted by urgency (error > blocked > waitingForInput),
    /// then by oldest activity time first within the same urgency.
    ///
    /// - Returns: An array of sessions needing attention, sorted by urgency.
    func agentsNeedingAttention() -> [AgentSessionInfo]

    /// Returns agents filtered by a specific state.
    ///
    /// - Parameter state: The state to filter by.
    /// - Returns: Sessions matching the given state.
    func agents(withState state: AgentDashboardState) -> [AgentSessionInfo]

    /// Returns the single most urgent agent for simple Quick Switch.
    ///
    /// This is the first agent from `agentsNeedingAttention()`, or nil
    /// if no agents need attention.
    ///
    /// - Returns: The most urgent session, or nil.
    func mostUrgentAgent() -> AgentSessionInfo?

    /// Navigates to a specific agent's tab.
    ///
    /// Delegates to the tab navigator to focus the tab where the agent
    /// is running. If the session ID is not found, the call is silently ignored.
    ///
    /// - Parameter sessionId: The session ID of the agent to navigate to.
    func navigateToAgent(_ sessionId: String)
}
