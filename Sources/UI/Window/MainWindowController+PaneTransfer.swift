// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+PaneTransfer.swift - Same-window pane transfer helpers.

import AppKit

extension MainWindowController {

    @discardableResult
    func moveSplitSurface(_ surfaceID: SurfaceID, to targetTabID: TabID) -> Bool {
        guard let sourceTabID = tabID(for: surfaceID),
              sourceTabID != targetTabID,
              tabManager.tab(for: targetTabID) != nil,
              tabSurfaceMap[sourceTabID] != surfaceID,
              let movedSurfaceView = splitSurfaceView(surfaceID, in: sourceTabID) else {
            return false
        }

        let sourceManager = tabSplitCoordinator.splitManager(for: sourceTabID)
        let targetManager = tabSplitCoordinator.splitManager(for: targetTabID)
        let sourceLeavesBefore = sourceManager.rootNode.allLeafIDs()
        let targetLeavesBefore = targetManager.rootNode.allLeafIDs()
        let sourceLeafViewsBefore = paneTransferLeafViews(for: sourceTabID)
        let targetLeafViewsBefore = paneTransferLeafViews(for: targetTabID)

        guard sourceLeafViewsBefore.count == sourceLeavesBefore.count,
              targetLeafViewsBefore.count == targetLeavesBefore.count,
              let sourceIndex = sourceLeafViewsBefore.firstIndex(where: {
                  $0 === movedSurfaceView
              }) else {
            return false
        }

        let movedContentID = sourceLeavesBefore[sourceIndex].terminalID
        let movedPanelInfo = sourceManager.panelInfo(for: movedContentID)
        let movedPanelTitle = sourceManager.panelTitle(for: movedContentID)
        let sourceViewsByContentID = Dictionary(
            uniqueKeysWithValues: zip(sourceLeavesBefore, sourceLeafViewsBefore)
                .filter { $0.0.terminalID != movedContentID }
                .map { ($0.0.terminalID, $0.1) }
        )
        let targetViewsByContentIDBefore = Dictionary(
            uniqueKeysWithValues: zip(targetLeavesBefore, targetLeafViewsBefore)
                .map { ($0.0.terminalID, $0.1) }
        )

        guard targetManager.appendExistingContent(
            movedContentID,
            panelInfo: movedPanelInfo,
            title: movedPanelTitle,
            focusNewContent: true
        ) else {
            return false
        }

        guard let movedState = removeSplitSurfaceTracking(surfaceID, from: sourceTabID) else {
            _ = targetManager.detachContent(movedContentID)
            return false
        }

        guard sourceManager.detachContent(movedContentID) != nil else {
            installSplitSurfaceTracking(movedState, in: sourceTabID)
            _ = targetManager.detachContent(movedContentID)
            return false
        }

        movedSurfaceView.removeFromSuperview()
        installSplitSurfaceTracking(movedState, in: targetTabID)

        let inheritedDirectory = surfaceWorkingDirectories[surfaceID]
            ?? tabManager.tab(for: targetTabID)?.workingDirectory
        surfaceImageDetectors.removeValue(forKey: surfaceID)
        surfaceOutputDispatchers.removeValue(forKey: surfaceID)
        wireSurfaceHandlers(
            for: surfaceID,
            tabID: targetTabID,
            in: movedSurfaceView,
            initialWorkingDirectory: inheritedDirectory
        )
        registerSurfaceWithProcessMonitor(surfaceID, tabID: targetTabID)

        applyPaneTransferLayout(
            for: sourceTabID,
            viewsByContentID: sourceViewsByContentID
        )

        var targetViewsByContentID = targetViewsByContentIDBefore
        targetViewsByContentID[movedContentID] = movedSurfaceView
        applyPaneTransferLayout(
            for: targetTabID,
            viewsByContentID: targetViewsByContentID
        )

        if displayedTabID == targetTabID {
            window?.makeFirstResponder(movedSurfaceView)
        }

        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        refreshTabStrip(syncFromFirstResponder: false)
        auroraChromeController?.refreshSources()
        return true
    }

    private struct SplitSurfaceMoveState {
        let surfaceID: SurfaceID
        let surfaceView: TerminalHostView
        let viewModel: TerminalViewModel?
    }

    private func splitSurfaceView(
        _ surfaceID: SurfaceID,
        in tabID: TabID
    ) -> TerminalHostView? {
        if displayedTabID == tabID {
            return splitSurfaceViews[surfaceID]
        }
        return savedTabSplitSurfaceViews[tabID]?[surfaceID]
    }

