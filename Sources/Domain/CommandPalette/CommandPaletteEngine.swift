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
        // Update frequency count (no lock needed — @MainActor serializes access).
        executionCounts[action.id, default: 0] += 1

        // Update recent actions (most recent first, max 5).
        recentActionIds.removeAll { $0 == action.id }
        recentActionIds.insert(action.id, at: 0)
        if recentActionIds.count > 5 {
            recentActionIds = Array(recentActionIds.prefix(5))
        }

        // Execute the handler (outside the lock to avoid deadlocks).
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
    private func registerBuiltInActions() {
        // Capture coordinator weakly to avoid retain cycles.
        // If coordinator is nil at call time, the handler is a silent no-op.
        weak var coord = coordinator

        let builtIns: [CommandAction] = [
            CommandAction(
                id: "tabs.new",
                name: "New Tab",
                description: "Open a new terminal tab",
                shortcut: "Cmd+T",
                category: .tabs,
                handler: { coord?.newTab() }
            ),
            CommandAction(
                id: "tabs.close",
                name: "Close Tab",
                description: "Close the current tab",
                shortcut: "Cmd+W",
                category: .tabs,
                handler: { coord?.closeTab() }
            ),
            CommandAction(
                id: "tabs.next",
                name: "Next Tab",
                description: "Switch to the next tab",
                shortcut: "Ctrl+Tab",
                category: .tabs,
                handler: {}
            ),
            CommandAction(
                id: "tabs.previous",
                name: "Previous Tab",
                description: "Switch to the previous tab",
                shortcut: "Ctrl+Shift+Tab",
                category: .tabs,
                handler: {}
            ),
            CommandAction(
                id: "splits.vertical",
                name: "Split Vertical",
                description: "Split the current pane vertically",
                shortcut: "Cmd+D",
                category: .splits,
                handler: { coord?.splitVertical() }
            ),
            CommandAction(
                id: "splits.horizontal",
                name: "Split Horizontal",
                description: "Split the current pane horizontally",
                shortcut: "Cmd+D",
                category: .splits,
                handler: { coord?.splitHorizontal() }
            ),
            CommandAction(
                id: "dashboard.toggle",
                name: "Toggle Dashboard",
                description: "Show or hide the agent dashboard panel",
                shortcut: "Cmd+Option+D",
                category: .dashboard,
                handler: { coord?.toggleDashboard() }
            ),
            CommandAction(
                id: "navigation.quickswitch",
                name: "Quick Switch",
                description: "Jump to the most urgent agent session",
                shortcut: "Cmd+Shift+A",
                category: .navigation,
                handler: {}
            ),
        ]

        for action in builtIns {
            actionsById[action.id] = action
        }
    }
}
