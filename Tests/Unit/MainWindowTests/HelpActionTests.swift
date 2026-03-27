// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HelpActionTests.swift - Tests for the Help menu action.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Help Action Tests

/// Tests for the `openHelpAction` method on `MainWindowController`.
///
/// Verifies that the Help action:
/// - Responds to the selector.
/// - Does not crash when invoked (even without a real docs directory).
@MainActor
final class HelpActionTests: XCTestCase {

    func testMainWindowControllerRespondsToOpenHelpAction() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertTrue(
            controller.responds(to: #selector(MainWindowController.openHelpAction(_:))),
            "MainWindowController must respond to openHelpAction"
        )
    }

    func testOpenHelpActionDoesNotCrash() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)

        // Should not crash even when docs directory does not exist.
        controller.openHelpAction(nil)
    }
}
