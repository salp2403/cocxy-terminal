// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateEnhancedTests.swift - Tests for enhanced AppDelegate lifecycle (T-012).

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - AppDelegate Lifecycle Tests

/// Tests for AppDelegate lifecycle management: terminate, reopen, shouldTerminate.
@MainActor
final class AppDelegateLifecycleTests: XCTestCase {

    func testApplicationShouldNotTerminateAfterLastWindowClosed() {
        let delegate = AppDelegate()
        let result = delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        XCTAssertFalse(
            result,
            "App must stay alive for Quick Terminal hotkey even with no windows (T-037)"
        )
    }

    func testApplicationShouldHandleReopenReturnsTrue() {
        let delegate = AppDelegate()
        let result = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )
        XCTAssertTrue(
            result,
            "App must handle reopen when there are no visible windows"
        )
    }
}

// MARK: - AppDelegate Config Integration Tests

/// Tests that AppDelegate creates and holds a ConfigService.
@MainActor
final class AppDelegateConfigTests: XCTestCase {

    func testAppDelegateHasConfigServiceProperty() {
        let delegate = AppDelegate()
        // ConfigService is nil before applicationDidFinishLaunching.
        // This verifies the property exists.
        XCTAssertNil(
            delegate.configService,
            "ConfigService must be nil before app launch"
        )
    }
}
