// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuKeybindingsBinderSwiftTests.swift
//
// Unit coverage for `MenuKeybindingsBinder.apply(_:to:)`, including identifier
// tagging, modifier-mask resolution, graceful fallbacks, idempotency, and
// hot-reload behavior.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("MenuKeybindingsBinder")
@MainActor
struct MenuKeybindingsBinderSwiftTests {

    // MARK: - Helpers

    /// Builds a menu tree with a single tagged item driven by the supplied
    /// catalog action. Returns the root menu plus the tagged item so tests
    /// can inspect the item directly.
    private func makeMenu(
        tagging action: KeybindingAction,
        title: String = "Tagged Item"
    ) -> (menu: NSMenu, item: NSMenuItem) {
        let menu = NSMenu(title: "Root")
        let item = NSMenuItem(
            title: title,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(item, with: action)
        menu.addItem(item)
        return (menu, item)
    }

    /// Convenience: makes a `KeybindingsConfig` whose custom overrides
    /// carry the given `(actionId, canonical)` pairs on top of the defaults.
    private func config(with overrides: [String: String]) -> KeybindingsConfig {
        let defaults = KeybindingsConfig.defaults
        return KeybindingsConfig(
            newTab: overrides[KeybindingActionCatalog.tabNew.id] ?? defaults.newTab,
            closeTab: overrides[KeybindingActionCatalog.tabClose.id] ?? defaults.closeTab,
            nextTab: overrides[KeybindingActionCatalog.tabNext.id] ?? defaults.nextTab,
            prevTab: overrides[KeybindingActionCatalog.tabPrevious.id] ?? defaults.prevTab,
            splitVertical: overrides[KeybindingActionCatalog.splitVertical.id] ?? defaults.splitVertical,
            splitHorizontal: overrides[KeybindingActionCatalog.splitHorizontal.id] ?? defaults.splitHorizontal,
            gotoAttention: overrides[KeybindingActionCatalog.remoteGoToAttention.id] ?? defaults.gotoAttention,
            toggleQuickTerminal: overrides[KeybindingActionCatalog.windowQuickTerminal.id] ?? defaults.toggleQuickTerminal,
            customOverrides: overrides.filter { pair in
                !KeybindingActionCatalog.legacyFieldMapping.values.contains(pair.key)
            }
        )
    }

    // MARK: - Applying Config

    @Test("apply updates keyEquivalent from config")
    func applyUpdatesKeyEquivalentFromConfig() {
        let (menu, item) = makeMenu(tagging: KeybindingActionCatalog.tabNew)

        // Default is cmd+t; rebind to cmd+shift+t.
        let keybindings = config(with: [KeybindingActionCatalog.tabNew.id: "cmd+shift+t"])
        MenuKeybindingsBinder.apply(keybindings, to: menu)

        #expect(item.keyEquivalent == "t")
        #expect(item.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("apply falls back to default when config missing action")
    func applyFallsBackToDefaultWhenConfigMissingAction() {
        let action = KeybindingActionCatalog.splitHorizontal
        let (menu, item) = makeMenu(tagging: action)

        // `KeybindingsConfig.defaults` mirrors the catalog defaults exactly,
        // so the binder should not change the key equivalent.
        MenuKeybindingsBinder.apply(.defaults, to: menu)

        #expect(item.keyEquivalent == action.defaultShortcut.menuKeyEquivalent)
        #expect(item.keyEquivalentModifierMask == action.defaultShortcut.modifierMask)
    }

    @Test("apply skips built-in menu items without action id")
    func applySkipsBuiltInMenuItemsWithoutActionID() {
        let menu = NSMenu(title: "Root")
        let untagged = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        untagged.keyEquivalentModifierMask = [.command]
        menu.addItem(untagged)

        // Config with a custom override for an action that does NOT match the
        // untagged item. Binder must leave the item untouched.
        let keybindings = config(with: [KeybindingActionCatalog.tabNew.id: "cmd+y"])
        MenuKeybindingsBinder.apply(keybindings, to: menu)

        #expect(untagged.keyEquivalent == "q")
        #expect(untagged.keyEquivalentModifierMask == [.command])
    }

    @Test("apply handles defaults config without crashing")
    func applyHandlesEmptyKeybindingsConfigWithoutCrashing() {
        let (menu, item) = makeMenu(tagging: KeybindingActionCatalog.editorFind)

        MenuKeybindingsBinder.apply(.defaults, to: menu)
        #expect(item.keyEquivalent == "f")
        #expect(item.keyEquivalentModifierMask == [.command])
    }

    @Test("apply updates modifier mask for complex combo")
    func applyUpdatesModifierMaskCorrectly() {
        let (menu, item) = makeMenu(tagging: KeybindingActionCatalog.tabMoveToNewWindow)

        let keybindings = config(with: [
            KeybindingActionCatalog.tabMoveToNewWindow.id: "cmd+ctrl+alt+shift+m",
        ])
        MenuKeybindingsBinder.apply(keybindings, to: menu)

        #expect(item.keyEquivalent == "m")
        #expect(item.keyEquivalentModifierMask == [.command, .control, .option, .shift])
    }

    // MARK: - Idempotency & Hot-Reload

    @Test("apply is idempotent on same config")
    func applyIsIdempotentOnSameConfig() {
        let (menu, item) = makeMenu(tagging: KeybindingActionCatalog.splitVertical)

        let keybindings = config(with: [KeybindingActionCatalog.splitVertical.id: "cmd+alt+v"])

        MenuKeybindingsBinder.apply(keybindings, to: menu)
        let firstEquivalent = item.keyEquivalent
        let firstMask = item.keyEquivalentModifierMask

        // Applying the same config again yields identical results.
        MenuKeybindingsBinder.apply(keybindings, to: menu)

        #expect(item.keyEquivalent == firstEquivalent)
        #expect(item.keyEquivalentModifierMask == firstMask)
    }

    @Test("hot reload applies new config to existing menu")
    func hotReloadAppliesNewConfigToExistingMenus() {
        let (menu, item) = makeMenu(tagging: KeybindingActionCatalog.tabClose)

        // Phase 1: first config.
        let first = config(with: [KeybindingActionCatalog.tabClose.id: "cmd+shift+w"])
        MenuKeybindingsBinder.apply(first, to: menu)
        #expect(item.keyEquivalent == "w")
        #expect(item.keyEquivalentModifierMask == [.command, .shift])

        // Phase 2: user rebinds to Cmd+Option+K — binder must overwrite.
        let second = config(with: [KeybindingActionCatalog.tabClose.id: "cmd+alt+k"])
        MenuKeybindingsBinder.apply(second, to: menu)

        #expect(item.keyEquivalent == "k")
        #expect(item.keyEquivalentModifierMask == [.command, .option])
    }

    // MARK: - Graceful Degradation

    @Test("invalid shortcut in config keeps previous binding")
    func invalidShortcutInConfigLogsWarningAndSkipsItem() {
        let action = KeybindingActionCatalog.tabNew
        let (menu, item) = makeMenu(tagging: action)

        // Seed with a known-good config so we have a reference state to
        // compare against after the bad one arrives.
        let good = config(with: [action.id: "cmd+alt+n"])
        MenuKeybindingsBinder.apply(good, to: menu)
        let priorEquivalent = item.keyEquivalent
        let priorMask = item.keyEquivalentModifierMask

        // Now feed an invalid shortcut. The binder must preserve the prior
        // state rather than crash or clear the equivalent.
        let bad = config(with: [action.id: "cmd+notarealkey+gibberish"])
        MenuKeybindingsBinder.apply(bad, to: menu)

        #expect(item.keyEquivalent == priorEquivalent)
        #expect(item.keyEquivalentModifierMask == priorMask)
    }

    // MARK: - Catalog Entry → Menu Shortcut

    @Test("menuKeyEquivalent resolves named keys for arrow shortcuts")
    func menuKeyEquivalentResolvesArrowKeys() {
        let (menu, item) = makeMenu(tagging: KeybindingActionCatalog.navigateSplitLeft)

        MenuKeybindingsBinder.apply(.defaults, to: menu)

        let expected = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        #expect(item.keyEquivalent == expected)
        #expect(item.keyEquivalentModifierMask == [.command, .option])
    }

    // MARK: - Nested Menus

    @Test("apply walks into submenus")
    func applyWalksSubmenus() {
        let root = NSMenu(title: "Root")
        let submenuHost = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "View")
        submenuHost.submenu = submenu
        root.addItem(submenuHost)

        let nested = NSMenuItem(
            title: "Tab 5",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        MenuKeybindingsBinder.tag(nested, with: KeybindingActionCatalog.tabGoto5)
        submenu.addItem(nested)

        let keybindings = config(with: [
            KeybindingActionCatalog.tabGoto5.id: "cmd+alt+5",
        ])

        // Binder must descend into the submenu and rewrite the nested item.
        MenuKeybindingsBinder.apply(keybindings, to: root)

        #expect(nested.keyEquivalent == "5")
        #expect(nested.keyEquivalentModifierMask == [.command, .option])
    }

    // MARK: - Pretty Shortcut Helper

    @Test("prettyShortcut resolves live label for custom binding")
    func prettyShortcutResolvesLiveLabel() {
        let keybindings = config(with: [KeybindingActionCatalog.tabNew.id: "cmd+shift+t"])
        let label = MenuKeybindingsBinder.prettyShortcut(
            for: KeybindingActionCatalog.tabNew.id,
            in: keybindings
        )
        #expect(label == "\u{21E7}\u{2318}T")
    }

    @Test("prettyShortcut returns nil for empty binding")
    func prettyShortcutReturnsNilForEmpty() {
        let keybindings = KeybindingsConfig(
            newTab: "",
            closeTab: KeybindingsConfig.defaults.closeTab,
            nextTab: KeybindingsConfig.defaults.nextTab,
            prevTab: KeybindingsConfig.defaults.prevTab,
            splitVertical: KeybindingsConfig.defaults.splitVertical,
            splitHorizontal: KeybindingsConfig.defaults.splitHorizontal,
            gotoAttention: KeybindingsConfig.defaults.gotoAttention,
            toggleQuickTerminal: KeybindingsConfig.defaults.toggleQuickTerminal
        )
        let label = MenuKeybindingsBinder.prettyShortcut(
            for: KeybindingActionCatalog.tabNew.id,
            in: keybindings
        )
        #expect(label == nil)
    }

    // MARK: - Tag Identifier Round-Trip

    @Test("tag writes a recognizable identifier")
    func tagIdentifierRoundTrip() {
        let item = NSMenuItem(title: "X", action: nil, keyEquivalent: "")
        MenuKeybindingsBinder.tag(item, with: KeybindingActionCatalog.splitClose)

        #expect(MenuKeybindingsBinder.actionId(of: item) == KeybindingActionCatalog.splitClose.id)
    }

    @Test("actionId returns nil for plain menu items")
    func actionIdIgnoresUntaggedItems() {
        let item = NSMenuItem(title: "Plain", action: nil, keyEquivalent: "")
        #expect(MenuKeybindingsBinder.actionId(of: item) == nil)
    }
}
