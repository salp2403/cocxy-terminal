// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateAccessibility.swift - VoiceOver descriptions for agent states.

// MARK: - AgentState Accessibility Extension

/// Provides human-readable descriptions of agent states for VoiceOver.
///
/// These descriptions are used by `AgentStateIndicator` and `TabItemView`
/// to communicate the current agent status to assistive technology users.
///
/// Each description is written from the user's perspective:
/// - "No agent active" (not "idle state")
/// - "Agent needs your input" (not "waiting for input")
///
/// - SeeAlso: `AgentStateIndicator` for the visual indicator.
/// - SeeAlso: `TabItemView` for the tab item accessibility value.
extension AgentState {

    /// A human-readable description of this agent state for VoiceOver.
    ///
    /// Used as the `accessibilityValue` on tab items and the
    /// `accessibilityLabel` on agent state indicators.
    var accessibilityDescription: String {
        switch self {
        case .idle:
            return "No agent active"
        case .launched:
            return "Agent launched"
        case .working:
            return "Agent is working"
        case .waitingInput:
            return "Agent needs your input"
        case .finished:
            return "Agent completed task"
        case .error:
            return "Agent encountered an error"
        }
    }
}
