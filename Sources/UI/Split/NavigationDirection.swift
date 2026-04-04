// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NavigationDirection.swift - Directional navigation between split panes.

import Foundation

// MARK: - Navigation Direction

/// Direction for navigating between split panes.
///
/// Used by `SplitNavigator` to determine which neighbor leaf to move
/// focus to relative to the currently focused leaf.
///
/// - SeeAlso: `SplitNavigator`
/// - SeeAlso: `SplitManager.navigateInDirection(_:)`
enum NavigationDirection: Sendable {
    /// Navigate to the pane on the left.
    case left
    /// Navigate to the pane on the right.
    case right
    /// Navigate to the pane above.
    case up
    /// Navigate to the pane below.
    case down

    /// Parses the CLI/socket representation of a navigation direction.
    init?(commandValue rawValue: String) {
        switch rawValue.lowercased() {
        case "left":
            self = .left
        case "right":
            self = .right
        case "up":
            self = .up
        case "down":
            self = .down
        default:
            return nil
        }
    }
}

// MARK: - Split Keyboard Action

/// Actions that can be triggered by keyboard shortcuts on splits.
///
/// Maps 1:1 to the documented keyboard shortcuts:
/// - Cmd+D: splitHorizontal
/// - Cmd+Shift+D: splitVertical
/// - Cmd+Option+Arrow: navigate{Left,Right,Up,Down}
/// - Cmd+Shift+W: closeActiveSplit
enum SplitKeyboardAction: Sendable {
    case splitHorizontal
    case splitVertical
    case splitWithBrowser
    case splitWithMarkdown
    case navigateLeft
    case navigateRight
    case navigateUp
    case navigateDown
    case closeActiveSplit
    case equalizeSplits
    case toggleZoom
}
