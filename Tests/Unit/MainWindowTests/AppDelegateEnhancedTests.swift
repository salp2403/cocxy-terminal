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

    func testApplicationShouldHandleReopenReusesHiddenCompletedWindow() {
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(MockTerminalEngine())
        delegate.createMainWindowForTesting(deferSurfaceBootstrap: false)
        guard let originalController = delegate.windowController else {
            XCTFail("Expected a main window controller")
            return
        }

        originalController.window?.orderOut(nil)
        XCTAssertFalse(originalController.window?.isVisible ?? true)

        let result = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertTrue(result)
        XCTAssertTrue(
            delegate.windowController === originalController,
            "Reopening a hidden completed window should reuse the existing controller instead of rebuilding the whole terminal shell"
        )
        XCTAssertTrue(originalController.window?.isVisible == true)
        originalController.window?.orderOut(nil)
    }

    func testDeferredLaunchDoesNotShowWindowBeforeContentSetup() {
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(MockTerminalEngine())

        delegate.createMainWindowForTesting(deferSurfaceBootstrap: true)

        let controller = delegate.windowController
        XCTAssertNotNil(controller)
        XCTAssertFalse(
            controller?.window?.isVisible ?? true,
            "Deferred launch must not flash an empty window before the terminal content tree exists"
        )
        XCTAssertNil(
            controller?.terminalContainerView,
            "Deferred launch keeps content setup out of the socket-ready critical path"
        )
    }

    func testApplicationDidBecomeActiveDoesNotShowIncompleteDeferredWindow() {
        let delegate = AppDelegate()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        delegate.installWindowControllerForTesting(controller)

        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))

        XCTAssertFalse(
            controller.window?.isVisible ?? true,
            "Activation must not order a deferred window before content setup completes"
        )

        controller.completeDeferredWindowSetupIfNeeded()
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))

        XCTAssertTrue(controller.window?.isVisible == true)
        controller.window?.orderOut(nil)
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
