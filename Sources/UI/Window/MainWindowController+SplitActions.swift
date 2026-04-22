// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+SplitActions.swift - Split pane creation, navigation, and management.

import AppKit
import SwiftUI

// MARK: - Split Pane Actions

/// Extension that handles all split pane operations: creating splits,
/// closing panes, navigating between panes, and rebuilding the visual
/// hierarchy from the domain model.
///
/// Extracted from MainWindowController to keep the main file focused on
/// window management, tabs, and core layout.
extension MainWindowController {

    // MARK: - Active Split Manager

    /// Returns the SplitManager for the active tab, if any.
    ///
    /// This is a convenience accessor used by keyboard action methods.
    /// Looks up the active tab ID and retrieves the per-tab SplitManager
    /// from the TabSplitCoordinator.
    var activeSplitManager: SplitManager? {
        guard let targetTabID = visibleTabID ?? tabManager.activeTabID else { return nil }
        return tabSplitCoordinator.splitManager(for: targetTabID)
    }

    // MARK: - Focused Pane

    /// The currently focused split pane's surface view.
    /// Defaults to terminalSurfaceView when no split is active.
    var focusedSplitSurfaceView: TerminalHostView? {
        guard let responder = window?.firstResponder else {
            if let focusedPane = focusedPaneView() as? TerminalHostView {
                return focusedPane
            }
            return terminalSurfaceView
        }
        // Walk the responder chain to find a terminal host view.
        if let surface = responder as? TerminalHostView {
            return surface
        }
        if let focusedPane = focusedPaneView() as? TerminalHostView {
            return focusedPane
        }
        return terminalSurfaceView
    }

    // MARK: - Split Creation Actions

    /// Splits the focused pane horizontally (side by side). Shortcut: Cmd+D.
    @objc func splitHorizontalAction(_ sender: Any?) {
        performVisualSplit(isVertical: true)
    }

    /// Splits the focused pane vertically (stacked). Shortcut: Cmd+Shift+D.
    @objc func splitVerticalAction(_ sender: Any?) {
        performVisualSplit(isVertical: false)
    }

    /// Opens a browser panel appended at the end of the split tree.
    /// The browser tab receives focus so it appears selected in the tab strip.
    @objc func splitWithBrowserAction(_ sender: Any?) {
        performVisualSplitWithPanel(isVertical: true, panel: .browser(), appendToEnd: true, focusNewPanel: true)
    }

    /// Opens a markdown panel appended at the end of the split tree.
    @objc func splitWithMarkdownAction(_ sender: Any?) {
        // Markdown panel opens with the workspace's working directory README if available.
        let dir = visibleTabID.flatMap { tabManager.tab(for: $0)?.workingDirectory }
            ?? tabManager.activeTab?.workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        let readmePath = dir.appendingPathComponent("README.md")
        let panel: PanelInfo = FileManager.default.fileExists(atPath: readmePath.path)
            ? .markdown(path: readmePath)
            : PanelInfo(type: .markdown)
        performVisualSplitWithPanel(isVertical: true, panel: panel, appendToEnd: true, focusNewPanel: true)
    }

    // MARK: - Split with Panel

