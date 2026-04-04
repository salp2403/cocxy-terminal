// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowControllerTests.swift - Tests for MainWindowController configuration.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - MainWindowController Creation Tests

/// Tests that the MainWindowController correctly creates and configures the window.
@MainActor
final class MainWindowControllerCreationTests: XCTestCase {

    func testWindowControllerCanBeCreatedWithBridge() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertNotNil(
            controller,
            "MainWindowController must be creatable with a bridge"
        )
    }

    func testWindowControllerHoldsReferenceToViewModel() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertNotNil(
            controller.terminalViewModel,
            "MainWindowController must create a TerminalViewModel"
        )
    }

    func testWindowControllerViewModelHasBridge() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertTrue(
            controller.terminalViewModel.ghosttyBridge === bridge,
            "ViewModel must hold a reference to the engine"
        )
    }

    func testWindowControllerUsesCocxyCoreHostViewWhenBridgeIsCocxyCore() {
        let bridge = CocxyCoreBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        XCTAssertTrue(
            controller.terminalSurfaceView is CocxyCoreView,
            "Main window should build a CocxyCoreView when CocxyCore is the selected engine"
        )
    }
}

// MARK: - MainWindowController Window Configuration Tests

/// Tests that the window is configured correctly for terminal use.
@MainActor
final class MainWindowControllerWindowTests: XCTestCase {

    func testWindowHasCorrectTitle() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        XCTAssertEqual(
            controller.window?.title,
            "Cocxy Terminal",
            "Window title must be 'Cocxy Terminal'"
        )
    }

    func testWindowHasMinimumSize() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        let minSize = controller.window?.minSize ?? .zero
        XCTAssertGreaterThanOrEqual(
            minSize.width,
            320,
            "Window minimum width must be at least 320"
        )
        XCTAssertGreaterThanOrEqual(
            minSize.height,
            240,
            "Window minimum height must be at least 240"
        )
    }

    func testWindowContentViewContainsTerminalSurfaceView() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        XCTAssertNotNil(
            controller.terminalSurfaceView,
            "Window must contain a TerminalSurfaceView (inside the split layout)"
        )
        XCTAssertNotNil(
            controller.tabBarView,
            "Window must contain a TabBarView sidebar"
        )
    }

    func testWindowHasTransparentTitlebar() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        XCTAssertTrue(
            controller.window?.titlebarAppearsTransparent ?? false,
            "Window must have transparent titlebar"
        )
    }

    func testWindowHasFullSizeContentView() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.fullSizeContentView),
            "Window must have .fullSizeContentView style"
        )
    }
}
