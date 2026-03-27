// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardStateIndicator.swift - Visual mapping for dashboard agent states.

import Foundation

// MARK: - Dashboard State Indicator

/// Maps `AgentDashboardState` to visual properties for the dashboard panel.
///
/// Provides static methods that return semantic color names and SF Symbol names
/// for each state. The SwiftUI views use these to render the colored indicator
/// dot next to each session row.
///
/// ## Color Mapping
///
/// | State          | Color          | Meaning                |
/// |----------------|----------------|------------------------|
/// | working        | systemGreen    | Actively processing    |
/// | waitingForInput| systemOrange   | Needs user attention   |
/// | blocked        | systemRed      | Blocked by error/perm  |
/// | error          | systemRed      | Fatal error            |
/// | idle           | tertiaryLabel  | No activity            |
/// | finished       | tertiaryLabel  | Task completed         |
/// | launching      | systemBlue     | Starting up            |
///
/// - SeeAlso: `DashboardSessionRow` (consumer)
/// - SeeAlso: `AgentDashboardState` (domain enum)
enum DashboardStateIndicator {

    /// Returns the semantic color name for a dashboard state.
    ///
    /// - Parameter state: The agent dashboard state.
    /// - Returns: A string color name usable with `NSColor` or `Color` lookup.
    static func colorName(for state: AgentDashboardState) -> String {
        switch state {
        case .working:
            return "systemGreen"
        case .waitingForInput:
            return "systemOrange"
        case .blocked, .error:
            return "systemRed"
        case .idle, .finished:
            return "tertiaryLabel"
        case .launching:
            return "systemBlue"
        }
    }

    /// Returns the SF Symbol name for a dashboard state.
    ///
    /// - Parameter state: The agent dashboard state.
    /// - Returns: An SF Symbol name suitable for `Image(systemName:)`.
    static func symbol(for state: AgentDashboardState) -> String {
        switch state {
        case .working, .launching:
            return "circle.fill"
        case .waitingForInput:
            return "circle.badge.questionmark.fill"
        case .blocked, .error:
            return "exclamationmark.circle.fill"
        case .idle, .finished:
            return "circle"
        }
    }

    /// Returns a human-readable label for a dashboard state.
    ///
    /// Used for accessibility and tooltips.
    ///
    /// - Parameter state: The agent dashboard state.
    /// - Returns: A descriptive label in English.
    static func accessibilityLabel(for state: AgentDashboardState) -> String {
        switch state {
        case .working:
            return "Working"
        case .waitingForInput:
            return "Waiting for input"
        case .blocked:
            return "Blocked"
        case .error:
            return "Error"
        case .idle:
            return "Idle"
        case .finished:
            return "Finished"
        case .launching:
            return "Launching"
        }
    }
}