    /// Creates a visual split with a non-terminal panel.
    ///
    /// - Parameters:
    ///   - isVertical: Whether to split horizontally (side by side) or vertically (stacked).
    ///   - panel: The panel info describing the content type and initial data.
    ///   - appendToEnd: When true, the panel is added at the rightmost position
    ///     of the split tree regardless of focus. Defaults to false (split at focus).
    ///   - focusNewPanel: When true, the new panel receives focus in the domain
    ///     model so the tab strip highlights it. Defaults to false.
    func performVisualSplitWithPanel(isVertical: Bool, panel: PanelInfo, appendToEnd: Bool = false, focusNewPanel: Bool = false) {
        guard let container = terminalContainerView else { return }
        let currentPaneCount = countSplitPanes()
        guard currentPaneCount < Self.maxPaneCount else { return }
        guard let focusedSurface = focusedSplitSurfaceView else { return }
        let currentTabID = visibleTabID ?? tabManager.activeTabID
        let splitManager = activeSplitManager
        let splitTargetLeafID = splitManager?.focusedLeafID

        // Update the domain model with panel type.
        let contentID: UUID?
        if appendToEnd {
            contentID = splitManager?.appendPanel(panel: panel, focusNewPanel: focusNewPanel)
        } else {
            contentID = splitManager?.splitFocusedWithPanel(
                direction: isVertical ? .horizontal : .vertical,
                panel: panel
            )
        }
        let newSplitID = appendToEnd
            ? nil
            : splitTargetLeafID.flatMap { splitManager?.parentSplitID(of: $0) }
        guard let contentID else {
            return
        }

        // Create the panel view based on type.
        let panelView: NSView
        switch panel.type {
        case .terminal:
            // Fallback: create a terminal (should use performVisualSplit instead).
            performVisualSplit(isVertical: isVertical)
            return
        case .browser:
            let browserVM = BrowserViewModel()
            browserVM.historyStore = browserHistoryStore
            browserVM.activeProfileID = browserProfileManager?.activeProfileID
            if let url = panel.initialURL {
                browserVM.urlString = url.absoluteString
            }
            var browserView = BrowserPanelView(
                viewModel: browserVM,
                profileManager: browserProfileManager,
                onToggleHistory: { [weak self] in self?.toggleBrowserHistory() },
                onToggleBookmarks: { [weak self] in self?.toggleBrowserBookmarks() },
                onDismiss: { [weak self] in self?.closePanel(contentID: contentID) },
                layout: .splitPane
            )
            browserView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
            let hostingView = NSHostingView(rootView: browserView)
            hostingView.wantsLayer = true
            panelView = hostingView
        case .markdown:
            let workspaceDir = visibleTabID.flatMap { tabManager.tab(for: $0)?.workingDirectory }
                ?? tabManager.activeTab?.workingDirectory
            let mdView = MarkdownContentView(filePath: panel.filePath, workspaceDirectory: workspaceDir)
            panelView = mdView
        case .subagent:
            guard let dashboardVM = injectedDashboardViewModel,
                  let subagentId = panel.subagentId,
                  let sessionId = panel.sessionId else { return }
            let subView = SubagentContentView(
                viewModel: dashboardVM,
                subagentId: subagentId,
                sessionId: sessionId,
                vibrancyAppearanceOverride: resolveVibrancyAppearanceOverride()
            )
            let capturedContentID = contentID
            subView.onClose = { [weak self] in
                self?.closeSubagentPanel(contentID: capturedContentID)
            }
            panelView = subView
        }

        panelContentViews[contentID] = panelView

        if appendToEnd, let tabID = currentTabID {
            // Rebuild the entire view hierarchy from the domain model.
            // This guarantees the visual layout matches the tree after
            // appendPanel placed the new leaf at the rightmost position.
            rebuildSplitViewHierarchy(for: tabID)
        } else {
            // Build the visual split at the focused position.
            let parentView = focusedSurface.superview ?? container

            if activeSplitView == nil {
                focusedSurface.removeFromSuperview()
                let splitView = createSplitView(
                    isVertical: isVertical,
                    frame: container.bounds,
                    first: focusedSurface,
                    second: panelView,
                    splitID: newSplitID
                )
                container.addSubview(splitView, positioned: .below, relativeTo: nil)
                self.activeSplitView = splitView
            } else if let parentSplit = parentView as? NSSplitView {
                let paneFrame = focusedSurface.frame
                let subviewIndex = parentSplit.subviews.firstIndex(of: focusedSurface)
                focusedSurface.removeFromSuperview()
                let nestedSplit = createSplitView(
                    isVertical: isVertical,
                    frame: paneFrame,
                    first: focusedSurface,
                    second: panelView,
                    splitID: newSplitID
                )
                if let index = subviewIndex {
                    parentSplit.insertArrangedSubview(nestedSplit, at: index)
                } else {
                    parentSplit.addSubview(nestedSplit)
                }
                parentSplit.adjustSubviews()
            }
        }

        // When focusNewPanel is false, keep focus on the terminal so the
        // user's workflow is not disrupted. When true, the panel receives
        // domain-model focus (via appendPanel) and we skip forcing the
        // terminal as first responder so the tab strip highlights the new panel.
        if !focusNewPanel {
            window?.makeFirstResponder(focusedSurface)
        }

        // Update toolbar to show panel tabs.
        updateWorkspaceToolbar()
    }

    // MARK: - Terminal Split

