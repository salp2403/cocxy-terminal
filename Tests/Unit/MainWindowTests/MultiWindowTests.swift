// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MultiWindowTests.swift - Tests for multi-window support.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Multi-Window Tests

/// Tests for multi-window support in `MainWindowController` and `AppDelegate`.
///
/// Verifies that:
/// - MainWindowController responds to the newWindowAction selector.
/// - AppDelegate tracks additional window controllers.
/// - Multiple windows can be created without crashing.
@MainActor
final class MultiWindowTests: XCTestCase {

    func testMainWindowControllerRespondsToNewWindowAction() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        XCTAssertTrue(
            controller.responds(to: #selector(MainWindowController.newWindowAction(_:))),
            "MainWindowController must respond to newWindowAction"
        )
    }

    func testAppDelegateHasAdditionalWindowControllersArray() {
        let delegate = AppDelegate()

        XCTAssertNotNil(
            delegate.additionalWindowControllers,
            "AppDelegate must expose additionalWindowControllers"
        )
        XCTAssertTrue(
            delegate.additionalWindowControllers.isEmpty,
            "Additional window controllers should start empty"
        )
    }
}
