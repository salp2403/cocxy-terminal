// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ShortcutHintRegistry.swift - Stable shortcut hint metadata.

import Foundation

enum ShortcutHintPlacement: String, Sendable, Equatable, Hashable, CaseIterable {
    case sidebar
    case titlebar
    case pane
    case debug
}

struct ShortcutHint: Identifiable, Sendable, Equatable {
    let id: String
    let actionId: String
    let title: String
    let placement: ShortcutHintPlacement
    let debugOnly: Bool
}

struct ShortcutHintRegistry: Sendable, Equatable {
    let hints: [ShortcutHint]

    static let defaults = ShortcutHintRegistry(hints: [
        ShortcutHint(
            id: "window.focusLocation.titlebar",
            actionId: KeybindingActionCatalog.windowFocusLocation.id,
            title: "Location",
            placement: .titlebar,
            debugOnly: false
        ),
        ShortcutHint(
            id: "window.commandPalette.sidebar",
            actionId: KeybindingActionCatalog.windowCommandPalette.id,
            title: "Command Palette",
            placement: .sidebar,
            debugOnly: false
        ),
        ShortcutHint(
            id: "split.close.pane",
            actionId: KeybindingActionCatalog.splitClose.id,
            title: "Close Split",
            placement: .pane,
            debugOnly: false
        ),
        ShortcutHint(
            id: "debug.shortcutHintTuning",
            actionId: KeybindingActionCatalog.windowFocusLocation.id,
            title: "Shortcut Hint Tuning",
            placement: .debug,
            debugOnly: true
        ),
    ])

    func visibleHints(alwaysShow: Bool, isDebugOverlayVisible: Bool) -> [ShortcutHint] {
        guard alwaysShow else { return [] }
        return hints.filter { hint in
            !hint.debugOnly || isDebugOverlayVisible
        }
    }

    func visibleHints(
        placement: ShortcutHintPlacement,
        alwaysShow: Bool,
        isDebugOverlayVisible: Bool
    ) -> [ShortcutHint] {
        visibleHints(alwaysShow: alwaysShow, isDebugOverlayVisible: isDebugOverlayVisible)
            .filter { $0.placement == placement }
    }
}
