// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+AgentStateResolution.swift - Bridge between the
// window controller and the pure SurfaceAgentStateResolver used by Fase 3
// UI consumers (agent progress overlay, status bar, sidebar pill).

import AppKit

extension MainWindowController {

    /// Resolves the `SurfaceAgentState` used by tab-scoped agent
    /// indicators.
    ///
    /// Picks the most relevant surface for the indicator (focused split
    /// first, then primary, then any other surface with activity) and
    /// reads its entry from the injected per-surface store. Falls back to
    /// the legacy tab-level fields whenever the store has no usable
    /// entry, so the pre-refactor visual behavior is preserved.
    ///
    /// See `SurfaceAgentStateResolver` for the full priority chain and
    /// rationale.
    ///
    /// - Parameters:
    ///   - tabID: Owning tab of the indicator being updated.
    ///   - tab: Latest tab snapshot, used for the safety-net fallback.
    /// - Returns: The best `SurfaceAgentState` to drive the indicator.
    func resolveSurfaceAgentState(for tabID: TabID, tab: Tab) -> SurfaceAgentState {
        var focusedSurfaceID: SurfaceID?
        if displayedTabID == tabID {
            focusedSurfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID
        }

        return SurfaceAgentStateResolver.resolve(
            tab: tab,
            focusedSurfaceID: focusedSurfaceID,
            primarySurfaceID: tabSurfaceMap[tabID],
            allSurfaceIDs: surfaceIDs(for: tabID),
            store: injectedPerSurfaceStore
        )
    }
}
