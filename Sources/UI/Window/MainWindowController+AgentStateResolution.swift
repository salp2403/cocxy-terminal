// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+AgentStateResolution.swift - Bridge between the
// window controller and the pure SurfaceAgentStateResolver used by
// tab-scoped agent indicators.

import AppKit

extension MainWindowController {

    /// Resolves the `SurfaceAgentState` used by tab-scoped agent
    /// indicators.
    ///
    /// Picks the most relevant surface for the indicator (focused split
    /// first, then primary, then any other surface with activity) and
    /// reads its entry from the injected per-surface store. Falls back
    /// to `.idle` when the store has no active entry for any of the
    /// tab's surfaces.
    ///
    /// See `SurfaceAgentStateResolver` for the full priority chain and
    /// rationale.
    ///
    /// - Parameter tabID: Owning tab of the indicator being updated.
    /// - Returns: The best `SurfaceAgentState` to drive the indicator.
    func resolveSurfaceAgentState(for tabID: TabID) -> SurfaceAgentState {
        resolveSurfaceAgentStateFull(for: tabID).state
    }

    /// Full resolver wrapper returning both the state and the surface ID
    /// the resolver picked for the primary indicator.
    ///
    /// The multi-agent mini-pills use `chosenSurfaceID` to exclude the
    /// primary surface when collecting additional active splits.
    func resolveSurfaceAgentStateFull(
        for tabID: TabID
    ) -> SurfaceAgentStateResolver.Resolution {
        var focusedSurfaceID: SurfaceID?
        if displayedTabID == tabID {
            focusedSurfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID
        }

        return SurfaceAgentStateResolver.resolveFull(
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
    /// The sidebar renders one mini-pill per entry next to the main
    /// pill so the user sees every agent running across the tab's
    /// splits at a glance.
    func additionalActiveAgentStates(for tabID: TabID) -> [SurfaceAgentState] {
        let resolution = resolveSurfaceAgentStateFull(for: tabID)

        return SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: resolution.chosenSurfaceID,
            allSurfaceIDs: surfaceIDs(for: tabID),
            store: injectedPerSurfaceStore
        )
    }
}
