// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ResizeOverlayState.swift - State for the resize dimensions overlay.

import Foundation

// MARK: - Resize Overlay State

/// Tracks the visibility and content of the terminal resize overlay.
///
/// During a live window resize, the terminal briefly shows the current
/// dimensions (e.g., "80x24") as a semi-transparent overlay. This state
/// drives that overlay.
///
/// The overlay auto-hides after a configurable delay (typically 1 second)
/// once the resize ends.
struct ResizeOverlayState: Sendable {

    /// Whether the overlay is currently visible.
    private(set) var isVisible: Bool = false

    /// Number of terminal columns.
    private(set) var columns: UInt16 = 0

    /// Number of terminal rows.
    private(set) var rows: UInt16 = 0

    /// The display string shown in the overlay (e.g., "80x24").
    var displayString: String {
        "\(columns)x\(rows)"
    }

    /// Shows the overlay with the given terminal dimensions.
    ///
    /// - Parameters:
    ///   - columns: Current number of character columns.
    ///   - rows: Current number of character rows.
    mutating func show(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
        self.isVisible = true
    }

    /// Hides the overlay.
    mutating func hide() {
        isVisible = false
    }
}
