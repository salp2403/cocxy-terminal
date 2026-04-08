// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowUIIntegrationTests.swift - Tests for SwiftUI overlay integration in MainWindowController.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Command Palette Integration Tests

/// Tests that the Command Palette overlay can be toggled on the main window.
@MainActor
final class CommandPaletteIntegrationTests: XCTestCase {

    func testToggleCommandPaletteCreatesOverlay() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleCommandPalette()

        XCTAssertTrue(
            controller.isCommandPaletteVisible,
            "Command palette must be visible after first toggle"
        )
    }

    func testToggleCommandPaletteTwiceDismissesOverlay() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleCommandPalette()
        controller.toggleCommandPalette()

        XCTAssertFalse(
            controller.isCommandPaletteVisible,
            "Command palette must be hidden after second toggle"
        )
    }

    func testCommandPaletteActionIsObjCCallable() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        // Verify the @objc action method exists and is callable.
        controller.toggleCommandPaletteAction(nil)

        XCTAssertTrue(
            controller.isCommandPaletteVisible,
            "toggleCommandPaletteAction must toggle the command palette"
        )
    }
}

// MARK: - Dashboard Integration Tests

/// Tests that the Dashboard panel can be toggled on the main window.
@MainActor
final class DashboardIntegrationTests: XCTestCase {

    func testToggleDashboardCreatesPanel() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleDashboard()

        XCTAssertTrue(
            controller.isDashboardVisible,
            "Dashboard must be visible after first toggle"
        )
    }

    func testToggleDashboardTwiceHidesPanel() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleDashboard()
        controller.toggleDashboard()

        XCTAssertFalse(
            controller.isDashboardVisible,
            "Dashboard must be hidden after second toggle"
        )
    }

    func testDashboardActionIsObjCCallable() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleDashboardAction(nil)

        XCTAssertTrue(
            controller.isDashboardVisible,
            "toggleDashboardAction must toggle the dashboard"
        )
    }
}

// MARK: - Search Bar Integration Tests

/// Tests that the scrollback search bar can be toggled on the main window.
@MainActor
final class SearchBarIntegrationTests: XCTestCase {

    func testToggleSearchBarCreatesBar() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleSearchBar()

        XCTAssertTrue(
            controller.isSearchBarVisible,
            "Search bar must be visible after first toggle"
        )
    }

    func testToggleSearchBarTwiceHidesBar() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleSearchBar()
        controller.toggleSearchBar()

        XCTAssertFalse(
            controller.isSearchBarVisible,
            "Search bar must be hidden after second toggle"
        )
    }

    func testSearchBarActionIsObjCCallable() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleSearchBarAction(nil)

        XCTAssertTrue(
            controller.isSearchBarVisible,
            "toggleSearchBarAction must toggle the search bar"
        )
    }
}

// MARK: - Smart Routing Integration Tests

/// Tests that the Smart Routing overlay can be shown on the main window.
@MainActor
final class SmartRoutingIntegrationTests: XCTestCase {

    func testShowSmartRoutingCreatesOverlay() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.showSmartRouting()

        XCTAssertTrue(
            controller.isSmartRoutingVisible,
            "Smart routing overlay must be visible after show"
        )
    }

    func testDismissSmartRoutingHidesOverlay() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.showSmartRouting()
        controller.dismissSmartRouting()

        XCTAssertFalse(
            controller.isSmartRoutingVisible,
            "Smart routing overlay must be hidden after dismiss"
        )
    }

    func testSmartRoutingActionIsObjCCallable() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.showSmartRoutingAction(nil)

        XCTAssertTrue(
            controller.isSmartRoutingVisible,
            "showSmartRoutingAction must show the smart routing overlay"
        )
    }

    func testShowSmartRoutingMakesOverlayFirstResponder() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.showSmartRouting()

        XCTAssertTrue(
            controller.window?.firstResponder === controller.smartRoutingHostingView,
            "Smart routing overlay should become first responder so keyboard navigation works immediately"
        )
    }
}

// MARK: - Timeline Integration Tests

/// Tests that the Timeline view can be toggled on the main window.
@MainActor
final class TimelineIntegrationTests: XCTestCase {

    func testToggleTimelineCreatesPanel() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleTimeline()

        XCTAssertTrue(
            controller.isTimelineVisible,
            "Timeline must be visible after first toggle"
        )
    }

    func testToggleTimelineTwiceHidesPanel() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleTimeline()
        controller.toggleTimeline()

        XCTAssertFalse(
            controller.isTimelineVisible,
            "Timeline must be hidden after second toggle"
        )
    }

    func testTimelineActionIsObjCCallable() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleTimelineAction(nil)

        XCTAssertTrue(
            controller.isTimelineVisible,
            "toggleTimelineAction must toggle the timeline"
        )
    }
}

// MARK: - About Dialog Tests

/// Tests that the About panel is wired correctly.
@MainActor
final class AboutDialogIntegrationTests: XCTestCase {

    func testShowAboutPanelIsCallable() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        // Just verify the method exists and doesn't crash.
        // We can't easily assert the panel appeared in tests.
        XCTAssertTrue(
            controller.responds(to: #selector(MainWindowController.showAboutPanel(_:))),
            "MainWindowController must respond to showAboutPanel:"
        )
    }
}

// MARK: - Window Overlays Don't Break Terminal Tests

/// Tests that adding/removing overlays does not break the terminal host view.
@MainActor
final class OverlayTerminalCoexistenceTests: XCTestCase {

    func testTerminalHostViewRemainsAfterCommandPaletteToggle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleCommandPalette()

        XCTAssertNotNil(
            controller.terminalSurfaceView,
            "Terminal host view must remain after command palette toggle"
        )
    }

    func testTerminalHostViewRemainsAfterDashboardToggle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleDashboard()

        XCTAssertNotNil(
            controller.terminalSurfaceView,
            "Terminal host view must remain after dashboard toggle"
        )
    }

    func testTerminalHostViewRemainsAfterSearchBarToggle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleSearchBar()

        XCTAssertNotNil(
            controller.terminalSurfaceView,
            "Terminal host view must remain after search bar toggle"
        )
    }

    func testTabBarViewRemainsAfterAllOverlaysToggled() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleCommandPalette()
        controller.toggleDashboard()
        controller.toggleSearchBar()
        controller.showSmartRouting()

        XCTAssertNotNil(
            controller.tabBarView,
            "Tab bar view must remain after all overlays toggled"
        )
        XCTAssertNotNil(
            controller.terminalSurfaceView,
            "Terminal surface view must remain after all overlays toggled"
        )
    }
}
