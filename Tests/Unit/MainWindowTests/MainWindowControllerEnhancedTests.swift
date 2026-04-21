// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowControllerEnhancedTests.swift - Tests for enhanced MainWindowController (T-012).

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Window Style Mask Tests

/// Tests that the window has the correct NSWindow.StyleMask for a native macOS terminal.
@MainActor
final class MainWindowStyleMaskTests: XCTestCase {

    func testWindowHasTitledStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.titled),
            "Window must have .titled style"
        )
    }

    func testWindowHasClosableStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.closable),
            "Window must have .closable style"
        )
    }

    func testWindowHasMiniaturizableStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.miniaturizable),
            "Window must have .miniaturizable style"
        )
    }

    func testWindowHasResizableStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.resizable),
            "Window must have .resizable style"
        )
    }

    func testWindowHasFullSizeContentViewStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.fullSizeContentView),
            "Window must have .fullSizeContentView style"
        )
    }
}

// MARK: - Window Titlebar Tests

/// Tests that the titlebar is configured for a transparent, modern macOS look.
@MainActor
final class MainWindowTitlebarTests: XCTestCase {

    func testTitlebarAppearsTransparent() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertTrue(
            controller.window?.titlebarAppearsTransparent ?? false,
            "Titlebar must appear transparent"
        )
    }

    func testDefaultTitleIsCocxyTerminal() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertEqual(
            controller.window?.title,
            "Cocxy Terminal",
            "Default window title must be 'Cocxy Terminal'"
        )
    }
}

// MARK: - Window Size and Position Tests

/// Tests for window sizing, minimum size, and position persistence.
@MainActor
final class MainWindowSizeTests: XCTestCase {

    func testWindowHasMinimumWidth() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let minSize = controller.window?.minSize ?? .zero
        XCTAssertGreaterThanOrEqual(
            minSize.width,
            320,
            "Window minimum width must be at least 320"
        )
    }

    func testWindowHasMinimumHeight() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let minSize = controller.window?.minSize ?? .zero
        XCTAssertGreaterThanOrEqual(
            minSize.height,
            240,
            "Window minimum height must be at least 240"
        )
    }

    func testWindowHasFrameAutosaveName() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let autosaveName = controller.window?.frameAutosaveName ?? ""
        XCTAssertFalse(
            autosaveName.isEmpty,
            "Window must have a non-empty frame autosave name"
        )
    }

    func testWindowIsNotReleasedWhenClosed() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertFalse(
            controller.window?.isReleasedWhenClosed ?? true,
            "Window must not be released when closed"
        )
    }
}

// MARK: - Window Delegate Tests

/// Tests that the NSWindowDelegate methods are properly implemented.
@MainActor
final class MainWindowDelegateTests: XCTestCase {

    func testWindowDelegateIsSetToController() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertTrue(
            controller.window?.delegate === controller,
            "Window delegate must be the controller itself"
        )
    }

    func testWindowWillCloseCallsDestroyTerminalSurface() {
        // This test verifies that closing the window triggers cleanup.
        // We verify by checking the viewModel state after close notification.
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Mark the viewModel as running so we can verify it stops.
        let fakeSurfaceID = SurfaceID()
        controller.terminalViewModel.markRunning(surfaceID: fakeSurfaceID)
        XCTAssertTrue(controller.terminalViewModel.isRunning)

        // Simulate the windowWillClose notification.
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        // After close, the viewModel should be stopped.
        XCTAssertFalse(
            controller.terminalViewModel.isRunning,
            "Closing the window must stop the terminal viewModel"
        )
    }
}

// MARK: - Window Background Color Tests

/// Tests that the window background color is set correctly.
@MainActor
final class MainWindowBackgroundTests: XCTestCase {

    func testWindowHasNonNilBackgroundColor() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertNotNil(
            controller.window?.backgroundColor,
            "Window must have a background color set"
        )
    }
}

// MARK: - Config Integration Tests

/// Tests that MainWindowController integrates with ConfigService.
@MainActor
final class MainWindowConfigIntegrationTests: XCTestCase {

    func testWindowControllerAcceptsConfigService() {
        let bridge = MockTerminalEngine()
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let configService = ConfigService(fileProvider: fileProvider)
        let controller = MainWindowController(bridge: bridge, configService: configService)
        XCTAssertNotNil(
            controller,
            "MainWindowController must accept a ConfigService parameter"
        )
    }