    /// Creates a visual split by subdividing the focused pane.
    ///
    /// Supports recursive splits up to `maxPaneCount` panes.
    /// When splitting a pane that is already inside a split, the focused pane's
    /// view is replaced with a new NSSplitView containing the original pane
    /// and a new terminal pane.
    func performVisualSplit(isVertical: Bool) {
        guard let container = terminalContainerView else { return }
        let currentTabID = visibleTabID ?? tabManager.activeTabID

        // Count current panes. Reject if at maximum.
        let currentPaneCount = countSplitPanes()
        guard currentPaneCount < Self.maxPaneCount else {
            NSLog("[MainWindowController] Max pane count (%d) reached", Self.maxPaneCount)
            return
        }

        // Find the surface view that currently has focus.
        guard let focusedSurface = focusedSplitSurfaceView else { return }
        let splitManager = activeSplitManager
        let splitTargetLeafID = splitManager?.focusedLeafID

        // Update the domain model.
        splitManager?.handleSplitAction(
            isVertical ? .splitHorizontal : .splitVertical
        )
        let newSplitID = splitTargetLeafID.flatMap { splitManager?.parentSplitID(of: $0) }

        // Create new terminal for the second pane.
        let newViewModel = TerminalViewModel(engine: bridge)
        let configuredFontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        newViewModel.setDefaultFontSize(configuredFontSize)
        let newSurfaceView = CocxyCoreView(viewModel: newViewModel)

        let workingDirectory = currentTabID.flatMap { tabManager.tab(for: $0)?.workingDirectory }
            ?? tabManager.activeTab?.workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        let surfaceID: SurfaceID
        do {
            surfaceID = try bridge.createSurface(
                in: newSurfaceView,
                workingDirectory: workingDirectory,
                command: nil
            )
            newViewModel.markRunning(surfaceID: surfaceID)
            newSurfaceView.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
            newSurfaceView.syncSizeWithTerminal()
        } catch {
            NSLog("[MainWindowController] Failed to create surface for split: %@",
                  String(describing: error))
            return
        }

        // Track the new pane.
        splitSurfaceViews[surfaceID] = newSurfaceView
        splitViewModels[surfaceID] = newViewModel
        if let activeTabID = currentTabID {
            wireSurfaceHandlers(
                for: surfaceID,
                tabID: activeTabID,
                in: newSurfaceView,
                initialWorkingDirectory: workingDirectory
            )
        }

        // Determine the parent of the focused surface view.
        let parentView = focusedSurface.superview ?? container

        if activeSplitView == nil {
            // First split: wrap primary + new in a split view.
            focusedSurface.removeFromSuperview()

            let splitView = createSplitView(
                isVertical: isVertical,
                frame: container.bounds,
                first: focusedSurface,
                second: newSurfaceView,
                splitID: newSplitID
            )

            container.addSubview(splitView, positioned: .below, relativeTo: nil)
            self.activeSplitView = splitView
        } else if let parentSplit = parentView as? NSSplitView {
            // Recursive split: replace the focused pane inside its parent split
            // with a new nested split containing the focused pane + new pane.
            let paneFrame = focusedSurface.frame
            let subviewIndex = parentSplit.subviews.firstIndex(of: focusedSurface)
            focusedSurface.removeFromSuperview()

            let nestedSplit = createSplitView(
                isVertical: isVertical,
                frame: paneFrame,
                first: focusedSurface,
                second: newSurfaceView,
                splitID: newSplitID
            )

            if let index = subviewIndex {
                parentSplit.insertArrangedSubview(nestedSplit, at: index)
            } else {
                parentSplit.addSubview(nestedSplit)
            }
            parentSplit.adjustSubviews()
        }

        // Focus the new pane.
        window?.makeFirstResponder(newSurfaceView)

        // Update toolbar to show panel tabs.
        updateWorkspaceToolbar()

        // Aurora sidebar observes `TabManager.$tabs` and
        // `AgentStatePerSurfaceStore.$states`, but neither publisher
        // fires when a new idle surface joins the tree — the tab is
        // already there and the store has no entry yet. Push a
        // refresh so the new pane shows up in the Aurora session row
        // without waiting for the next agent activity.
        auroraChromeController?.refreshSources()
    }

    // MARK: - Close Split

