// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteEngine.swift - Engine for the Command Palette feature.

import Foundation

// MARK: - Command Palette Searching Protocol

/// Contract for the command palette search engine.
///
/// Provides registration, fuzzy search, execution, and usage tracking
/// for command actions. Each module in Cocxy registers its actions
/// via `registerAction` or `registerActions`.
///
/// - SeeAlso: ADR-008 Section 3.3
protocol CommandPaletteSearching: AnyObject, Sendable {
    /// All registered actions, ordered by usage frequency (most used first).
    var allActions: [CommandAction] { get }

    /// Searches registered actions with fuzzy matching.
    ///
    /// - Parameter query: The search string entered by the user.
    /// - Returns: Matched actions ordered by: fuzzy score * frequency boost.
    func search(query: String) -> [CommandAction]

    /// Registers a single action. Overwrites if the ID already exists.
    func registerAction(_ action: CommandAction)

    /// Registers multiple actions at once.
    func registerActions(_ actions: [CommandAction])

    /// Executes an action, tracking it in recents and frequency.
    @MainActor func execute(_ action: CommandAction)

    /// The last 5 executed actions, most recent first.
    var recentActions: [CommandAction] { get }
}

// MARK: - Command Palette Engine Implementation

/// Concrete implementation of `CommandPaletteSearching`.
///
/// Thread-safe via `NSLock` on all mutable state. Registers built-in
/// actions on initialization (tab, split, theme, dashboard).
///
/// ## Scoring
///
/// Search results are ordered by a combined score:
/// - Fuzzy match score (0-100) from `FuzzyMatcher`.
/// - Frequency boost: +1 point per previous execution of the action.
/// - The combined score determines the order of results.
///
/// ## Thread Safety
///
/// All mutable state (`actions`, `executionCounts`, `recentActionIds`)
/// is protected by `NSLock`. Read and write operations acquire the lock.
///
/// - SeeAlso: ADR-008 Section 3.3
final class CommandPaletteEngineImpl: CommandPaletteSearching, @unchecked Sendable {

    private final class WeakCoordinatorBox: @unchecked Sendable {
        weak var coordinator: CommandPaletteCoordinatorImpl?

        init(_ coordinator: CommandPaletteCoordinatorImpl?) {
            self.coordinator = coordinator
        }
    }

    // MARK: - State (lock-protected)

    /// Lock protecting all mutable state.
    private let lock = NSLock()

    /// All registered actions keyed by ID.
    private var actionsById: [String: CommandAction] = [:]

    /// Execution count per action ID (for frequency-based ranking).
    private var executionCounts: [String: Int] = [:]

    /// IDs of recently executed actions, most recent first. Max 5.
    private var recentActionIds: [String] = []

    // MARK: - Dependencies

    /// Optional coordinator for wiring built-in actions to real managers.
    /// When nil, built-in actions are registered as no-ops (safe defaults).
    private weak var coordinator: CommandPaletteCoordinatorImpl?

    // MARK: - Initialization

    /// Creates a new engine with built-in actions registered.
    ///
    /// - Parameter coordinator: Optional coordinator that wires built-in actions
    ///   to real managers (TabManager, SplitManager, etc.). When nil, built-in
    ///   actions are safe no-ops. Defaults to nil for backwards compatibility.
    init(coordinator: CommandPaletteCoordinatorImpl? = nil) {
        self.coordinator = coordinator
        registerBuiltInActions()
    }

    // MARK: - CommandPaletteSearching

    var allActions: [CommandAction] {
        lock.lock()
        defer { lock.unlock() }
        return Array(actionsById.values).sorted { lhs, rhs in
            let lhsCount = executionCounts[lhs.id] ?? 0
            let rhsCount = executionCounts[rhs.id] ?? 0
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            return lhs.name < rhs.name
        }
    }

    func search(query: String) -> [CommandAction] {
        lock.lock()
        let actions = Array(actionsById.values)
        let counts = executionCounts
        lock.unlock()

        if query.isEmpty {
            // Return all actions sorted by frequency.
            return actions.sorted { lhs, rhs in
                let lhsCount = counts[lhs.id] ?? 0
                let rhsCount = counts[rhs.id] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                return lhs.name < rhs.name
            }
        }

        // Fuzzy match each action and collect scored results.
        var scoredResults: [(action: CommandAction, score: Int)] = []

        for action in actions {
            if let matchResult = FuzzyMatcher.fuzzyMatch(query: query, target: action.name) {
                let frequencyBoost = counts[action.id] ?? 0
                let combinedScore = matchResult.score + frequencyBoost
                scoredResults.append((action: action, score: combinedScore))
            }
        }

        // Sort by combined score descending, then name ascending for stability.
        scoredResults.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.action.name < rhs.action.name
        }

