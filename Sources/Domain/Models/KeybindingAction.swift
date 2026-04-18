// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingAction.swift - Canonical catalog of user-visible keyboard actions.

import Foundation

// MARK: - Category

/// Logical grouping used to section the Keybindings editor UI.
///
/// Order reflects display order: window-level actions first, then editing-like
/// actions (tabs, splits, navigation), domain panels (review, markdown),
/// remote workspace features, and a catch-all `misc` bucket at the end.
enum KeybindingCategory: String, CaseIterable, Identifiable, Sendable {
    case window
    case tab
    case split
    case navigation
    case editor
    case review
    case markdown
    case remote
    case misc

    var id: String { rawValue }

    /// User-facing title shown as the section header in the editor.
    var title: String {
        switch self {
        case .window: return "Window"
        case .tab: return "Tabs"
        case .split: return "Splits"
        case .navigation: return "Navigation"
        case .editor: return "Editor"
        case .review: return "Review"
        case .markdown: return "Markdown"
        case .remote: return "Remote"
        case .misc: return "Other"
        }
    }
}

// MARK: - Keybinding Action

/// A single user-rebindable action surfaced in the Keybindings editor.
///
/// Each entry pairs a stable dotted identifier (used in `config.toml`) with
/// a display name, category, and a default shortcut. The catalog is the
/// canonical source of truth — adding or removing entries here is the only
/// place needed to expose a new rebindable action to the editor.
///
/// - Note: The identifier is stable and used as a TOML key
///   (`[keybindings] "split.horizontal" = "cmd+d"`). Once shipped,
///   identifiers must not change without a migration path.
struct KeybindingAction: Identifiable, Sendable, Equatable {

    /// Stable dotted identifier, persisted in `config.toml`.
    ///
    /// Examples: `"tab.new"`, `"split.horizontal"`, `"window.commandPalette"`.
    let id: String

    /// Human-readable name shown in the editor row.
    let displayName: String

    /// One-line explanation shown as secondary text or a tooltip.
    let summary: String

    /// Category the row lives under.
    let category: KeybindingCategory

    /// Factory default shortcut. Never mutated at runtime.
    let defaultShortcut: KeybindingShortcut

    // MARK: - Lookup

    /// Returns the catalog entry for the given id, or `nil` when unknown.
    static func catalogEntry(for id: String) -> KeybindingAction? {
        KeybindingActionCatalog.all.first { $0.id == id }
    }
}

// MARK: - Catalog

/// Static registry of every rebindable action the Keybindings editor knows
/// about.
///
/// The shortcut strings listed here mirror the shortcuts currently emitted by
/// `AppDelegate+MenuSetup` and `MainWindowController` so the defaults match
/// what the app ships with. When a new shortcut is added to the menu, add a
/// matching entry here.
///
/// The editor displays these in the order they appear below (grouped by
/// `category`); ordering within a category is preserved.
enum KeybindingActionCatalog {

    // MARK: - Window