    /// Closes the focused split pane. Shortcut: Cmd+Shift+W.
    @objc func closeSplitAction(_ sender: Any?) {
        guard let container = terminalContainerView else { return }
        guard activeSplitView != nil else { return }

        guard let focusedPane = focusedPaneSnapshot() else { return }
        var promotedRemainingView: NSView?

        // Check if the pane being closed is a non-terminal panel.
        let closingPanelView: NSView? = panelContentViews[focusedPane.contentID]

        // Keep at least one terminal leaf alive in every tab. Closing the last
        // remaining terminal and leaving only auxiliary panels produces a dead
        // workspace with no PTY-backed surface to focus or recover.
        if closingPanelView == nil,
           let splitManager = activeSplitManager {
            let terminalLeafCount = splitManager.rootNode.allLeafIDs().filter {
                splitManager.panelType(for: $0.terminalID) == .terminal
            }.count
            if terminalLeafCount <= 1 {
                NSSound.beep()
                return
            }
        }

        // Update the domain model.
        activeSplitManager?.handleSplitAction(.closeActiveSplit)

        // Determine the view to remove: either a panel or a terminal surface.
        let viewToRemove: NSView
        if let panelView = closingPanelView {
            viewToRemove = panelView
            // Clean up the panel content view entry.
            panelContentViews.removeValue(forKey: focusedPane.contentID)
        } else if let focusedSurface = focusedPane.view as? TerminalHostView {
            let surfaceIDToDestroy = focusedPane.surfaceID

            // Destroy the surface in the engine.
            if let sid = surfaceIDToDestroy {
                clearSurfaceTracking(for: sid)
                // Cancel any pending `.launched` watchdog or foreground
                // probe before we tear the surface down so the scheduled
                // callbacks cannot fire against the already-cleared
                // store entry. The input-drop tracker is cleared in the
                // same block so the next split created under this ID
                // (extremely rare, UUID-based) starts with a fresh
                // counter.
                cancelLaunchedWatchdog(surfaceID: sid)
                cancelForegroundProbe(surfaceID: sid)
                cancelInputDropTracking(surfaceID: sid)
                // Release per-surface detection state (engine bucket +
                // shadow store entry) before the bridge tears down the
                // terminal so no stale split state is retained.
                injectedAgentDetectionEngine?.clearSurface(sid)
                injectedPerSurfaceStore?.reset(surfaceID: sid)
                bridge.destroySurface(sid)
                splitViewModels[sid]?.markStopped()
                splitSurfaceViews.removeValue(forKey: sid)
                splitViewModels.removeValue(forKey: sid)
            }
            viewToRemove = focusedSurface
        } else {
            return
        }

        // Remove the view from its parent split and collapse if needed.
        if let parentSplit = viewToRemove.superview as? NSSplitView {
            viewToRemove.removeFromSuperview()

            // If the parent split now has one child, promote it.
            if parentSplit.subviews.count == 1, let remaining = parentSplit.subviews.first {
                let grandparent = parentSplit.superview
                let parentFrame = parentSplit.frame

                remaining.removeFromSuperview()
                parentSplit.removeFromSuperview()
                promotedRemainingView = remaining

                remaining.frame = parentFrame
                remaining.autoresizingMask = [.width, .height]

                if let gp = grandparent as? NSSplitView {
                    gp.addSubview(remaining)
                    gp.adjustSubviews()
                } else {
                    grandparent?.addSubview(remaining, positioned: .below, relativeTo: nil)
                }
            }
        }

        let remainingLeafCount = activeSplitManager?.rootNode.allLeafIDs().count ?? 0

        // Check if we are back to a single pane and adopt the surviving view as
        // the tab's primary surface when needed.
        if remainingLeafCount <= 1 {
            let trackedFallbackTerminalView =
                visibleTabID.flatMap { tabSurfaceViews[$0] }
                ?? splitSurfaceViews.values.first
            let remainingView =
                promotedRemainingView
                ?? firstVisiblePaneView(in: container)
                ?? trackedFallbackTerminalView
                ?? terminalSurfaceView

            activeSplitView?.removeFromSuperview()
            activeSplitView = nil

            if let remainingTerminalView = remainingView as? TerminalHostView {
                remainingTerminalView.removeFromSuperview()
                remainingTerminalView.frame = container.bounds
                remainingTerminalView.autoresizingMask = [.width, .height]
                container.addSubview(remainingTerminalView, positioned: .below, relativeTo: nil)

                promoteTerminalHostViewToPrimary(remainingTerminalView)
                remainingTerminalView.syncSizeWithTerminal()
                window?.makeFirstResponder(remainingTerminalView)
            } else if let fallbackTerminalView = trackedFallbackTerminalView {
                fallbackTerminalView.removeFromSuperview()
                fallbackTerminalView.frame = container.bounds
                fallbackTerminalView.autoresizingMask = [.width, .height]
                container.addSubview(fallbackTerminalView, positioned: .below, relativeTo: nil)

                promoteTerminalHostViewToPrimary(fallbackTerminalView)
                fallbackTerminalView.syncSizeWithTerminal()
                window?.makeFirstResponder(fallbackTerminalView)
            } else if let remainingView {
                remainingView.removeFromSuperview()
                remainingView.frame = container.bounds
                remainingView.autoresizingMask = [.width, .height]
                container.addSubview(remainingView, positioned: .below, relativeTo: nil)
                window?.makeFirstResponder(remainingView)
            }
        } else {
            // Focus another pane.
            let nextFocus = focusedPaneView() ?? terminalSurfaceView
            if let next = nextFocus {
                window?.makeFirstResponder(next)
            }
        }

        // Update toolbar to reflect panel changes.
        updateWorkspaceToolbar()

        // Aurora sidebar: pushing a refresh after the tree has
        // collapsed keeps the session-row pane list aligned with the
        // remaining surfaces. The store subscription cannot detect a
        // split close on its own because the torn-down surface was
        // already removed from the store by the teardown path.
        auroraChromeController?.refreshSources()
    }

    // MARK: - Split Navigation Actions

    /// Equalizes all split panes. Shortcut: Cmd+Shift+E.
    @objc func equalizeSplitsAction(_ sender: Any?) {
        activeSplitManager?.handleSplitAction(.equalizeSplits)
    }

    /// Toggles zoom on the focused split pane. Shortcut: Cmd+Shift+F.
    @objc func toggleSplitZoomAction(_ sender: Any?) {
        activeSplitManager?.handleSplitAction(.toggleZoom)
    }

    /// Navigates to the split pane on the left. Shortcut: Cmd+Option+Left.
    @objc func navigateSplitLeftAction(_ sender: Any?) {
        activeSplitManager?.handleSplitAction(.navigateLeft)
    }

    /// Navigates to the split pane on the right. Shortcut: Cmd+Option+Right.
    @objc func navigateSplitRightAction(_ sender: Any?) {
        activeSplitManager?.handleSplitAction(.navigateRight)
    }

