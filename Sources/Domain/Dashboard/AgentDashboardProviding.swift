// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardProviding.swift - Protocol for the agent dashboard service.

import Foundation
import Combine

// MARK: - Agent Dashboard Providing Protocol

/// Contract for the agent dashboard service.
///
/// Provides a reactive list of agent sessions sorted by priority and urgency,
/// along with convenience methods for filtering, prioritizing, and querying
/// session state.
///
/// The dashboard subscribes to `HookEventReceiver` and `AgentDetectionEngine`
/// to automatically track agent sessions. UI consumers bind to `sessionsPublisher`
/// for reactive updates.
///
/// - SeeAlso: ADR-008 Section 5.1 (Dashboard)
/// - SeeAlso: HU-101 (Multi-agent dashboard)
@MainActor protocol AgentDashboardProviding: AnyObject {
    /// All current agent sessions, sorted by priority then urgency.
    var sessions: [AgentSessionInfo] { get }

    /// Publisher for UI binding. Emits the full session list on every change.
    var sessionsPublisher: AnyPublisher<[AgentSessionInfo], Never> { get }

    /// Whether the dashboard panel is currently visible.
    var isVisible: Bool { get set }

    /// Toggles dashboard panel visibility.
    func toggleVisibility()

    /// Updates the priority of an agent session.
    ///
    /// - Parameters:
    ///   - priority: The new priority level.
    ///   - sessionId: The session to update.
    func setPriority(_ priority: AgentPriority, for sessionId: String)

    /// Returns the most urgent agent session (for Quick Switch).
    ///
    /// Urgency order: error > blocked > waitingForInput > working.
    /// Within the same state, the oldest session wins.
    ///
    /// - Returns: The most urgent session, or nil if no sessions exist.
    func mostUrgentSession() -> AgentSessionInfo?

    /// Returns sessions filtered by a specific state.
    ///
    /// - Parameter state: The state to filter by.
    /// - Returns: Sessions matching the given state, sorted by priority.
    func sessions(withState state: AgentDashboardState) -> [AgentSessionInfo]

    /// Returns a summary of the last activity for a session.
    ///
    /// - Parameter sessionId: The session to query.
    /// - Returns: A human-readable summary, or nil if no activity recorded.
    func activitySummary(for sessionId: String) -> String?
}
