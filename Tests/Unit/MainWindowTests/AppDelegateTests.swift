// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateTests.swift - Tests for AppDelegate lifecycle management.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - AppDelegate Bridge Initialization Tests

/// Tests that the AppDelegate exposes bridge lifecycle state correctly.
@MainActor
final class AppDelegateBridgeTests: XCTestCase {

    func testAppDelegateHasBridgeProperty() {
        let delegate = AppDelegate()
        // Bridge is nil before applicationDidFinishLaunching.
        XCTAssertNil(
            delegate.bridge,
            "Bridge must be nil before app launch"
        )
    }

    func testAppDelegateHasWindowControllerProperty() {
        let delegate = AppDelegate()
        // Window controller is nil before applicationDidFinishLaunching.
        XCTAssertNil(
            delegate.windowController,
            "WindowController must be nil before app launch"
        )
    }
}