    /// Navigates to the split pane above. Shortcut: Cmd+Option+Up.
    @objc func navigateSplitUpAction(_ sender: Any?) {
        activeSplitManager?.handleSplitAction(.navigateUp)
    }

    /// Navigates to the split pane below. Shortcut: Cmd+Option+Down.
    @objc func navigateSplitDownAction(_ sender: Any?) {
        activeSplitManager?.handleSplitAction(.navigateDown)
    }

    // MARK: - Workspace Toolbar Updates

    /// Updates the workspace toolbar to reflect the current split state.
    /// Called after split/close operations to keep the toolbar in sync.
    func updateWorkspaceToolbar() {
        refreshTabStrip()
    }

    // MARK: - Split View Helpers

    /// Creates an NSSplitView wrapping two subviews at 50% ratio.
    func createSplitView(
        isVertical: Bool,
        frame: NSRect,
        first: NSView,
        second: NSView,
        splitID: UUID? = nil,
        ratio: CGFloat = 0.5
    ) -> NSSplitView {
        let splitView = NSSplitView(frame: frame)
        splitView.isVertical = isVertical
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        if let splitID {
            splitView.identifier = NSUserInterfaceItemIdentifier(splitID.uuidString)
        }

        first.frame = NSRect(origin: .zero, size: frame.size)
        second.frame = NSRect(origin: .zero, size: frame.size)

        splitView.addSubview(first)
        splitView.addSubview(second)
        splitView.adjustSubviews()

        // Defer position setting to after layout is complete.
        // DispatchQueue.main.async is more reliable than Task for single-turn
        // deferral — it fires after the current layout pass finishes.
        DispatchQueue.main.async { [weak splitView] in
            guard let splitView else { return }
            let totalSize = splitView.isVertical
                ? splitView.bounds.width
                : splitView.bounds.height
            guard totalSize > 0 else { return }
            let position = (totalSize - splitView.dividerThickness) * SplitNode.clampRatio(ratio)
            splitView.setPosition(position, ofDividerAt: 0)
        }

        return splitView
    }

    /// Finds a rendered split view by its logical split node ID.
    func findSplitView(withID splitID: UUID, in rootView: NSView? = nil) -> NSSplitView? {
        let root = rootView ?? activeSplitView
        let identifier = NSUserInterfaceItemIdentifier(splitID.uuidString)

        guard let root else { return nil }
        if let splitView = root as? NSSplitView, splitView.identifier == identifier {
            return splitView
        }

        for subview in root.subviews {
            if let match = findSplitView(withID: splitID, in: subview) {
                return match
            }
        }

        return nil
    }

    /// Collects all leaf views from the split hierarchy in visual order (DFS).
    ///
    /// When no splits are active, returns just the primary terminal surface.
    /// When splits are active, walks the NSSplitView tree depth-first to
    /// produce an ordered list matching the domain model's `allLeafIDs()`.
    func collectLeafViews() -> [NSView] {
        guard let splitView = activeSplitView else {
            if let primary = terminalSurfaceView {
                return [primary]
            }
            return []
        }
        return collectLeaves(from: splitView)
    }

    /// Recursively collects non-NSSplitView children from a split hierarchy.
    private func collectLeaves(from view: NSView) -> [NSView] {
        if let splitView = view as? NSSplitView {
            return splitView.subviews.flatMap { collectLeaves(from: $0) }
        }
        return [view]
    }

    /// Counts the total number of panes in the split hierarchy.
    func countSplitPanes() -> Int {
        if activeSplitView == nil {
            return 1  // Just the primary surface.
        }
        // 1 (primary) + split terminal surfaces + non-terminal panels.
        return 1 + splitSurfaceViews.count + panelContentViews.count
    }

    /// Reloads the browser in the currently focused panel, if it is a browser.
    func reloadFocusedBrowserPanel() {
        guard let sm = activeSplitManager,
              let focusedID = sm.focusedLeafID else { return }

        let leaves = sm.rootNode.allLeafIDs()
        guard let leaf = leaves.first(where: { $0.leafID == focusedID }) else { return }

        if let panelView = panelContentViews[leaf.terminalID],
           let viewModel = browserViewModel(containedIn: panelView) {
            viewModel.reload()
        }
    }

    // MARK: - Rebuild Split Hierarchy

