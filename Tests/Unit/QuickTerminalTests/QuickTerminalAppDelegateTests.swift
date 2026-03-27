// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalAppDelegateTests.swift - Tests for AppDelegate Quick Terminal integration (T-037).

import XCTest
@testable import CocxyTerminal

// MARK: - Quick Terminal AppDelegate Integration Tests

/// Tests that the AppDelegate correctly integrates the QuickTerminalController.
///
/// Covers:
/// - AppDelegate has a quickTerminalController property.
/// - applicationShouldTerminateAfterLastWindowClosed returns false (stays alive for hotkey).
@MainActor
final class QuickTerminalAppDelegateTests: XCTestCase {

    private var sut: AppDelegate!

    override func setUp() {
        super.setUp()
        sut = AppDelegate()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - 1. AppDelegate has quickTerminalController property

    func testAppDelegateHasQuickTerminalControllerProperty() {
        // Before launch, the controller may be nil. But the property must exist.
        // We verify type access compiles and the property is accessible.
        let controller: QuickTerminalController? = sut.quickTerminalController
        XCTAssertNil(controller,
                     "Quick terminal controller must be nil before app launch")
    }

    // MARK: - 2. App should NOT terminate after last window closed

    func testAppShouldNotTerminateAfterLastWindowClosed() {
        // With Quick Terminal, the app must stay alive to respond to the global hotkey.
        let shouldTerminate = sut.applicationShouldTerminateAfterLastWindowClosed(
            NSApplication.shared
        )
        XCTAssertFalse(shouldTerminate,
                       "App must stay alive for Quick Terminal hotkey even with no windows")
    }
}
