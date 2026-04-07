// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateAggregator.swift - Cross-window agent state aggregation.

import Foundation
import Combine

// MARK: - Agent State Event

/// Describes an agent state change from any window.
///
/// Published by the aggregator so consumers (dashboard, timeline, status bar)
/// can react to agent activity across the entire application.
struct AgentStateEvent: Sendable {
    /// The session whose agent state changed.
    let sessionID: SessionID

    /// The window that owns this session.
    let windowID: WindowID

    /// The agent state before the change.
    let previousState: AgentState

    /// The agent state after the change.
    let newState: AgentState

    /// Name of the detected agent (e.g., "Claude Code").
    let agentName: String?

    /// Timestamp of the change.
    let timestamp: Date
}

// MARK: - Protocol

/// Contract for aggregating agent state across all windows.
///
/// The aggregator reads from the `SessionRegistry` to provide a unified
/// view of all agent activity. The dashboard consumes this to show agents
/// from all windows, not just the current one.
///
/// ## Data Flow
///
/// ```
/// AgentDetectionEngine -> stateChanged
///   -> wireAgentDetectionToTabs -> tabManager.updateTab + registry.updateAgentState
///     -> AgentStateAggregator (reads registry) -> publishes events
///       -> Dashboard, StatusBar, Timeline
/// ```
@MainActor
protocol AgentStateAggregating: AnyObject {

    /// All sessions that have an active agent (not `.idle`).
    var activeAgentSessions: [SessionEntry] { get }

    /// Sessions with a specific agent state.
    func sessions(withAgentState state: AgentState) -> [SessionEntry]

    /// Publisher that emits on every agent state change in any window.
    var agentStateChanged: AnyPublisher<AgentStateEvent, Never> { get }
}

// MARK: - Implementation

/// Aggregates agent state from the `SessionRegistry`.
///
/// Subscribes to `sessionUpdated` events filtered to `.agentStateChanged`.
/// Recomputes the active session list from the registry on every change.
@MainActor
final class AgentStateAggregatorImpl: AgentStateAggregating {

    // MARK: - Dependencies

    private let registry: any SessionRegistering

    // MARK: - Subjects

    private let agentStateSubject = PassthroughSubject<AgentStateEvent, Never>()

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(registry: any SessionRegistering) {
        self.registry = registry
        subscribeToRegistryChanges()
    }

    // MARK: - Protocol

    var activeAgentSessions: [SessionEntry] {
        registry.allSessions.filter { $0.agentState != .idle }
    }

    func sessions(withAgentState state: AgentState) -> [SessionEntry] {
        registry.allSessions.filter { $0.agentState == state }
    }

    var agentStateChanged: AnyPublisher<AgentStateEvent, Never> {
        agentStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Subscriptions

    private func subscribeToRegistryChanges() {
        registry.sessionUpdated
            .sink { [weak self] event in
                guard let self else { return }
                guard case .agentStateChanged(let old, let new) = event.change else { return }

                let entry = self.registry.session(for: event.sessionID)
                self.agentStateSubject.send(AgentStateEvent(
                    sessionID: event.sessionID,
                    windowID: event.windowID,
                    previousState: old,
                    newState: new,
                    agentName: entry?.detectedAgentName,
                    timestamp: Date()
                ))
            }
            .store(in: &cancellables)
    }
}
