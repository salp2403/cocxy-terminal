// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceAgentStateResolver.swift - Pure resolver that picks the best
// per-surface agent state for a tab-scoped indicator. After Fase 4 the
// resolver does not consult any Tab fields anymore; the store is the
// sole source of truth and the safety-net fallback is plain `.idle`.

import Foundation

/// Resolves the `SurfaceAgentState` that drives tab-scoped UI indicators
/// (agent progress overlay, status bar, sidebar pill, multi-agent
/// mini-pills).
///
/// Pure `enum` namespace with static entry points so the resolver can be
/// unit-tested as a plain value without booting AppKit or SwiftUI.
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
/// 4. **`.idle` fallback** — no store entry for any surface of the tab.
///    Idle is always safe: new agents repopulate the store via the
///    detection engine without needing a Tab snapshot.
///
/// A surface is considered "with activity" when its state is `.launched`,
/// `.working`, or `.waitingInput` (`isActive`), or when it has a detected
/// agent attached (`hasAgent`). This keeps finished-with-agent surfaces
/// visible as "activity" so the indicator does not clear itself between
/// the `finished` transition and the next `idle` transition.
enum SurfaceAgentStateResolver {

    /// Full resolution result: both the `SurfaceAgentState` picked for the
    /// indicator and the surface ID it came from.
    ///
    /// `chosenSurfaceID` is `nil` when the resolver fell through to the
    /// `.idle` fallback (priority 4). Callers that need to render
    /// additional per-surface indicators for the remaining splits use this
    /// field to skip the surface whose state already drives the primary
    /// indicator.
    struct Resolution: Equatable, Sendable {
        let state: SurfaceAgentState
        let chosenSurfaceID: SurfaceID?
    }

    /// Pure resolution entry point returning both the state and the
    /// surface ID it came from.
    ///
    /// - Parameters:
    ///   - focusedSurfaceID: Surface ID of the focused split pane when the
    ///     owning tab is currently displayed, or `nil` when the tab is not
    ///     displayed or no split is focused.
    ///   - primarySurfaceID: Surface ID of the tab's primary surface
    ///     (typically `tabSurfaceMap[tabID]`).
    ///   - allSurfaceIDs: Every surface currently associated with the tab
    ///     (primary + live splits + saved splits). The ordering provided
    ///     by the caller is preserved for priority 3 iteration.
    ///   - store: Per-surface state store. When `nil`, the resolver goes
    ///     straight to `.idle`; useful for tests and for safety during
    ///     early startup before the store is injected.
    /// - Returns: The best `SurfaceAgentState` and the surface ID it came
    ///   from, or `chosenSurfaceID == nil` when the `.idle` fallback was
    ///   used.
    @MainActor
    static func resolveFull(
        focusedSurfaceID: SurfaceID?,
        primarySurfaceID: SurfaceID?,
        allSurfaceIDs: [SurfaceID],
        store: AgentStatePerSurfaceStore?
    ) -> Resolution {
        guard let store else {
            return Resolution(state: .idle, chosenSurfaceID: nil)
        }

        if let focusedSurfaceID {
            let state = store.state(for: focusedSurfaceID)
            if state.isActive || state.hasAgent {
                return Resolution(state: state, chosenSurfaceID: focusedSurfaceID)
            }
        }

        if let primarySurfaceID, primarySurfaceID != focusedSurfaceID {
            let state = store.state(for: primarySurfaceID)
            if state.isActive || state.hasAgent {
                return Resolution(state: state, chosenSurfaceID: primarySurfaceID)
            }
        }

        for surfaceID in allSurfaceIDs {
            if surfaceID == focusedSurfaceID || surfaceID == primarySurfaceID {
                continue
            }
            let state = store.state(for: surfaceID)
            if state.isActive || state.hasAgent {
                return Resolution(state: state, chosenSurfaceID: surfaceID)
            }
        }

        return Resolution(state: .idle, chosenSurfaceID: nil)
    }

    /// Convenience wrapper that returns only the resolved state.
    ///
    /// Used by consumers that do not need the chosen surface ID (overlay,
    /// status bar, single sidebar pill). Internally delegates to
    /// `resolveFull`.
    @MainActor
    static func resolve(
        focusedSurfaceID: SurfaceID?,
        primarySurfaceID: SurfaceID?,
        allSurfaceIDs: [SurfaceID],
        store: AgentStatePerSurfaceStore?
    ) -> SurfaceAgentState {
        resolveFull(
            focusedSurfaceID: focusedSurfaceID,
            primarySurfaceID: primarySurfaceID,
            allSurfaceIDs: allSurfaceIDs,
            store: store
        ).state
    }

    /// Collects every other per-surface state that the primary resolver
    /// would skip, filtered to surfaces with live activity
    /// (`isActive || hasAgent`).
    ///
    /// Used by the multi-agent mini-pills to render indicators for splits
    /// whose agent is active but did not drive the tab-level primary
    /// indicator.
    ///
    /// The output is sorted by `SurfaceID.rawValue.uuidString` so
    /// successive renders keep the same order (no flicker as splits are
    /// added or removed).
    ///
    /// - Parameters:
    ///   - primaryChosenSurfaceID: Surface ID the primary resolver
    ///     selected for this tab. Pass the `chosenSurfaceID` from
    ///     `resolveFull`. When `nil`, the primary resolver fell back to
    ///     `.idle` and no surface is excluded.
    ///   - allSurfaceIDs: Every surface associated with the tab. The
    ///     caller ordering is ignored; the result is sorted by UUID.
    ///   - store: Per-surface state store. When `nil`, the result is
    ///     empty — there are no per-split states to surface.
    /// - Returns: The sorted list of additional active `SurfaceAgentState`
    ///   snapshots, or `[]` when no other split has activity.
    @MainActor
    static func additionalActiveStates(
        primaryChosenSurfaceID: SurfaceID?,
        allSurfaceIDs: [SurfaceID],
        store: AgentStatePerSurfaceStore?
    ) -> [SurfaceAgentState] {
        guard let store else { return [] }

        return allSurfaceIDs
            .filter { $0 != primaryChosenSurfaceID }
            .map { (surfaceID: $0, state: store.state(for: $0)) }
            .filter { $0.state.isActive || $0.state.hasAgent }
            .sorted { $0.surfaceID.rawValue.uuidString < $1.surfaceID.rawValue.uuidString }
            .map { $0.state }
    }
}
