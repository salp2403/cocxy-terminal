// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ShortcutHintOverlayMountTests.swift - Runtime mounting for persistent shortcut hints.

import XCTest
@testable import CocxyTerminal

@MainActor
final class ShortcutHintOverlayMountTests: XCTestCase {
    func testAlwaysShowShortcutHintsMountsSidebarTitlebarAndPaneHosts() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)

        let config = UXPolishConfig(
            alwaysShowShortcutHints: true,
            shortcutHintDebugOverlay: false,
            shortcutHintOffsetX: 0,
            shortcutHintOffsetY: 0,
            shortcutHintScale: 1
        )

        controller.refreshShortcutHintsOverlay(config: config, keybindings: .defaults)

        XCTAssertEqual(
            Set(controller.shortcutHintOverlayHosts.keys),
            [.sidebar, .titlebar, .pane],
            "Always-show hints must be mounted in the real sidebar, titlebar, and pane overlay positions"
        )
        XCTAssertTrue(
            controller.shortcutHintOverlayHosts.values.allSatisfy { $0.superview === controller.overlayContainerView },
            "Hint hosts must be mounted on the passthrough overlay layer so they remain visible above chrome and panes"
        )
    }

    func testDisablingAlwaysShowShortcutHintsRemovesMountedHosts() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)

        let enabled = UXPolishConfig(
            alwaysShowShortcutHints: true,
            shortcutHintDebugOverlay: true,
            shortcutHintOffsetX: 0,
            shortcutHintOffsetY: 0,
            shortcutHintScale: 1
        )
        controller.refreshShortcutHintsOverlay(config: enabled, keybindings: .defaults)
        XCTAssertFalse(controller.shortcutHintOverlayHosts.isEmpty)

        controller.refreshShortcutHintsOverlay(config: .defaults, keybindings: .defaults)

        XCTAssertTrue(controller.shortcutHintOverlayHosts.isEmpty)
    }
}
