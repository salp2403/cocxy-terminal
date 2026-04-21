// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandAction.swift - Domain models for the Command Palette.

import Foundation

// MARK: - Command Category

/// Categories for organizing commands in the palette.
///
/// Each module registers its actions under the appropriate category.
/// The palette UI can group or filter by category.
///
/// - SeeAlso: ADR-008 Section 3.2
enum CommandCategory: String, Codable, Sendable, CaseIterable {
    case tabs       = "Tabs"
    case splits     = "Splits"
    case navigation = "Navigation"
    case agent      = "Agent"
    case dashboard  = "Dashboard"
    case search     = "Search"
    case theme      = "Theme"
    case config     = "Config"
    case cli        = "CLI"
}

// MARK: - Command Action

/// A single action executable from the command palette.
///
/// Each action has a unique identifier, a human-readable name and description,
/// an optional keyboard shortcut, a category for grouping, and a handler
/// closure that executes the action.
///
/// Actions are runtime-only (not Codable) because the handler closure
/// cannot be serialized.
///
/// - SeeAlso: ADR-008 Section 3.2
struct CommandAction: Identifiable, Sendable {
    /// Unique identifier for this action (e.g., "tabs.new", "splits.vertical").
    let id: String

    /// Display name shown in the palette (e.g., "Split Side by Side").
    let name: String

    /// Short description of what the action does.
    let description: String

    /// Keyboard shortcut string, if any (e.g., "Cmd+D").
    let shortcut: String?

    /// Category for grouping in the palette UI.
    let category: CommandCategory

    /// The closure to execute when the action is selected.
    ///
    /// Handlers run on the MainActor since command actions typically
    /// trigger UI mutations (new tab, split, theme change, etc.).
    let handler: @MainActor @Sendable () -> Void
}