    private func removeSplitSurfaceTracking(
        _ surfaceID: SurfaceID,
        from tabID: TabID
    ) -> SplitSurfaceMoveState? {
        if displayedTabID == tabID {
            guard let surfaceView = splitSurfaceViews.removeValue(forKey: surfaceID) else {
                return nil
            }
            return SplitSurfaceMoveState(
                surfaceID: surfaceID,
                surfaceView: surfaceView,
                viewModel: splitViewModels.removeValue(forKey: surfaceID)
            )
        }

        guard var storedViews = savedTabSplitSurfaceViews[tabID],
              let surfaceView = storedViews.removeValue(forKey: surfaceID) else {
            return nil
        }
        if storedViews.isEmpty {
            savedTabSplitSurfaceViews.removeValue(forKey: tabID)
        } else {
            savedTabSplitSurfaceViews[tabID] = storedViews
        }

        var storedViewModels = savedTabSplitViewModels[tabID] ?? [:]
        let viewModel = storedViewModels.removeValue(forKey: surfaceID)
        if storedViewModels.isEmpty {
            savedTabSplitViewModels.removeValue(forKey: tabID)
        } else {
            savedTabSplitViewModels[tabID] = storedViewModels
        }

        return SplitSurfaceMoveState(
            surfaceID: surfaceID,
            surfaceView: surfaceView,
            viewModel: viewModel
        )
    }

    private func installSplitSurfaceTracking(
        _ state: SplitSurfaceMoveState,
        in tabID: TabID
    ) {
        if displayedTabID == tabID {
            splitSurfaceViews[state.surfaceID] = state.surfaceView
            if let viewModel = state.viewModel {
                splitViewModels[state.surfaceID] = viewModel
            }
            return
        }

        var storedViews = savedTabSplitSurfaceViews[tabID] ?? [:]
        storedViews[state.surfaceID] = state.surfaceView
        savedTabSplitSurfaceViews[tabID] = storedViews

        if let viewModel = state.viewModel {
            var storedViewModels = savedTabSplitViewModels[tabID] ?? [:]
            storedViewModels[state.surfaceID] = viewModel
            savedTabSplitViewModels[tabID] = storedViewModels
        }
    }

    private func paneTransferLeafViews(for tabID: TabID) -> [NSView] {
        if displayedTabID == tabID {
            return collectLeafViews()
        }

        if let splitView = savedTabSplitViews[tabID] {
            return paneTransferLeaves(from: splitView)
        }

        if let primaryView = tabSurfaceViews[tabID] {
            return [primaryView]
        }

        return []
    }

    private func paneTransferLeaves(from view: NSView) -> [NSView] {
        if let splitView = view as? NSSplitView {
            return splitView.subviews.flatMap { paneTransferLeaves(from: $0) }
        }
        return [view]
    }

    private func applyPaneTransferLayout(
        for tabID: TabID,
        viewsByContentID: [UUID: NSView]
    ) {
        let splitManager = tabSplitCoordinator.splitManager(for: tabID)
        let leaves = splitManager.rootNode.allLeafIDs()

        guard leaves.count > 1 else {
            if displayedTabID == tabID {
                restoreSinglePaneAfterTransfer(
                    tabID: tabID,
                    view: leaves.first.flatMap { viewsByContentID[$0.terminalID] }
                )
            } else {
                savedTabSplitViews.removeValue(forKey: tabID)
                savedTabSplitSurfaceViews.removeValue(forKey: tabID)
                savedTabSplitViewModels.removeValue(forKey: tabID)
                savedTabPanelContentViews.removeValue(forKey: tabID)
            }
            return
        }

        if displayedTabID == tabID {
            rebuildSplitViewHierarchy(
                for: tabID,
                viewsByTerminalIDOverride: viewsByContentID
            )
            return
        }

        if let splitView = makeStoredSplitView(
            from: splitManager.rootNode,
            viewsByTerminalID: viewsByContentID
        ) {
            savedTabSplitViews[tabID] = splitView
        } else {
            savedTabSplitViews.removeValue(forKey: tabID)
        }
    }

    private func restoreSinglePaneAfterTransfer(tabID: TabID, view: NSView?) {
        activeSplitView?.removeFromSuperview()
        activeSplitView = nil

        guard let container = terminalContainerView,
              let view else {
            return
        }

        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view, positioned: .below, relativeTo: nil)

        if let terminalView = view as? TerminalHostView {
            terminalSurfaceView = terminalView
            tabSurfaceViews[tabID] = terminalView
            window?.makeFirstResponder(terminalView)
        }
    }
}
