// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraShortcutLabelSwiftTestingTests.swift - Pure coverage for the
// palette/new-tab label resolver used by the Aurora sidebar tray.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("MainWindowController.auroraShortcutLabel — tray label resolution")
struct AuroraShortcutLabelSwiftTestingTests {

    // MARK: - Helpers

    /// Builds a `KeybindingsConfig` on top of the defaults with
    /// overrides applied via `copying`. The helper keeps every test
    /// self-contained so a regression in one field cannot bleed into
    /// the others.
    private func config(
        newTab: String? = nil,
        customOverrides: [String: String] = [:]
    ) -> KeybindingsConfig {
        let defaults = KeybindingsConfig.defaults
        return KeybindingsConfig(
            newTab: newTab ?? defaults.newTab,
            closeTab: defaults.closeTab,
            nextTab: defaults.nextTab,
            prevTab: defaults.prevTab,
            splitVertical: defaults.splitVertical,
            splitHorizontal: defaults.splitHorizontal,
            gotoAttention: defaults.gotoAttention,
            toggleQuickTerminal: defaults.toggleQuickTerminal,
            customOverrides: customOverrides
        )
    }

    // MARK: - Default binding

    @Test
    func defaultWindowCommandPaletteReturnsCatalogPrettyLabel() {
        let label = MainWindowController.auroraShortcutLabel(
            for: KeybindingActionCatalog.windowCommandPalette,
            in: config()
        )
        #expect(label == KeybindingActionCatalog.windowCommandPalette.defaultShortcut.prettyLabel)
        // `KeybindingShortcut.prettyLabel` emits modifiers in the
        // macOS-canonical `⌃⌥⇧⌘<key>` order so `cmd+shift+p` prints
        // as `⇧⌘P`, not `⌘⇧P`.
        #expect(label == "⇧⌘P")
    }

    @Test
    func defaultTabNewReturnsCatalogPrettyLabel() {
        let label = MainWindowController.auroraShortcutLabel(
            for: KeybindingActionCatalog.tabNew,
            in: config()
        )
        #expect(label == KeybindingActionCatalog.tabNew.defaultShortcut.prettyLabel)
        #expect(label == "⌘T")
    }

    // MARK: - Custom binding

    @Test
    func customTabNewLegacyFieldReturnsPrettyLabelForNewValue() {
        let cfg = config(newTab: "cmd+shift+n")
        let label = MainWindowController.auroraShortcutLabel(
            for: KeybindingActionCatalog.tabNew,
            in: cfg
        )
        #expect(label != "⌘T",
                "A remapped tab.new binding must not surface the catalog default label")
        #expect(label.contains("N"),
                "The pretty label should reflect the new key (N) the user bound")
    }

    @Test
    func customWindowCommandPaletteOverrideReturnsPrettyLabelForNewValue() {
        let cfg = config(customOverrides: [
            KeybindingActionCatalog.windowCommandPalette.id: "ctrl+space",
        ])
        let label = MainWindowController.auroraShortcutLabel(
            for: KeybindingActionCatalog.windowCommandPalette,
            in: cfg
        )
        #expect(label != "⌘⇧P",
                "A remapped window.commandPalette binding must not surface the catalog default label")
        #expect(label.contains("⌃") || label.contains("Space") || label.contains("space"),
                "The pretty label should reflect the ctrl+space binding the user stored")
    }

    // MARK: - Cleared binding (the regression guard for finding P3)

    @Test
    func clearedLegacyTabNewReturnsEmDash() {
        let cfg = config(newTab: "")
        let label = MainWindowController.auroraShortcutLabel(
            for: KeybindingActionCatalog.tabNew,
            in: cfg
        )
        #expect(label == "—",
                "When the user clears tab.new the tray must show the em-dash placeholder, not the catalog default")
    }

    @Test
    func clearedWindowCommandPaletteOverrideReturnsEmDash() {
        let cfg = config(customOverrides: [
            KeybindingActionCatalog.windowCommandPalette.id: "",
        ])
        let label = MainWindowController.auroraShortcutLabel(
            for: KeybindingActionCatalog.windowCommandPalette,
            in: cfg
        )
        #expect(label == "—",
                "An empty customOverrides entry must be treated as an intentional clear, not a parse error")
    }

    // The tolerant `KeybindingShortcut.parse` accepts arbitrary base
    // keys (anything non-empty after the last `+`), so there is no
    // "unparseable but non-empty" state to guard against — malformed
    // strings end up showing a best-effort pretty label with no
    // modifiers. That means only two paths matter for the tray:
    // (1) empty string → em-dash placeholder, (2) anything else →
    // pretty label. Both are covered above.
}
