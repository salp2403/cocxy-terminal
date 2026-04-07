// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardTabNavigating.swift - Protocol for dashboard-to-tab navigation.

import Foundation

// MARK: - Dashboard Tab Navigating Protocol

/// Contract for navigating from the agent dashboard to a specific tab.
///
/// The dashboard ViewModel uses this protocol to focus a tab when the user
/// clicks on a session row. Concrete implementation is provided by
/// `TabManager` (which already conforms to `TabActivating`).
///
/// Injected into the ViewModel to avoid a direct dependency on `TabManager`.
///
/// - SeeAlso: `AgentDashboardViewModel`
/// - SeeAlso: `TabManager`
protocol DashboardTabNavigating: AnyObject {
    /// Focuses the tab with the given identifier.
    ///
    /// If the tab does not exist, the call is silently ignored.
    ///
    /// - Parameter id: The tab identifier to focus.
    @MainActor
    func focusTab(id: TabID) -> Bool
}
