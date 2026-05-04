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
    case worktree   = "Worktree"
    case editor     = "Editor"

    func localizedTitle(using localizer: AppLocalizer) -> String {
        let key = "command.category.\(rawValue.lowercased())"
        return localizer.string(key, fallback: rawValue)
    }
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

    func localized(using localizer: AppLocalizer) -> CommandAction {
        if let editorDisplayName = dynamicEditorDisplayName {
            return CommandAction(
                id: id,
                name: String(
                    format: localizer.string(
                        "command.editor.openNamed.name",
                        fallback: "Open Workspace in %@"
                    ),
                    editorDisplayName
                ),
                description: String(
                    format: localizer.string(
                        "command.editor.openNamed.description",
                        fallback: "Open the active tab's workspace using %@"
                    ),
                    editorDisplayName
                ),
                shortcut: shortcut,
                category: category,
                handler: handler
            )
        }

        let nameKey = "command.\(id).name"
        return CommandAction(
            id: id,
            name: localizer.string(nameKey, fallback: name),
            description: localizer.string(localizedDescriptionKey, fallback: description),
            shortcut: shortcut,
            category: category,
            handler: handler
        )
    }

    private var localizedDescriptionKey: String {
        if id == "window.pictureInPicture" {
            if description.hasPrefix("Enable [experimental].pip-enabled") {
                return "command.window.pictureInPicture.description.disabled"
            }
            return "command.window.pictureInPicture.description.enabled"
        }
        return "command.\(id).description"
    }

    private var dynamicEditorDisplayName: String? {
        guard id.hasPrefix("editor.open."), id != "editor.openDefault" else { return nil }
        let namePrefix = "Open Workspace in "
        if name.hasPrefix(namePrefix) {
            return String(name.dropFirst(namePrefix.count))
        }
        let descriptionPrefix = "Open the active tab's workspace using "
        if description.hasPrefix(descriptionPrefix) {
            return String(description.dropFirst(descriptionPrefix.count))
        }
        return nil
    }
}
