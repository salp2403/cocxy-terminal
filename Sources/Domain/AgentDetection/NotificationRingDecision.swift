// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotificationRingDecision.swift - Pure decision enum for the per-surface
// notification ring used by Fase 3 to decide whether an individual split
// pane should pulse while an agent is waiting on user input.

import Foundation

/// Whether the notification ring for a single surface should be shown or
/// hidden at a given point in time.
///
/// The decision is pure: given the agent state of a surface, whether its
/// owning tab is currently displayed, and whether the surface itself has
/// keyboard focus, the enum picks the correct action. This keeps the
/// display logic unit-testable without booting AppKit.
///
/// Invariant: the ring never pulses on a surface that the user is
/// actively looking at (owning tab displayed **and** surface focused).
/// Every other combination that reports `.waitingInput` pulses — so
/// background tabs, background splits of the active tab, and
/// unfocused-but-visible splits all surface the waiting signal.
enum NotificationRingDecision: Equatable, Sendable {

    /// Turn the ring on (or keep it on).
    case show

    /// Turn the ring off (or keep it off).
    case hide

    /// Pure decision entry point.
    ///
    /// - Parameters:
    ///   - agentState: Current agent state of the surface.
    ///   - isTabVisible: Whether the owning tab is the displayed tab
    ///     right now.
    ///   - isSurfaceFocused: Whether the surface itself currently owns
    ///     the first-responder focus inside the displayed tab. Ignored
    ///     when `isTabVisible` is `false`.
    /// - Returns: `.show` when the ring should pulse, `.hide` otherwise.
    static func decide(
        agentState: AgentState,
        isTabVisible: Bool,
        isSurfaceFocused: Bool
    ) -> NotificationRingDecision {
        guard agentState == .waitingInput else {
            return .hide
        }
        if isTabVisible && isSurfaceFocused {
            return .hide
        }
        return .show
    }
}