    /// Rebuilds the visual NSSplitView hierarchy from the domain model.
    ///
    /// Used after operations that change the logical ordering of leaves
    /// (e.g., swap/reorder) without adding or removing panes. Removes
    /// the current activeSplitView and reconstructs it to match the
    /// domain model's DFS order.
    func rebuildSplitViewHierarchy(
        for tabID: TabID,
        viewsByTerminalIDOverride: [UUID: NSView]? = nil
    ) {
        guard let container = terminalContainerView else { return }
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        let leaves = sm.rootNode.allLeafIDs()

        // Nothing to rebuild if the domain model has a single leaf.
        guard leaves.count > 1 else {
            refreshTabStrip()
            return
        }

        // Collect all leaf views in current visual order.
        let currentLeafViews = collectLeafViews()

        let viewsByTerminalID: [UUID: NSView]
        if let viewsByTerminalIDOverride {
            viewsByTerminalID = viewsByTerminalIDOverride
        } else {
            // Build a best-effort mapping from terminalID to the NSView backing it.
            var inferredViewsByTerminalID: [UUID: NSView] = [:]
            let allLeafInfos = sm.rootNode.allLeafIDs()

            // The primary surface maps to the first terminal leaf that matches.
            if let primary = terminalSurfaceView,
               tabSurfaceMap[tabID] != nil,
               let firstLeaf = allLeafInfos.first {
                inferredViewsByTerminalID[firstLeaf.terminalID] = primary
            }

            // Map split surfaces by finding which terminalID they back.
            // In the current architecture, split surfaces are keyed by SurfaceID,
            // not terminalID. We match by view identity from the visual hierarchy.
            for (i, leafView) in currentLeafViews.enumerated() {
                if i < allLeafInfos.count {
                    let terminalID = allLeafInfos[i].terminalID
                    if inferredViewsByTerminalID[terminalID] == nil {
                        inferredViewsByTerminalID[terminalID] = leafView
                    }
                }
            }

            viewsByTerminalID = inferredViewsByTerminalID
        }

        // Panel views stored in panelContentViews are found by
        // buildNSSplitView via the fallback lookup. No extra
        // mapping is needed here.

        // Detach all leaf views from the hierarchy.
        for view in currentLeafViews {
            view.removeFromSuperview()
        }
        activeSplitView?.removeFromSuperview()
        activeSplitView = nil

        // When transitioning from a single pane to a split layout,
        // remove the primary surface from the container so it can be
        // re-attached inside the new NSSplitView hierarchy.
        terminalSurfaceView?.removeFromSuperview()

        // Rebuild from the domain model.
        let newSplitView = buildNSSplitView(from: sm.rootNode, viewsByTerminalID: viewsByTerminalID)

        if let splitView = newSplitView as? NSSplitView {
            splitView.frame = container.bounds
            splitView.autoresizingMask = [.width, .height]
            container.addSubview(splitView, positioned: .below, relativeTo: nil)
            activeSplitView = splitView
        } else if let singleView = newSplitView {
            // Back to a single pane (shouldn't happen here but defensive).
            singleView.frame = container.bounds
            singleView.autoresizingMask = [.width, .height]
            container.addSubview(singleView, positioned: .below, relativeTo: nil)
        }

        refreshTabStrip()
    }

    /// Recursively builds an NSView hierarchy from a SplitNode tree.
    private func buildNSSplitView(
        from node: SplitNode,
        viewsByTerminalID: [UUID: NSView]
    ) -> NSView? {
        switch node {
        case .leaf(_, let terminalID):
            return viewsByTerminalID[terminalID]
                ?? panelContentViews[terminalID]

        case .split(let id, let direction, let first, let second, let ratio):
            guard let firstView = buildNSSplitView(from: first, viewsByTerminalID: viewsByTerminalID),
                  let secondView = buildNSSplitView(from: second, viewsByTerminalID: viewsByTerminalID) else {
                return buildNSSplitView(from: first, viewsByTerminalID: viewsByTerminalID)
                    ?? buildNSSplitView(from: second, viewsByTerminalID: viewsByTerminalID)
            }
            let splitFrame = terminalContainerView?.bounds ?? .zero
            return createSplitView(
                isVertical: direction == .horizontal,
                frame: splitFrame,
                first: firstView,
                second: secondView,
                splitID: id,
                ratio: ratio
            )
        }
    }

    /// Builds a detached split hierarchy that can be stored for a background tab.
    ///
    /// The returned view is not added to the container; callers can place it
    /// into `savedTabSplitViews` and let `handleTabSwitch` restore it later.
    func makeStoredSplitView(
        from rootNode: SplitNode,
        viewsByTerminalID: [UUID: NSView]
    ) -> NSSplitView? {
        guard let view = buildNSSplitView(from: rootNode, viewsByTerminalID: viewsByTerminalID)
        else {
            return nil
        }
        return view as? NSSplitView
    }

    // MARK: - Subagent Auto-Split

