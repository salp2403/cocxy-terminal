// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartRoutingOverlayViewModel.swift - ViewModel for the Smart Routing overlay.

import Foundation
import Combine

// MARK: - Smart Routing Filter

/// Filter modes for the Smart Routing overlay.
///
/// Controls which agents are displayed in the overlay list.
enum SmartRoutingFilter: Equatable, Sendable {
    /// Show all agents needing attention (error + blocked + waiting).
    case all
    /// Show only agents in error state.
    case errorsOnly
    /// Show only agents waiting for user input.
    case waitingOnly
}

// MARK: - Smart Routing Overlay ViewModel

/// ViewModel for the Smart Routing overlay panel.
///
/// Manages the displayed list of agents, filter state, and selection.
/// The overlay shows agents needing attention with keyboard shortcuts
/// (1-9) for quick navigation.
///
/// ## Usage
///
/// ```swift
/// let viewModel = SmartRoutingOverlayViewModel(router: router)
/// viewModel.refresh()
/// viewModel.applyFilter(.errorsOnly)
/// viewModel.selectAgentByNumber(1) // navigate to first agent
/// ```
///
/// - SeeAlso: `SmartAgentRouting` protocol
/// - SeeAlso: `SmartRoutingOverlayView`
@MainActor
final class SmartRoutingOverlayViewModel {

    // MARK: - Published State

    /// The agents currently displayed in the overlay, after filtering.
    private(set) var displayedAgents: [AgentSessionInfo] = []

    /// The current active filter.
    private(set) var activeFilter: SmartRoutingFilter = .all

    /// Message shown when no agents need attention.
    let emptyMessage: String = "No agents need attention"

    // MARK: - Dependencies

    private let router: SmartAgentRouting

    // MARK: - Private State

    /// All agents needing attention (unfiltered cache).
    private var allAgentsNeedingAttention: [AgentSessionInfo] = []

    // MARK: - Initialization

    /// Creates a SmartRoutingOverlayViewModel.
    ///
    /// - Parameter router: The smart agent router providing data and navigation.
    init(router: SmartAgentRouting) {
        self.router = router
    }

    // MARK: - Public API

    /// Refreshes the displayed agents from the router.
    ///
    /// Call this when the overlay is shown or when the underlying data changes.
    func refresh() {
        allAgentsNeedingAttention = router.agentsNeedingAttention()
        applyCurrentFilter()
    }

    /// Applies a filter to the displayed agents.
    ///
    /// - Parameter filter: The filter mode to apply.
    func applyFilter(_ filter: SmartRoutingFilter) {
        activeFilter = filter
        applyCurrentFilter()
    }

    /// Selects an agent by its 1-based position number (keyboard shortcut).
    ///
    /// If the number is out of range (e.g., pressing 5 when only 3 agents
    /// are shown), the call is silently ignored.
    ///
    /// - Parameter number: The 1-based position of the agent to select.
    func selectAgentByNumber(_ number: Int) {
        let index = number - 1
        guard index >= 0, index < displayedAgents.count else { return }
        let session = displayedAgents[index]
        router.navigateToAgent(session.id)
    }

    // MARK: - Private

    private func applyCurrentFilter() {
        switch activeFilter {
        case .all:
            displayedAgents = allAgentsNeedingAttention
        case .errorsOnly:
            displayedAgents = router.agents(withState: .error)
        case .waitingOnly:
            displayedAgents = router.agents(withState: .waitingForInput)
        }
    }
}
