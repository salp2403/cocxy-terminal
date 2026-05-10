// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ContextAwareShortcuts.swift - Pure routing decisions for contextual shortcuts.

import Foundation

enum ContextAwareShortcutSurface: Sendable, Equatable {
    case browser
    case terminal
    case editor
    case other
}

enum ContextAwareShortcutAction: Sendable, Equatable {
    case focusBrowserAddressField
    case openBrowserSplitAndFocusAddressField
}

enum ContextAwareShortcuts {
    static func commandLAction(
        focusedSurface: ContextAwareShortcutSurface,
        browserSurfaceAvailable: Bool
    ) -> ContextAwareShortcutAction {
        if focusedSurface == .browser || browserSurfaceAvailable {
            return .focusBrowserAddressField
        }
        return .openBrowserSplitAndFocusAddressField
    }
}