    /// Spawns a subagent panel as a vertical split on the right side.
    ///
    /// Called automatically when a SubagentStart hook event arrives.
    /// Creates a `SubagentContentView` and appends it to the split tree.
    ///
    /// - Parameters:
    ///   - subagentId: The unique ID of the spawned subagent.
    ///   - sessionId: The parent session's ID.
    ///   - agentType: The subagent type (e.g., "Explore", "Plan").
    func spawnSubagentPanel(subagentId: String, sessionId: String, agentType: String?, targetTabId: UUID? = nil) {
        let normalizedSubagentId = subagentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSubagentId.isEmpty else { return }
        let normalizedAgentType = agentType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedAgentType, !normalizedAgentType.isEmpty else {
            return
        }
        let lowercasedAgentType = normalizedAgentType.lowercased()
        let genericAgentTypes: Set<String> = [
            "subprocess",
            "agent",
            "subagent",
            "generic",
            "general",
            "general-purpose",
            "unknown",
        ]
        if genericAgentTypes.contains(lowercasedAgentType) {
            return
        }

        // Switch to the correct tab before creating the split.
        if let targetId = targetTabId {
            let targetTabID = TabID(rawValue: targetId)
            if tabManager.activeTabID != targetTabID {
                _ = focusTab(id: targetTabID)
            }
        }

        if panelContentViews.values.contains(where: { view in
            guard let subagentView = view as? SubagentContentView else { return false }
            return subagentView.subagentId == normalizedSubagentId && subagentView.sessionId == sessionId
        }) {
            refreshTabStrip()
            return
        }

        let panel = PanelInfo.subagent(id: normalizedSubagentId, sessionId: sessionId)
        performVisualSplitWithPanel(isVertical: true, panel: panel, appendToEnd: true)

        if let activeTabID = visibleTabID ?? tabManager.activeTabID {
            if let contentID = panelContentViews.first(where: { _, view in
                guard let subagentView = view as? SubagentContentView else { return false }
                return subagentView.subagentId == normalizedSubagentId && subagentView.sessionId == sessionId
            })?.key {
                tabSplitCoordinator.splitManager(for: activeTabID)
                    .setPanelTitle(for: contentID, title: normalizedAgentType)
            }
        }

        // Animate the new panel entrance (fade-in).
        if let newPanelView = panelContentViews.values.first(where: { ($0 as? SubagentContentView)?.subagentId == subagentId }) {
            let duration = AnimationConfig.duration(AnimationConfig.splitTransitionDuration)
            if duration > 0 {
                newPanelView.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    newPanelView.animator().alphaValue = 1.0
                }
            }
        }