    func testWindowSizeReflectsConfigDimensions() throws {
        let toml = """
        [appearance]
        font-size = 14.0
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)

        // The window should have a reasonable size (not zero).
        let frame = controller.window?.frame ?? .zero
        XCTAssertGreaterThan(
            frame.width,
            0,
            "Window width must be greater than 0 when config is provided"
        )
        XCTAssertGreaterThan(
            frame.height,
            0,
            "Window height must be greater than 0 when config is provided"
        )
    }

    func testTopTabPositionUsesTopLevelStripOnlyWhenAuroraDisabled() throws {
        let toml = """
        [appearance]
        tab-position = "top"
        aurora-enabled = false
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)

        XCTAssertTrue(
            controller.usesTopLevelTabsInHorizontalStrip,
            "Classic top mode must render top-level tabs, not split panes"
        )
    }

    func testTopTabPositionKeepsAuroraSidebarWhenAuroraDefaultsOn() throws {
        let toml = """
        [appearance]
        tab-position = "top"
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)

        XCTAssertFalse(
            controller.usesTopLevelTabsInHorizontalStrip,
            "Aurora is enabled by default and owns its own sidebar instead of reusing classic top tabs"
        )
    }

    func testTopTabStripCloseFocusedPaneCollapsesSplitWithoutClosingWorkspaceTab() throws {
        let toml = """
        [general]
        confirm-close-process = false

        [appearance]
        tab-position = "top"
        aurora-enabled = false
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }
        controller.newTabAction(nil)

        guard let strip = controller.horizontalTabStripView as? HorizontalTabStripView,
              let activeTabID = controller.tabManager.activeTabID else {
            XCTFail("Expected a visible top strip and active tab")
            return
        }
        let tabCountBefore = controller.tabManager.tabs.count

        strip.onSplitSideBySide?()

        XCTAssertTrue(
            controller.usesTopLevelTabsInHorizontalStrip,
            "The regression only applies to classic top-level tab mode"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            2,
            "The split toolbar action should create a second pane in the active workspace tab"
        )
        XCTAssertEqual(
            strip.tabs.count,
            tabCountBefore,
            "In top mode the strip must keep showing workspace tabs, not split leaves"
        )

        strip.onClosePanel?()

        XCTAssertNil(
            controller.activeSplitView,
            "The right-side close action in top mode must collapse the visual split hierarchy"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            1,
            "Closing the focused pane must also collapse the split model back to one leaf"
        )
        XCTAssertEqual(
            controller.tabManager.tabs.count,
            tabCountBefore,
            "Closing the focused pane must not close the workspace tab shown in the top strip"
        )
        XCTAssertEqual(
            controller.tabManager.activeTabID,
            activeTabID,
            "The active workspace tab should remain selected after closing its focused split"
        )
    }

    func testTopTabStripCloseFocusedPaneWaitsForConfirmation() throws {
        let toml = """
        [general]
        confirm-close-process = true

        [appearance]
        tab-position = "top"
        aurora-enabled = false
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }
        controller.newTabAction(nil)

        guard let strip = controller.horizontalTabStripView as? HorizontalTabStripView,
              let activeTabID = controller.tabManager.activeTabID else {
            XCTFail("Expected a visible top strip and active tab")
            return
        }
        let tabCountBefore = controller.tabManager.tabs.count

        strip.onSplitSideBySide?()

        var capturedTitle: String?
        var capturedMessage: String?
        var pendingDecision: ((Bool) -> Void)?
        controller.focusedPaneCloseConfirmationPresenter = { title, message, completion in
            capturedTitle = title
            capturedMessage = message
            pendingDecision = completion
        }

        strip.onClosePanel?()

        XCTAssertEqual(capturedTitle, "Close Focused Pane?")
        XCTAssertTrue(
            capturedMessage?.contains("workspace tab stays open") ?? false,
            "The confirmation should make it clear that this closes only the focused pane"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            2,
            "Clicking the top-strip close icon must not close the split before confirmation"
        )
        XCTAssertEqual(
            controller.tabManager.tabs.count,
            tabCountBefore,
            "Prompting to close a focused pane must not close the workspace tab"
        )

        pendingDecision?(true)

        XCTAssertNil(
            controller.activeSplitView,
            "Confirming should collapse the split hierarchy"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            1,
            "Confirming should close the focused pane after the prompt"
        )
        XCTAssertEqual(controller.tabManager.tabs.count, tabCountBefore)
        XCTAssertEqual(controller.tabManager.activeTabID, activeTabID)
    }
}
