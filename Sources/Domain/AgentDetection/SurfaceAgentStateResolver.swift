// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceAgentStateResolver.swift - Pure resolver used by Fase 3 UI consumers
// to pick the best per-surface agent state for a tab-scoped indicator, with
// a Tab-level fallback as safety net during the dual-write migration.

import Foundation

// MARK: - Tab Fallback Convenience

extension SurfaceAgentState {

    /// Builds a `SurfaceAgentState` snapshot from the legacy tab-level
    /// fields.
    ///
    /// Used as a safety net during the Fase 3 migration: UI consumers that
    /// start reading from `AgentStatePerSurfaceStore` fall back to this
    /// snapshot whenever the store has no entry for the resolved surface.
    /// This preserves the pre-refactor visual behavior and guarantees that
    /// a missing store entry never results in a blank indicator.
    ///
    /// The dual-write pattern installed in Fase 2 (`AgentWiring`) keeps
    /// `Tab` and the store in sync, so the fallback is always a truthful
    /// snapshot of the same information the store would have held.
    init(from tab: Tab) {
        self.init(
            agentState: tab.agentState,
            detectedAgent: tab.detectedAgent,
            agentActivity: tab.agentActivity,
            agentToolCount: tab.agentToolCount,
            agentErrorCount: tab.agentErrorCount
        )
    }
}

// MARK: - Resolver

/// Resolves the `SurfaceAgentState` that drives tab-scoped UI indicators
/// (agent progress overlay, status bar, sidebar pill) during the Fase 3
/// migration from tab-level fields to a per-surface store.
///
/// The resolver is an `enum` namespace with static entry points so it can
/// be unit-tested as a plain value without booting AppKit or SwiftUI.
///
/// ## Priority Chain
///
/// 1. **Focused split surface** — when the owning tab is displayed and the
///    user is typing in a split pane, the focused pane wins so live
///    activity is what the indicator reflects.
/// 2. **Primary surface** — the tab's own terminal (`tabSurfaceMap[tabID]`),
///    used when no split is focused or the focused split is idle.
/// 3. **Any other surface with activity** — any other surface registered
///    for the tab (splits, restored splits, background surfaces) whose
///    state reports `isActive || hasAgent`. Caller ordering is preserved.
/// 4. **Tab fallback** — synthesize a `SurfaceAgentState` from the legacy
///    tab-level fields. Always safe: the dual-write keeps `Tab` aligned
///    with the store.
///
/// A surface is considered "with activity" when its state is `.launched`,
/// `.working`, or `.waitingInput` (`isActive`), or when it has a detected
/// agent attached (`hasAgent`). This keeps finished-with-agent surfaces
/// visible as "activity" so the indicator does not clear itself between
/// the `finished` transition and the next `idle` transition.
enum SurfaceAgentStateResolver {

    /// Pure resolution entry point.
    ///
    /// - Parameters:
    ///   - tab: Source of the tab-level fallback (priority 4).
    ///   - focusedSurfaceID: Surface ID of the focused split pane when the
    ///     owning tab is currently displayed, or `nil` when the tab is not
    ///     displayed or no split is focused.
    ///   - primarySurfaceID: Surface ID of the tab's primary surface
    ///     (typically `tabSurfaceMap[tabID]`).
    ///   - allSurfaceIDs: Every surface currently associated with the tab
    ///     (primary + live splits + saved splits). The ordering provided
    ///     by the caller is preserved for priority 3 iteration.
    ///   - store: Per-surface state store. When `nil`, the resolver goes
    ///     straight to the tab fallback; useful for tests and for safety
    ///     during early startup before the store is injected.
    /// - Returns: The best `SurfaceAgentState` for the indicator.
    @MainActor
    static func resolve(
        tab: Tab,
        focusedSurfaceID: SurfaceID?,
        primarySurfaceID: SurfaceID?,
        allSurfaceIDs: [SurfaceID],
        store: AgentStatePerSurfaceStore?
    ) -> SurfaceAgentState {
        guard let store else {
            return SurfaceAgentState(from: tab)
        }

        if let focusedSurfaceID {
            let state = store.state(for: focusedSurfaceID)
            if state.isActive || state.hasAgent {
                return state
            }
        }

        if let primarySurfaceID, primarySurfaceID != focusedSurfaceID {
            let state = store.state(for: primarySurfaceID)
            if state.isActive || state.hasAgent {
                return state
            }
        }

        for surfaceID in allSurfaceIDs {
            if surfaceID == focusedSurfaceID || surfaceID == primarySurfaceID {
                continue
            }
            let state = store.state(for: surfaceID)
            if state.isActive || state.hasAgent {
                return state
            }
        }

        return SurfaceAgentState(from: tab)
    }
}