        refreshTabStrip()
    }

    /// Closes a subagent panel by its content ID, with an optional exit animation.
    func closeSubagentPanel(contentID: UUID) {
        closePanel(contentID: contentID, animated: true)
    }

    /// Closes a non-terminal panel by its content ID.
    ///
    /// Used by SwiftUI-hosted panels whose close button lives inside the panel
    /// itself. The method focuses the corresponding split leaf first so the
    /// existing `closeSplitAction` path performs the same model, view and
    /// cleanup work as keyboard and tab-strip closes.
    func closePanel(contentID: UUID, animated: Bool = false) {
        guard let sm = activeSplitManager else { return }
        let leaves = sm.rootNode.allLeafIDs()
        guard let targetLeaf = leaves.first(where: { $0.terminalID == contentID }) else { return }

        let panelView = panelContentViews[contentID]
        let duration = AnimationConfig.duration(AnimationConfig.splitTransitionDuration)

        if animated, duration > 0, let panelView {
            // Animate fade-out before removing.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panelView.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    sm.focusLeaf(id: targetLeaf.leafID)
                    self?.closeSplitAction(nil)
                    self?.refreshTabStrip()
                }
            })
        } else {
            sm.focusLeaf(id: targetLeaf.leafID)
            closeSplitAction(nil)
            refreshTabStrip()
        }
    }

    /// Closes a subagent panel by subagent ID and session ID.
    ///
    /// Searches all panel content views for a matching `SubagentContentView`.
    func closeSubagentPanelBySubagentId(_ subagentId: String, sessionId: String) {
        guard let (contentID, _) = panelContentViews.first(where: { (_, view) in
            guard let subView = view as? SubagentContentView else { return false }
            return subView.subagentId == subagentId && subView.sessionId == sessionId
        }) else { return }
        closeSubagentPanel(contentID: contentID)
    }

    /// Removes all subagent panels for a given session.
    func removeSubagentPanels(forSession sessionId: String) {
        let subagentContentIDs = panelContentViews.compactMap { (id, view) -> UUID? in
            guard let subView = view as? SubagentContentView,
                  subView.sessionId == sessionId else { return nil }
            return id
        }
        for contentID in subagentContentIDs {
            closeSubagentPanel(contentID: contentID)
        }
    }

    private func focusedPaneSnapshot() -> (contentID: UUID, view: NSView, surfaceID: SurfaceID?)? {
        guard let sm = activeSplitManager,
              let focusedLeafID = sm.focusedLeafID else {
            if let resolvedFromResponder = paneSnapshotFromFirstResponder() {
                activeSplitManager?.focusLeaf(id: resolvedFromResponder.leafID)
                return (
                    contentID: resolvedFromResponder.contentID,
                    view: resolvedFromResponder.view,
                    surfaceID: resolvedFromResponder.surfaceID
                )
            }
            return nil
        }

        let leaves = sm.rootNode.allLeafIDs()
        guard let focusedIndex = leaves.firstIndex(where: { $0.leafID == focusedLeafID }) else {
            if let resolvedFromResponder = paneSnapshotFromFirstResponder() {
                activeSplitManager?.focusLeaf(id: resolvedFromResponder.leafID)
                return (
                    contentID: resolvedFromResponder.contentID,
                    view: resolvedFromResponder.view,
                    surfaceID: resolvedFromResponder.surfaceID
                )
            }
            return nil
        }

        let leafViews = collectLeafViews()
        guard focusedIndex < leafViews.count else {
            if let resolvedFromResponder = paneSnapshotFromFirstResponder() {
                activeSplitManager?.focusLeaf(id: resolvedFromResponder.leafID)
                return (
                    contentID: resolvedFromResponder.contentID,
                    view: resolvedFromResponder.view,
                    surfaceID: resolvedFromResponder.surfaceID
                )
            }
            return nil
        }

        let leaf = leaves[focusedIndex]
        let view = leafViews[focusedIndex]
        let resolvedSurfaceID: SurfaceID?

        if let hostView = view as? TerminalHostView {
            resolvedSurfaceID = self.surfaceID(for: hostView)
        } else {
            resolvedSurfaceID = nil
        }

        return (leaf.terminalID, view, resolvedSurfaceID)
    }

    func focusedPaneView() -> NSView? {
        focusedPaneSnapshot()?.view
    }

    private func surfaceID(for hostView: TerminalHostView) -> SurfaceID? {
        if let currentTabID = visibleTabID ?? tabManager.activeTabID,
           tabSurfaceViews[currentTabID] === hostView {
            return tabSurfaceMap[currentTabID]
        }

        return splitSurfaceViews.first(where: { $0.value === hostView })?.key
    }

    /// Synchronizes the domain-focused leaf with the AppKit first responder.
    ///
    /// Browser and subagent panels often install nested responder chains
    /// (`WKWebView`, buttons, text fields). Relying only on SplitManager's
    /// previous `focusedLeafID` can leave toolbar actions targeting the wrong
    /// pane after the user clicks inside panel chrome.
    func syncFocusedLeafSelectionFromFirstResponder() {
        guard let resolved = paneSnapshotFromFirstResponder() else { return }
        activeSplitManager?.focusLeaf(id: resolved.leafID)
    }

    private func paneSnapshotFromFirstResponder() -> (contentID: UUID, view: NSView, surfaceID: SurfaceID?, leafID: UUID)? {
        guard let sm = activeSplitManager else { return nil }
        let leaves = sm.rootNode.allLeafIDs()
        guard !leaves.isEmpty else { return nil }

        let leafViews = collectLeafViews()
        guard leafViews.count == leaves.count else { return nil }

        var currentView: NSView?
        if let firstResponderView = window?.firstResponder as? NSView {
            currentView = firstResponderView
        } else if let firstResponder = window?.firstResponder as? NSResponder {
            currentView = firstResponder.nextResponder as? NSView
        }

        while let view = currentView {
            if let focusedIndex = leafViews.firstIndex(where: { $0 === view }) {
                let leaf = leaves[focusedIndex]
                let resolvedSurfaceID = (view as? TerminalHostView).flatMap(surfaceID(for:))
                return (
                    contentID: leaf.terminalID,
                    view: view,
                    surfaceID: resolvedSurfaceID,
                    leafID: leaf.leafID
                )
            }
            currentView = view.superview
        }

        return nil
    }

    private func firstVisiblePaneView(in container: NSView) -> NSView? {
        for subview in container.subviews.reversed() {
            if let splitView = subview as? NSSplitView {
                if let leaf = collectLeaves(from: splitView).last {
                    return leaf
                }
                continue
            }
            if subview is TerminalHostView || panelContentViews.values.contains(where: { $0 === subview }) {
                return subview
            }
        }
        return nil
    }

    private func promoteTerminalHostViewToPrimary(_ hostView: TerminalHostView) {
        guard let activeTabID = visibleTabID ?? tabManager.activeTabID else {
            terminalSurfaceView = hostView
            return
        }

        terminalSurfaceView = hostView
        tabSurfaceViews[activeTabID] = hostView

        if let promotedSurfaceID = splitSurfaceViews.first(where: { $0.value === hostView })?.key {
            tabSurfaceMap[activeTabID] = promotedSurfaceID
            splitSurfaceViews.removeValue(forKey: promotedSurfaceID)
            if let promotedViewModel = splitViewModels.removeValue(forKey: promotedSurfaceID) {
                tabViewModels[activeTabID] = promotedViewModel
            } else if let promotedViewModel = hostView.terminalViewModel {
                tabViewModels[activeTabID] = promotedViewModel
            }
            return
        }

        if let promotedSurfaceID = surfaceID(for: hostView) {
            tabSurfaceMap[activeTabID] = promotedSurfaceID
        }
        if let promotedViewModel = hostView.terminalViewModel {
            tabViewModels[activeTabID] = promotedViewModel
        }
    }
}
