// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ShortcutHintRegistrySwiftTestingTests.swift - Always-show shortcut hints.

import Testing
@testable import CocxyTerminal

@Suite("UX polish - shortcut hint registry")
struct ShortcutHintRegistrySwiftTestingTests {

    @Test("default UX polish config keeps always-show hints off")
    func defaultConfigKeepsAlwaysShowHintsOff() {
        #expect(CocxyConfig.defaults.uxPolish.alwaysShowShortcutHints == false)
        #expect(CocxyConfig.defaults.uxPolish.shortcutHintDebugOverlay == false)
    }

    @Test("registry filters persistent hints unless always-show is enabled")
    func registryFiltersPersistentHintsByPreference() {
        let registry = ShortcutHintRegistry.defaults

        #expect(registry.visibleHints(alwaysShow: false, isDebugOverlayVisible: false).isEmpty)
        #expect(
            registry.visibleHints(alwaysShow: true, isDebugOverlayVisible: false)
                .contains { $0.actionId == KeybindingActionCatalog.windowFocusLocation.id }
        )
    }

    @Test("debug overlay exposes tuning hints only when enabled")
    func registryShowsDebugHintsOnlyWhenDebugOverlayEnabled() {
        let registry = ShortcutHintRegistry.defaults

        #expect(
            registry.visibleHints(alwaysShow: true, isDebugOverlayVisible: false)
                .allSatisfy { !$0.debugOnly }
        )
        #expect(
            registry.visibleHints(alwaysShow: true, isDebugOverlayVisible: true)
                .contains { $0.debugOnly }
        )
    }
}
