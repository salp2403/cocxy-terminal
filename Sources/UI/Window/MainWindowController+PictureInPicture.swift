// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+PictureInPicture.swift - Floating terminal panel lifecycle.

import AppKit

@MainActor
extension MainWindowController {

    @discardableResult
    func detachActiveTerminalToPIP() -> Bool {
        guard configService?.current.experimental.pipEnabled == true else { return false }
        guard activeSplitView == nil else { return false }
        guard let tabID = visibleTabID ?? tabManager.activeTabID,
              pipControllers[tabID] == nil,
              let tab = tabManager.tab(for: tabID),
              let container = terminalContainerView,
              let surfaceView = tabSurfaceViews[tabID],
              surfaceView.superview === container else {
            return false
        }

        surfaceView.removeFromSuperview()
        displayedTabID = nil
        refreshVisibleTerminalInteractionState()

        let controller = PIPWindowController(
            tabID: tabID,
            title: "Cocxy PIP - \(tab.displayTitle)",
            detachedView: surfaceView,
            onRestore: { [weak self] tabID, view in
                Task { @MainActor in
                    self?.restorePIP(tabID: tabID, view: view)
                }
            }
        )
        pipControllers[tabID] = controller
        controller.show()
        refreshStatusBar()
        refreshTabStrip(syncFromFirstResponder: false)
        return true
    }

    func restorePIP(tabID: TabID, view: NSView) {
        pipControllers[tabID] = nil
        guard tabManager.tab(for: tabID) != nil else {
            return
        }

        if let surfaceView = view as? CocxyCoreView {
            tabSurfaceViews[tabID] = surfaceView
            terminalSurfaceView = surfaceView
        }

        if tabManager.activeTabID != tabID {
            tabManager.setActive(id: tabID)
        }
        displayedTabID = nil
        handleTabSwitch(to: tabID)
    }

    @objc func detachActiveTerminalToPIPAction(_ sender: Any?) {
        _ = detachActiveTerminalToPIP()
    }
}
