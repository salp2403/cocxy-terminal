// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuKeybindingsBinder.swift - Resolves live menu shortcuts from ConfigService.

import AppKit
import Foundation
import os.log

// MARK: - Menu Keybindings Binder

/// Applies a `KeybindingsConfig` onto an `NSMenu` tree so menu-bar
/// shortcuts reflect the user-editable keybindings catalog instead of the
/// hardcoded defaults.
///
/// ## How it works
///
/// Each rebindable `NSMenuItem` is tagged at construction time with a stable
/// catalog id via `NSMenuItem.identifier` (e.g. `"tab.new"`,
/// `"split.horizontal"`). At bind time the binder walks the menu tree,
/// looks each tagged item up in the supplied config, and rewrites its
/// `keyEquivalent` plus `keyEquivalentModifierMask` to match.
///
/// ## What stays untouched
///
/// Menu items without an identifier are treated as non-rebindable (About,
/// Quit, Cut/Copy/Paste, Undo/Redo, Hide/Show, Full Screen, separators,
/// submenus). The binder never rewrites them.
///
/// ## Hot-reload
///
/// `AppDelegate` subscribes to `ConfigService.configChangedPublisher` and
/// calls `apply(_:to:)` each time the TOML file changes on disk, so a
/// shortcut edited in Preferences takes effect live — no restart required.
///
/// ## Graceful degradation
///
/// - An unknown action id (config drift, stale file) is ignored silently.
/// - A blank shortcut ("no binding") clears the menu item's equivalent.
/// - A shortcut that parses but cannot be expressed as a single AppKit
///   key equivalent (e.g. a named key AppKit does not recognise) is logged
///   via `os_log` and skipped. The menu item keeps its previous value.
/// - Duplicates inside the config are applied as-is: AppKit's normal
///   first-match semantics on `performKeyEquivalent` apply. Conflicts are
///   blocked by the editor's save path, so duplicates in the live file are
///   treated as legitimate user intent.
///
/// - SeeAlso: `KeybindingsConfig`, `KeybindingAction`, `KeybindingShortcut`.
enum MenuKeybindingsBinder {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "MenuKeybindingsBinder"
    )

    // MARK: - Identifier Bridge

    /// Attaches a catalog action id to an `NSMenuItem` so the binder can
    /// recognise it later.
    ///
    /// Menu items built in `AppDelegate+MenuSetup` use this helper instead
    /// of assigning `keyEquivalent` directly. The initial default shortcut
    /// is also applied here so the menu renders correctly until the binder
    /// has a chance to overlay the user's config.
    ///
    /// - Parameters:
    ///   - item: The menu item to tag.
    ///   - action: The catalog action to associate.
    static func tag(_ item: NSMenuItem, with action: KeybindingAction) {
        item.identifier = identifier(for: action.id)
        apply(action.defaultShortcut, to: item)
    }

    /// Returns the catalog action id associated with a tagged menu item, or
    /// `nil` when the item was not registered via `tag(_:with:)`.
    static func actionId(of item: NSMenuItem) -> String? {
        guard let rawValue = item.identifier?.rawValue,
              rawValue.hasPrefix(identifierPrefix) else {
            return nil
        }
        return String(rawValue.dropFirst(identifierPrefix.count))
    }

    // MARK: - Apply

    /// Walks `menu` and every submenu, overlaying shortcuts from `config`
    /// onto every tagged menu item.
    ///
    /// - Parameters:
    ///   - config: The `[keybindings]` snapshot to apply.
    ///   - menu: The top-level menu (usually `NSApplication.shared.mainMenu`).
    static func apply(_ config: KeybindingsConfig, to menu: NSMenu) {
        walk(menu) { item in
            guard let actionId = actionId(of: item) else { return }

            let raw = config.shortcutString(for: actionId)
            guard !raw.isEmpty else {
                // Explicit "no binding".
                clear(item)
                return
            }

            guard let shortcut = KeybindingShortcut.parse(raw) else {
                logger.warning(
                    "Invalid shortcut \(raw, privacy: .public) for action \(actionId, privacy: .public); keeping previous binding."
                )
                return
            }

            guard shortcut.isAssignableToMenuItem else {
                logger.warning(
                    "Shortcut \(raw, privacy: .public) for action \(actionId, privacy: .public) cannot be assigned to a menu item; keeping previous binding."
                )
                return
            }

            apply(shortcut, to: item)
        }
    }

    // MARK: - Private

    /// Prefix used to distinguish keybinding-managed menu items from
    /// arbitrary identifiers that AppKit may assign to other items.
    private static let identifierPrefix = "keybinding."

    private static func identifier(for actionId: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("\(identifierPrefix)\(actionId)")
    }

    /// Writes `shortcut` onto `item`.
    private static func apply(_ shortcut: KeybindingShortcut, to item: NSMenuItem) {
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierMask
    }

    /// Clears the menu item's shortcut entirely.
    private static func clear(_ item: NSMenuItem) {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
    }

    /// Depth-first traversal of a menu tree, yielding every menu item.
    private static func walk(_ menu: NSMenu, visit: (NSMenuItem) -> Void) {
        for item in menu.items {
            visit(item)
            if let submenu = item.submenu {
                walk(submenu, visit: visit)
            }
        }
    }
}
