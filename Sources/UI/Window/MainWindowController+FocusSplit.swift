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

    /// Helper that locates the terminal host view for `surfaceID` and
    /// installs it as the window's first responder.
    ///
    /// Extracted from `focusSplit(tabID:surfaceID:)` so tests can
    /// exercise the focus transition without having to stage a full
    /// tab switch. The method is intentionally internal (not
    /// `fileprivate`) so a future cleanup can share it with other
    /// per-surface focus routes (e.g. Cmd+click on a timeline entry).
    @MainActor
    func applyFocusToSurface(surfaceID: SurfaceID) {
        guard
            let hostView = surfaceView(for: surfaceID),
            let window
        else {
            return
        }
        window.makeFirstResponder(hostView)
    }
}
