// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+MenuValidation.swift - Focus-aware global menu validation.

import AppKit

extension MainWindowController: NSMenuItemValidation {
    private static let terminalScrollMenuActions: [Selector] = [
        #selector(scrollTerminalPageUpAction(_:)),
        #selector(scrollTerminalPageDownAction(_:)),
        #selector(scrollTerminalToTopAction(_:)),
        #selector(scrollTerminalToBottomAction(_:)),
    ]

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action,
              Self.terminalScrollMenuActions.contains(action) else {
            return true
        }

        return window?.firstResponder is TerminalHostView
    }
}