    static let windowNewWindow = KeybindingAction(
        id: "window.new",
        displayName: "New Window",
        summary: "Open a new Cocxy Terminal window.",
        category: .window,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "n")
    )

    static let windowMinimize = KeybindingAction(
        id: "window.minimize",
        displayName: "Minimize Window",
        summary: "Minimize the active window to the Dock.",
        category: .window,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "m")
    )

    static let windowToggleFullScreen = KeybindingAction(
        id: "window.toggleFullScreen",
        displayName: "Toggle Full Screen",
        summary: "Enter or leave full-screen mode.",
        category: .window,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresControl: true, baseKey: "f")
    )

    static let windowCommandPalette = KeybindingAction(
        id: "window.commandPalette",
        displayName: "Command Palette",
        summary: "Open the searchable command palette.",
        category: .window,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "p")
    )

    static let windowPreferences = KeybindingAction(
        id: "window.preferences",
        displayName: "Settings",
        summary: "Open the Preferences window.",
        category: .window,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: ",")
    )

    static let windowQuickTerminal = KeybindingAction(
        id: "window.quickTerminal",
        displayName: "Toggle Quick Terminal",
        summary: "Slide the quick terminal in or out.",
        category: .window,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "grave")
    )

    // MARK: - Tab

    static let tabNew = KeybindingAction(
        id: "tab.new",
        displayName: "New Tab",
        summary: "Open a new terminal tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "t")
    )

    static let tabClose = KeybindingAction(
        id: "tab.close",
        displayName: "Close Tab",
        summary: "Close the active tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "w")
    )

    static let tabNext = KeybindingAction(
        id: "tab.next",
        displayName: "Next Tab",
        summary: "Switch to the next tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "]")
    )

    static let tabPrevious = KeybindingAction(
        id: "tab.previous",
        displayName: "Previous Tab",
        summary: "Switch to the previous tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "[")
    )

    static let tabMoveToNewWindow = KeybindingAction(
        id: "tab.moveToNewWindow",
        displayName: "Move Tab to New Window",
        summary: "Detach the active tab into its own window.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(
            requiresCommand: true,
            requiresControl: true,
            requiresShift: true,
            baseKey: "n"
        )
    )

    static let tabGoto1 = KeybindingAction(
        id: "tab.goto1",
        displayName: "Go to Tab 1",
        summary: "Switch to the first tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "1")
    )

    static let tabGoto2 = KeybindingAction(
        id: "tab.goto2",
        displayName: "Go to Tab 2",
        summary: "Switch to the second tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "2")
    )

    static let tabGoto3 = KeybindingAction(
        id: "tab.goto3",
        displayName: "Go to Tab 3",
        summary: "Switch to the third tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "3")
    )

    static let tabGoto4 = KeybindingAction(
        id: "tab.goto4",
        displayName: "Go to Tab 4",
        summary: "Switch to the fourth tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "4")
    )

    static let tabGoto5 = KeybindingAction(
        id: "tab.goto5",
        displayName: "Go to Tab 5",
        summary: "Switch to the fifth tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "5")
    )

    static let tabGoto6 = KeybindingAction(
        id: "tab.goto6",
        displayName: "Go to Tab 6",
        summary: "Switch to the sixth tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "6")
    )

    static let tabGoto7 = KeybindingAction(
        id: "tab.goto7",
        displayName: "Go to Tab 7",
        summary: "Switch to the seventh tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "7")
    )

    static let tabGoto8 = KeybindingAction(
        id: "tab.goto8",
        displayName: "Go to Tab 8",
        summary: "Switch to the eighth tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "8")
    )

    static let tabGoto9 = KeybindingAction(
        id: "tab.goto9",
        displayName: "Go to Tab 9",
        summary: "Switch to the ninth tab.",
        category: .tab,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "9")
    )

    // MARK: - Split

    static let splitVertical = KeybindingAction(
        id: "split.vertical",
        displayName: "Split Vertical",
        summary: "Split the active pane into a new column.",
        category: .split,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "d")
    )

    static let splitHorizontal = KeybindingAction(
        id: "split.horizontal",
        displayName: "Split Horizontal",
        summary: "Split the active pane into a new row.",
        category: .split,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "d")
    )

    static let splitClose = KeybindingAction(
        id: "split.close",
        displayName: "Close Split",
        summary: "Close the focused split pane.",
        category: .split,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "w")
    )

    static let splitEqualize = KeybindingAction(
        id: "split.equalize",
        displayName: "Equalize Splits",
        summary: "Resize all splits to be equal.",
        category: .split,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "e")
    )

    static let splitToggleZoom = KeybindingAction(
        id: "split.toggleZoom",
        displayName: "Toggle Split Zoom",
        summary: "Temporarily fill the window with the focused split.",
        category: .split,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "f")
    )

    // MARK: - Navigation

    static let navigateSplitLeft = KeybindingAction(
        id: "navigation.splitLeft",
        displayName: "Navigate Split Left",
        summary: "Move focus to the split on the left.",
        category: .navigation,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "left")
    )

    static let navigateSplitRight = KeybindingAction(
        id: "navigation.splitRight",
        displayName: "Navigate Split Right",
        summary: "Move focus to the split on the right.",
        category: .navigation,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "right")
    )

    static let navigateSplitUp = KeybindingAction(
        id: "navigation.splitUp",
        displayName: "Navigate Split Up",
        summary: "Move focus to the split above.",
        category: .navigation,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "up")
    )

    static let navigateSplitDown = KeybindingAction(
        id: "navigation.splitDown",
        displayName: "Navigate Split Down",
        summary: "Move focus to the split below.",
        category: .navigation,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "down")
    )

    // MARK: - Editor (view actions: find, zoom)

    static let editorFind = KeybindingAction(
        id: "editor.find",
        displayName: "Find",
        summary: "Open the terminal search bar.",
        category: .editor,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "f")
    )

    static let editorZoomIn = KeybindingAction(
        id: "editor.zoomIn",
        displayName: "Zoom In",
        summary: "Increase font size.",
        category: .editor,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "plus")
    )

    static let editorZoomOut = KeybindingAction(
        id: "editor.zoomOut",
        displayName: "Zoom Out",
        summary: "Decrease font size.",
        category: .editor,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "minus")
    )

    static let editorResetZoom = KeybindingAction(
        id: "editor.resetZoom",
        displayName: "Reset Zoom",
        summary: "Restore the default font size.",
        category: .editor,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, baseKey: "0")
    )

    // MARK: - Review

    static let reviewDashboard = KeybindingAction(
        id: "review.dashboard",
        displayName: "Toggle Dashboard",
        summary: "Show or hide the agent dashboard panel.",
        category: .review,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "a")
    )

    static let reviewCodeReview = KeybindingAction(
        id: "review.codeReview",
        displayName: "Toggle Code Review",
        summary: "Show or hide the agent code review panel.",
        category: .review,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "r")
    )

    static let reviewTimeline = KeybindingAction(
        id: "review.timeline",
        displayName: "Toggle Timeline",
        summary: "Show or hide the agent timeline panel.",
        category: .review,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "t")
    )

    static let reviewNotifications = KeybindingAction(
        id: "review.notifications",
        displayName: "Toggle Notifications",
        summary: "Show or hide the notification panel.",
        category: .review,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "i")
    )

    // MARK: - Markdown

    static let markdownBrowser = KeybindingAction(
        id: "markdown.browser",
        displayName: "Toggle Browser",
        summary: "Show or hide the inline browser panel.",
        category: .markdown,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "b")
    )

    // MARK: - Remote

    static let remoteGoToAttention = KeybindingAction(
        id: "remote.gotoAttention",
        displayName: "Go to Attention",
        summary: "Jump to the next session waiting for attention.",
        category: .remote,
        defaultShortcut: KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "u")
    )

    // MARK: - Assembly

    /// Every action the editor knows about, in display order.
    static let all: [KeybindingAction] = [
        // Window
        windowNewWindow,
        windowMinimize,
        windowToggleFullScreen,
        windowCommandPalette,
        windowPreferences,
        windowQuickTerminal,
        // Tab
        tabNew,
        tabClose,
        tabNext,
        tabPrevious,
        tabMoveToNewWindow,
        tabGoto1, tabGoto2, tabGoto3,
        tabGoto4, tabGoto5, tabGoto6,
        tabGoto7, tabGoto8, tabGoto9,
        // Split
        splitHorizontal,
        splitVertical,
        splitClose,
        splitEqualize,
        splitToggleZoom,
        // Navigation
        navigateSplitLeft,
        navigateSplitRight,
        navigateSplitUp,
        navigateSplitDown,
        // Editor
        editorFind,
        editorZoomIn,
        editorZoomOut,
        editorResetZoom,
        // Review
        reviewDashboard,
        reviewCodeReview,
        reviewTimeline,
        reviewNotifications,
        // Markdown
        markdownBrowser,
        // Remote
        remoteGoToAttention,
    ]

    /// Actions grouped by category, preserving the order in `all`.
    static let grouped: [(category: KeybindingCategory, actions: [KeybindingAction])] = {
        var buckets: [KeybindingCategory: [KeybindingAction]] = [:]
        for action in all {
            buckets[action.category, default: []].append(action)
        }
        return KeybindingCategory.allCases.compactMap { category in
            guard let actions = buckets[category], !actions.isEmpty else { return nil }
            return (category, actions)
        }
    }()

    /// Mapping from legacy `KeybindingsConfig` field names to catalog ids.
    ///
    /// Used by `KeybindingsConfig.shortcutString(for:)` so pre-existing TOML
    /// shaped around the eight typed fields continues to drive the editor
    /// without requiring migration.
    static let legacyFieldMapping: [String: String] = [
        "new-tab": tabNew.id,
        "close-tab": tabClose.id,
        "next-tab": tabNext.id,
        "prev-tab": tabPrevious.id,
        "split-vertical": splitVertical.id,
        "split-horizontal": splitHorizontal.id,
        "goto-attention": remoteGoToAttention.id,
        "toggle-quick-terminal": windowQuickTerminal.id,
    ]
}