        return scoredResults.map { $0.action }
    }

    func registerAction(_ action: CommandAction) {
        lock.lock()
        defer { lock.unlock() }
        actionsById[action.id] = action
    }

    func registerActions(_ actions: [CommandAction]) {
        lock.lock()
        defer { lock.unlock() }
        for action in actions {
            actionsById[action.id] = action
        }
    }

    @MainActor
    func execute(_ action: CommandAction) {
        // Lock protects shared mutable state read by search() from any thread.
        lock.lock()
        executionCounts[action.id, default: 0] += 1
        recentActionIds.removeAll { $0 == action.id }
        recentActionIds.insert(action.id, at: 0)
        if recentActionIds.count > 5 {
            recentActionIds = Array(recentActionIds.prefix(5))
        }
        lock.unlock()

        // Execute outside lock to avoid deadlocks if handler triggers search().
        action.handler()
    }

    var recentActions: [CommandAction] {
        lock.lock()
        let recentIds = recentActionIds
        let actions = actionsById
        lock.unlock()

        return recentIds.compactMap { actions[$0] }
    }

    // MARK: - Built-in Actions

    /// Registers the default set of built-in actions available in every Cocxy session.
    ///
    /// When a coordinator is set, built-in actions delegate to the coordinator's methods.
    /// When the coordinator is nil, handlers are safe no-ops.
    ///
    /// Shortcut labels are resolved from the `KeybindingActionCatalog` defaults.
    /// Live user customizations are applied later via `rebuildBuiltInShortcuts(using:)`
    /// so the palette can surface the same glyph the menu shows.
    private func registerBuiltInActions() {
        let coordinatorBox = WeakCoordinatorBox(coordinator)

        let builtIns: [CommandAction] = [
            CommandAction(
                id: "tabs.new",
                name: "New Tab",
                description: "Open a new terminal tab",
                shortcut: KeybindingActionCatalog.tabNew.defaultShortcut.prettyLabel,
                category: .tabs,
                handler: { coordinatorBox.coordinator?.newTab() }
            ),
            CommandAction(
                id: "tabs.close",
                name: "Close Tab",
                description: "Close the current tab",
                shortcut: KeybindingActionCatalog.tabClose.defaultShortcut.prettyLabel,
                category: .tabs,
                handler: { coordinatorBox.coordinator?.closeTab() }
            ),
            CommandAction(
                id: "tabs.next",
                name: "Next Tab",
                description: "Switch to the next tab",
                shortcut: KeybindingActionCatalog.tabNext.defaultShortcut.prettyLabel,
                category: .tabs,
                handler: { coordinatorBox.coordinator?.nextTab() }
            ),
            CommandAction(
                id: "tabs.previous",
                name: "Previous Tab",
                description: "Switch to the previous tab",
                shortcut: KeybindingActionCatalog.tabPrevious.defaultShortcut.prettyLabel,
                category: .tabs,
                handler: { coordinatorBox.coordinator?.previousTab() }
            ),
            CommandAction(
                id: "splits.vertical",
                name: "Split Stacked",
                description: "Split the current pane into a top/bottom stack",
                shortcut: KeybindingActionCatalog.splitVertical.defaultShortcut.prettyLabel,
                category: .splits,
                handler: { coordinatorBox.coordinator?.splitVertical() }
            ),
            CommandAction(
                id: "splits.horizontal",
                name: "Split Side by Side",
                description: "Split the current pane into left/right columns",
                shortcut: KeybindingActionCatalog.splitHorizontal.defaultShortcut.prettyLabel,
                category: .splits,
                handler: { coordinatorBox.coordinator?.splitHorizontal() }
            ),
            CommandAction(
                id: "dashboard.toggle",
                name: "Toggle Dashboard",
                description: "Show or hide the agent dashboard panel",
                shortcut: KeybindingActionCatalog.reviewDashboard.defaultShortcut.prettyLabel,
                category: .dashboard,
                handler: { coordinatorBox.coordinator?.toggleDashboard() }
            ),
            CommandAction(
                id: "navigation.quickswitch",
                name: "Quick Switch",
                description: "Jump to the most urgent agent session",
                shortcut: KeybindingActionCatalog.remoteGoToAttention.defaultShortcut.prettyLabel,
                category: .navigation,
                handler: { coordinatorBox.coordinator?.performQuickSwitch() }
            ),
            CommandAction(
                id: "worktree.create",
                name: "Create Agent Worktree Tab",
                description: "Create a cocxy-managed git worktree off the active tab's origin repo and attach it to the tab",
                shortcut: nil,
                category: .worktree,
                handler: { coordinatorBox.coordinator?.createWorktreeTab() }
            ),
            CommandAction(
                id: "worktree.remove",
                name: "Remove Current Worktree",
                description: "Remove the cocxy-managed worktree attached to the active tab (refuses when dirty)",
                shortcut: nil,
                category: .worktree,
                handler: { coordinatorBox.coordinator?.removeCurrentWorktree() }
            ),
        ]

        for action in builtIns {
            actionsById[action.id] = action
        }
    }

    // MARK: - Keybindings Hot-Reload

    /// Rebuilds the shortcut labels of the built-in actions using the live
    /// keybindings config.
    ///
    /// Called by `AppDelegate` whenever `ConfigService` publishes a new config
    /// so the command palette shows the same glyph the user sees in the menu
    /// bar. Unknown ids fall back to the catalog default.
    ///
    /// - Parameter keybindings: The current `[keybindings]` snapshot.
    func rebuildBuiltInShortcuts(using keybindings: KeybindingsConfig) {
        let mapping: [(paletteId: String, actionId: String)] = [
            ("window.new", KeybindingActionCatalog.windowNewWindow.id),
            ("window.minimize", KeybindingActionCatalog.windowMinimize.id),
            ("window.fullscreen", KeybindingActionCatalog.windowToggleFullScreen.id),
            ("window.commandPalette", KeybindingActionCatalog.windowCommandPalette.id),
            ("tabs.new", KeybindingActionCatalog.tabNew.id),
            ("tabs.close", KeybindingActionCatalog.tabClose.id),
            ("tabs.next", KeybindingActionCatalog.tabNext.id),
            ("tabs.previous", KeybindingActionCatalog.tabPrevious.id),
            ("tabs.moveToNewWindow", KeybindingActionCatalog.tabMoveToNewWindow.id),
            ("tabs.goto1", KeybindingActionCatalog.tabGoto1.id),
            ("tabs.goto2", KeybindingActionCatalog.tabGoto2.id),
            ("tabs.goto3", KeybindingActionCatalog.tabGoto3.id),
            ("tabs.goto4", KeybindingActionCatalog.tabGoto4.id),
            ("tabs.goto5", KeybindingActionCatalog.tabGoto5.id),
            ("tabs.goto6", KeybindingActionCatalog.tabGoto6.id),
            ("tabs.goto7", KeybindingActionCatalog.tabGoto7.id),
            ("tabs.goto8", KeybindingActionCatalog.tabGoto8.id),
            ("tabs.goto9", KeybindingActionCatalog.tabGoto9.id),
            ("splits.vertical", KeybindingActionCatalog.splitVertical.id),
            ("splits.horizontal", KeybindingActionCatalog.splitHorizontal.id),
            ("splits.close", KeybindingActionCatalog.splitClose.id),
            ("splits.equalize", KeybindingActionCatalog.splitEqualize.id),
            ("splits.zoom", KeybindingActionCatalog.splitToggleZoom.id),
            ("navigation.splitLeft", KeybindingActionCatalog.navigateSplitLeft.id),
            ("navigation.splitRight", KeybindingActionCatalog.navigateSplitRight.id),
            ("navigation.splitUp", KeybindingActionCatalog.navigateSplitUp.id),
            ("navigation.splitDown", KeybindingActionCatalog.navigateSplitDown.id),
            ("dashboard.toggle", KeybindingActionCatalog.reviewDashboard.id),
            ("agent.review", KeybindingActionCatalog.reviewCodeReview.id),
            ("timeline.toggle", KeybindingActionCatalog.reviewTimeline.id),
            ("search.toggle", KeybindingActionCatalog.editorFind.id),
            ("editor.zoomIn", KeybindingActionCatalog.editorZoomIn.id),
            ("editor.zoomOut", KeybindingActionCatalog.editorZoomOut.id),
            ("editor.resetZoom", KeybindingActionCatalog.editorResetZoom.id),
            ("preferences.show", KeybindingActionCatalog.windowPreferences.id),
            ("notifications.toggle", KeybindingActionCatalog.reviewNotifications.id),
            ("browser.toggle", KeybindingActionCatalog.markdownBrowser.id),
            ("navigation.quickswitch", KeybindingActionCatalog.remoteGoToAttention.id),
            ("navigation.quickterminal", KeybindingActionCatalog.windowQuickTerminal.id),
        ]

        lock.lock()
        defer { lock.unlock() }

        for (paletteId, actionId) in mapping {
            guard let existing = actionsById[paletteId] else { continue }
            let raw = keybindings.shortcutString(for: actionId)
            let label: String?
            if raw.isEmpty {
                label = nil
            } else if let parsed = KeybindingShortcut.parse(raw) {
                label = parsed.prettyLabel
            } else {
                label = existing.shortcut    // keep previous on parse failure
            }

            actionsById[paletteId] = CommandAction(
                id: existing.id,
                name: existing.name,
                description: existing.description,
                shortcut: label,
                category: existing.category,
                handler: existing.handler
            )
        }
    }
}
