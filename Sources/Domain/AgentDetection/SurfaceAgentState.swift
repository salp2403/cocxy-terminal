// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceAgentState.swift - Per-surface runtime agent activity.

import Foundation

/// Runtime agent-detection state scoped to a single terminal surface.
///
/// Unlike `Tab`, which represents a UI container that may hold multiple
/// split surfaces, this value captures the agent activity of one specific
/// surface. This enables independent agent tracking across splits of the
/// same tab (for example, a user can run `claude` in one split and `codex`
/// in another without state cross-contamination).
///
/// `Codable` is provided for diagnostic snapshots and future serialization
/// needs; runtime state itself is intentionally ephemeral and not persisted
/// to disk. `Equatable` enables publisher deduplication via `removeDuplicates`.
/// `Sendable` allows safe cross-actor usage.
struct SurfaceAgentState: Equatable, Sendable, Codable {

    /// Current state of the AI agent in this surface.
    var agentState: AgentState

    /// Information about the detected agent, if any.
    var detectedAgent: DetectedAgent?

    /// Description of the agent's current activity (e.g., "Read: main.swift").
    /// Updated by hook events.
    var agentActivity: String?

    /// Cumulative tool call count from the running agent.
    var agentToolCount: Int

    /// Cumulative error count from the running agent.
    var agentErrorCount: Int

    init(
        agentState: AgentState = .idle,
        detectedAgent: DetectedAgent? = nil,
        agentActivity: String? = nil,
        agentToolCount: Int = 0,
        agentErrorCount: Int = 0
    ) {
        self.agentState = agentState
        self.detectedAgent = detectedAgent
        self.agentActivity = agentActivity
        self.agentToolCount = agentToolCount
        self.agentErrorCount = agentErrorCount
    }

    /// Canonical idle state used as default for surfaces without activity.
    static let idle = SurfaceAgentState()

    /// Whether this surface currently has an agent actively running.
    ///
    /// Returns `true` for states that represent live agent activity:
    /// `.launched`, `.working`, and `.waitingInput`. The `.idle`, `.finished`,
    /// and `.error` states return `false`.
    var isActive: Bool {
        switch agentState {
        case .launched, .working, .waitingInput:
            return true
        case .idle, .finished, .error:
            return false
        }
    }

    /// Whether an agent has been detected in this surface, regardless of
    /// its current lifecycle state.
    var hasAgent: Bool {
        detectedAgent != nil
    }
}
