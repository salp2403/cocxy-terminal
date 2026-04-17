// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStatusTextFormatter.swift - Pure formatting helpers for the status
// bar agent indicator used by Fase 3 so the text generation logic can be
// unit-tested without booting AppKit.

import Foundation

/// Pure formatting helpers that translate an agent's current state into
/// the short human-readable string shown in the status bar.
///
/// The status bar reads its input from the per-surface store via the
/// `SurfaceAgentStateResolver`, then feeds the resolved state into this
/// formatter. Keeping the text generation in a pure namespace means the
/// formatter is testable in isolation and the bar extension stays focused
/// on wiring (colors, layout, vibrancy).
enum AgentStatusTextFormatter {

    /// Builds the status-bar text for a running agent.
    ///
    /// - Parameters:
    ///   - state: Current agent state of the surface that feeds the
    ///     indicator.
    ///   - agentName: Display name already resolved by the caller. Use
    ///     `DetectedAgent.displayName` first, `Tab.processName` next, and
    ///     the literal `"Agent"` as a last-resort label.
    ///   - agentActivity: Optional description of the current tool call
    ///     or activity (e.g. `"Read: main.swift"`). Only consulted when
    ///     the state is `.working`.
    /// - Returns: The status text, or `nil` when the indicator should
    ///   stay hidden (either `.idle` or the activity string was empty).
    static func activeAgentStatusText(
        state: AgentState,
        agentName: String,
        agentActivity: String?
    ) -> String? {
        let text: String
        switch state {
        case .launched:
            text = "\(agentName) starting..."
        case .working:
            if let activity = agentActivity?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !activity.isEmpty {
                text = activity
            } else {
                text = "\(agentName) working"
            }
        case .waitingInput:
            text = "\(agentName) waiting for input"
        case .finished:
            text = "\(agentName) finished"
        case .error:
            text = "\(agentName) error"
        case .idle:
            return nil
        }
        return text.isEmpty ? nil : text
    }

    /// Categorizes a state into the three counter buckets shown in the
    /// status bar summary.
    ///
    /// `.launched` collapses into `.working` because the status bar does
    /// not expose a separate launching bucket, mirroring the historical
    /// behavior of the indicator.
    ///
    /// - Parameter state: Agent state of the surface being counted.
    /// - Returns: The counter bucket the state contributes to, or `nil`
    ///   when the state does not add to any counter (`.idle`).
    static func counterBucket(for state: AgentState) -> CounterBucket? {
        switch state {
        case .working, .launched:
            return .working
        case .waitingInput:
            return .waiting
        case .error:
            return .errors
        case .finished:
            return .finished
        case .idle:
            return nil
        }
    }

    /// Summary counter buckets. One value per bucket keeps the mapping
    /// exhaustive and avoids silent drift when a new `AgentState` case is
    /// added.
    enum CounterBucket: Equatable, Sendable {
        case working
        case waiting
        case errors
        case finished
    }
}
