// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+FocusSplit.swift - Activates a tab and focuses
// a specific split surface inside it. Used by the sidebar multi-agent
// mini-pills so a click on the pill lands keyboard focus on the split
// where the user wants to interact with the agent.

import AppKit

extension MainWindowController {

    /// Activates the owning tab (if needed) and focuses the split whose
    /// surface matches `surfaceID`.
    ///
    /// The sidebar mini-pills call this when the user clicks the pill
    /// for a split other than the focused one. If the tab is already
    /// the active tab, the focus transition is a single main-queue
    /// dispatch; otherwise the tab activation runs first and the focus
    /// update is scheduled on the next run-loop tick so pending split
    /// view restoration (driven by `handleTabSwitch` downstream of
    /// `tabManager.setActive`) has time to repopulate
    /// `splitSurfaceViews`.
    ///
    /// Safe to call with a `surfaceID` that no longer resolves to a
    /// host view (e.g. the split was closed between the pill render
    /// and the click): the helper silently returns. We intentionally
    /// do NOT beep on missing targets so a stale click during
    /// concurrent teardown stays quiet.
    ///
    /// - Parameters:
    ///   - tabID: Owning tab of the split. When it differs from the
    ///     currently active tab, the tab is activated first.
    ///   - surfaceID: Identifier of the split surface to focus.
    @MainActor
    func focusSplit(tabID: TabID, surfaceID: SurfaceID) {
        let needsTabActivation = tabManager.activeTabID != tabID
        if needsTabActivation {
            tabManager.setActive(id: tabID)
        }

        // When the tab switch is queued, we need one main-queue tick
        // for `handleTabSwitch` + `splitSurfaceViews` to settle. When
        // the tab was already active, dispatch async is still safe —
        // it yields one runloop cycle then runs the focus transition.
        // Keeping the path uniform avoids branching between sync vs
        // async behavior and prevents subtle ordering bugs.
        DispatchQueue.main.async { [weak self] in
            self?.applyFocusToSurface(surfaceID: surfaceID)
        }
    }

    /// Moves AppKit focus to the host view that owns `surfaceID` AND
    /// refreshes every UI consumer that derives from the "which split
    /// is focused" input.
    ///
    /// Extracted from `focusSplit(tabID:surfaceID:)` so tests can
    /// exercise the focus transition without having to stage a full
    /// tab switch. Kept `internal` (not `fileprivate`) so a future
    /// cleanup can share it with other per-surface focus routes
    /// (e.g. Cmd+click on a timeline entry).
    ///
    /// ## Refresh set
    ///
    /// After `makeFirstResponder(...)`, callers that read
    /// `focusedSplitSurfaceView?.terminalViewModel?.surfaceID` start
    /// returning the new surface. But most sidebar/status-bar consumers
    /// populate their snapshots during a separate render pass driven
    /// by Combine publishers — publishers that don't fire when the
    /// click stays on the SAME tab. Without an explicit refresh, the
    /// Fase B focused-border stays on the old mini-pill, the status
    /// bar mini-matrix keeps highlighting the old dot, the split
    /// manager's `focusedLeafID` still points at the previous leaf,
    /// and the agent-progress overlay may keep showing the previous
    /// split's metrics.
    ///
    /// This method explicitly fans the change out to five places:
    /// 1. The split manager's `focusedLeafID` (so `paneSnapshot()` and
    ///    downstream consumers agree on who owns focus).
    /// 2. The sidebar view model (so per-split mini-pills re-render
    ///    with the new `isFocused` bit).
    /// 3. The status bar (so the per-split mini-matrix re-renders).
    /// 4. The per-terminal agent progress overlay (so its counters
    ///    follow the newly focused split).
    /// 5. The horizontal tab strip (so the active-leaf highlight
    ///    follows the new focused split instead of the previous one).
    @MainActor
    func applyFocusToSurface(surfaceID: SurfaceID) {
        guard
            let hostView = surfaceView(for: surfaceID),
            let window
        else {
            return
        }
        window.makeFirstResponder(hostView)

        // Keep the domain-level split focus in sync with AppKit so
        // later queries via `paneSnapshot()` pick the right leaf.
        syncSplitManagerFocus(to: hostView)

        // Re-render every UI surface that reads focused-split state
        // through the per-surface resolver. `syncWithManager()` re-
        // populates `TabDisplayItem.perSurfaceAgents` (mini-pills) and
        // `refreshStatusBar()` re-computes `AgentSummary` (mini-matrix
        // + active-agent pill). `updateAgentProgressOverlay()` follows
        // the resolved focused surface for its counters.
        // `refreshTabStrip()` rebuilds the horizontal workspace toolbar
        // so the active-leaf chip highlights the new split instead of
        // the previous one (the strip reads `activeSplitManager.focusedLeafID`
        // which we just updated in `syncSplitManagerFocus`).
        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        updateAgentProgressOverlay()
        refreshTabStrip()
    }

    /// Aligns the active split manager's `focusedLeafID` with the
    /// given AppKit host view.
    ///
    /// Uses `collectLeafViews()` to enumerate the split tree's panes
    /// in document order and matches the target view by reference.
    /// When the view is not in the split tree (e.g. the hostView is
    /// the tab's primary terminal in a single-surface tab), the
    /// lookup silently returns — `makeFirstResponder` has already
    /// landed, and the split manager has no leaf to update.
    @MainActor
    private func syncSplitManagerFocus(to hostView: NSView) {
        guard let splitManager = activeSplitManager else { return }
        let leaves = splitManager.rootNode.allLeafIDs()
        let leafViews = collectLeafViews()
        guard leafViews.count == leaves.count else { return }
        if let index = leafViews.firstIndex(where: { $0 === hostView }) {
            splitManager.focusLeaf(id: leaves[index].leafID)
        }
    }
}
