// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// StaticCommandPaletteEngine.swift - Immutable command palette engine for transient overlays.

import Foundation

/// Lightweight palette engine for one-shot overlays whose actions are
/// rebuilt from live app state right before presentation.
///
/// The regular `CommandPaletteEngineImpl` owns recents, execution
/// counters, and the global command catalogue. Unified QuickSwitch
/// needs a narrower surface: only switch targets, ranked by the
/// cross-surface ranker, with no mutation of global palette recents.
final class StaticCommandPaletteEngine: CommandPaletteSearching, @unchecked Sendable {
    private let actions: [CommandAction]

    init(actions: [CommandAction]) {
        self.actions = actions
    }

    var allActions: [CommandAction] { actions }

    var recentActions: [CommandAction] { [] }

    func search(query: String) -> [CommandAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }

        return actions.compactMap { action -> (CommandAction, Int)? in
            let targets = [action.name, action.description, action.category.rawValue]
            let score = targets.compactMap {
                FuzzyMatcher.fuzzyMatch(query: trimmed, target: $0)?.score
            }.max()
            return score.map { (action, $0) }
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name < rhs.0.name
        }
        .map(\.0)
    }

    func registerAction(_ action: CommandAction) {}

    func registerActions(_ actions: [CommandAction]) {}

    @MainActor
    func execute(_ action: CommandAction) {
        action.handler()
    }
}
