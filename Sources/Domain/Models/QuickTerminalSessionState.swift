// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalSessionState.swift - Serializable state for the quick terminal.

import Foundation

// MARK: - Quick Terminal Session State

/// Captures the quick terminal's state for session persistence.
///
/// Stored as part of the overall session when saving, and applied
/// during restoration to bring the quick terminal back to its previous
/// configuration (position, size, visibility).
///
/// - SeeAlso: `QuickTerminalViewModel` for the runtime counterpart.
/// - SeeAlso: `SessionRestorer` for how this is used during restore.
struct QuickTerminalSessionState: Codable, Sendable, Equatable {
    /// Whether the quick terminal was visible when the session was saved.
    let isVisible: Bool
    /// The working directory of the quick terminal.
    let workingDirectory: String
    /// The height (or width, for left/right positions) as a fraction of the screen.
    let heightPercent: Double
    /// The screen edge from which the panel slides in.
    let position: QuickTerminalPosition

    /// Default state: hidden, home directory, 40% height, top edge.
    static var defaults: QuickTerminalSessionState {
        QuickTerminalSessionState(
            isVisible: false,
            workingDirectory: "~",
            heightPercent: 0.4,
            position: .top
        )
    }
}
