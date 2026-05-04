// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateAccessibility.swift - VoiceOver descriptions for agent states.

// MARK: - AgentState Accessibility Extension

/// Provides human-readable descriptions of agent states for VoiceOver.
///
/// These descriptions are used by `AgentStateIndicator` and `TabItemView`
/// to communicate the current agent status to assistive technology users.
///
/// Each description is written from the user's perspective:
/// - `agentState.accessibility.idle`: "No agent active" (not "idle state")
/// - `agentState.accessibility.waitingInput`: "Agent needs your input" (not "waiting for input")
///
/// - SeeAlso: `AgentStateIndicator` for the visual indicator.
/// - SeeAlso: `TabItemView` for the tab item accessibility value.
extension AgentState {

    /// A human-readable description of this agent state for VoiceOver.
    ///
    /// Used as the `accessibilityValue` on tab items and the
    /// `accessibilityLabel` on agent state indicators.
    var accessibilityDescription: String {
        accessibilityDescription(using: AppLocalizer(languagePreference: .english))
    }

    /// A localized human-readable description of this agent state for VoiceOver.
    func accessibilityDescription(using localizer: AppLocalizer) -> String {
        switch self {
        case .idle:
            return localizer.string("agentState.accessibility.idle", fallback: "No agent active")
        case .launched:
            return localizer.string("agentState.accessibility.launched", fallback: "Agent launched")
        case .working:
            return localizer.string("agentState.accessibility.working", fallback: "Agent is working")
        case .waitingInput:
            return localizer.string("agentState.accessibility.waitingInput", fallback: "Agent needs your input")
        case .finished:
            return localizer.string("agentState.accessibility.finished", fallback: "Agent completed task")
        case .error:
            return localizer.string("agentState.accessibility.error", fallback: "Agent encountered an error")
        }
    }
}
