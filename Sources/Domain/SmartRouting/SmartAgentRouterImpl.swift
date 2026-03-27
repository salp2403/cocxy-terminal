// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartAgentRouterImpl.swift - Implementation of SmartAgentRouting.

import Foundation

// MARK: - Smart Agent Router Implementation

/// Concrete implementation of `SmartAgentRouting`.
///
/// Uses `AgentDashboardProviding` as its data source to read the current
/// list of agent sessions, filters them to those needing attention, and
/// sorts by urgency.
///
/// Navigation is delegated to a `DashboardTabNavigating` instance, which
/// is typically the `TabManager`.
///
/// ## States That Need Attention
///
/// - `.error`: Agent encountered a fatal error.
/// - `.blocked`: Agent is blocked on a permission request.
/// - `.waitingForInput`: Agent is waiting for user response.
///
/// All other states (`.working`, `.idle`, `.launching`, `.finished`) are
/// considered "not needing attention".
///
/// - SeeAlso: `SmartAgentRouting` protocol
/// - SeeAlso: `AgentDashboardProviding` protocol
@MainActor
final class SmartAgentRouterImpl: SmartAgentRouting {

    // MARK: - Dependencies

    private let dashboard: AgentDashboardProviding
    private weak var tabNavigator: DashboardTabNavigating?

    // MARK: - Constants

    /// States that indicate an agent needs user attention.
    private static let attentionStates: Set<AgentDashboardState> = [
        .error,
        .blocked,
        .waitingForInput
    ]

    // MARK: - Initialization

    /// Creates a SmartAgentRouter.
    ///
    /// - Parameters:
    ///   - dashboard: The agent dashboard providing session data.
    ///   - tabNavigator: The navigator for focusing agent tabs.
    init(dashboard: AgentDashboardProviding, tabNavigator: DashboardTabNavigating?) {
        self.dashboard = dashboard
        self.tabNavigator = tabNavigator
    }

    // MARK: - SmartAgentRouting

    func agentsNeedingAttention() -> [AgentSessionInfo] {
        dashboard.sessions
            .filter { Self.attentionStates.contains($0.state) }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state {
                    return lhs.state < rhs.state
                }
                let lhsTime = lhs.lastActivityTime ?? .distantPast
                let rhsTime = rhs.lastActivityTime ?? .distantPast
                return lhsTime < rhsTime
            }
    }

    func agents(withState state: AgentDashboardState) -> [AgentSessionInfo] {
        dashboard.sessions.filter { $0.state == state }
    }

    func mostUrgentAgent() -> AgentSessionInfo? {
        agentsNeedingAttention().first
    }

    func navigateToAgent(_ sessionId: String) {
        guard let session = dashboard.sessions.first(where: { $0.id == sessionId }) else {
            return
        }
        let tabId = TabID(rawValue: session.tabId)
        tabNavigator?.focusTab(id: tabId)
    }
}
