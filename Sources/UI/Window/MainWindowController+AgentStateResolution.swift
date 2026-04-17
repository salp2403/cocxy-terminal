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
        resolveSurfaceAgentStateFull(for: tabID, tab: tab).state
    }

    /// Full resolver wrapper returning both the state and the surface ID
    /// the resolver picked for the primary indicator.
    ///
    /// Fase 3e uses `chosenSurfaceID` to exclude the primary surface when
    /// collecting additional active splits for the multi-agent pills.
    func resolveSurfaceAgentStateFull(
        for tabID: TabID,
        tab: Tab
    ) -> SurfaceAgentStateResolver.Resolution {
        var focusedSurfaceID: SurfaceID?
        if displayedTabID == tabID {
            focusedSurfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID
        }

        return SurfaceAgentStateResolver.resolveFull(
            tab: tab,
            focusedSurfaceID: focusedSurfaceID,
            primarySurfaceID: tabSurfaceMap[tabID],
            allSurfaceIDs: surfaceIDs(for: tabID),
            store: injectedPerSurfaceStore
        )
    }

    /// Returns the per-surface states for splits of the tab other than
    /// the one the primary resolver chose, filtered to surfaces with
    /// live activity.
    ///
    /// The result is sorted by UUID so successive renders stay stable.
    /// Fase 3e renders one mini-pill per entry next to the main sidebar
    /// pill so the user can see every agent running across the tab's
    /// splits at a glance.
    func additionalActiveAgentStates(for tabID: TabID, tab: Tab) -> [SurfaceAgentState] {
        let resolution = resolveSurfaceAgentStateFull(for: tabID, tab: tab)

        return SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: resolution.chosenSurfaceID,
            allSurfaceIDs: surfaceIDs(for: tabID),
            store: injectedPerSurfaceStore
        )
    }
}
