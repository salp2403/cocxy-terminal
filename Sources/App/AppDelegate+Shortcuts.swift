// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Shortcuts.swift - Local Shortcuts.app action handlers.

import AppKit

extension AppDelegate {

    @MainActor
    func activateForShortcut() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = focusedWindowController()?.window ?? windowController?.window {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    func sendTextToActiveTerminalForShortcut(
        _ text: String,
        pressReturn: Bool
    ) -> Bool {
        let payload = pressReturn ? text + "\r" : text
        guard let controller = focusedWindowController() ?? windowController,
              let surfaceID = controller.focusedSplitSurfaceView?.terminalViewModel?.surfaceID
                ?? controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID else {
            return false
        }
        controller.terminalEngine(for: surfaceID).sendText(payload, to: surfaceID)
        return true
    }

    @MainActor
    func openNotebookPanelForShortcut() -> Bool {
        guard let controller = focusedWindowController() ?? windowController else {
            return false
        }
        controller.splitWithNotebookAction(nil)
        return true
    }
}
