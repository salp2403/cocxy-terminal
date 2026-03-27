// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowOverlayContainerTests.swift - Tests for overlay container z-ordering fix.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Overlay Container Tests

/// Tests that overlays are rendered above the terminal via a dedicated overlay container.
///
/// The bugs: Command Palette (Cmd+Shift+P), Dashboard (Cmd+Option+D), and other overlays
/// were being added as subviews of the NSSplitView (window.contentView). NSSplitView
/// manages its own subview layout, so extra subviews don't appear as expected.
///
/// The fix: A root container view holds both the NSSplitView and an overlay container.
/// Overlays go in the overlay container, which is layered above the split view.
@MainActor
final class OverlayContainerTests: XCTestCase {

    func testWindowHasOverlayContainer() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        XCTAssertNotNil(
            controller.overlayContainerView,
            "MainWindowController must have an overlay container view"
        )
    }

    func testOverlayContainerIsAboveSplitView() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        guard let contentView = controller.window?.contentView else {
            XCTFail("Window must have a content view")
            return
        }

        guard let overlayContainer = controller.overlayContainerView else {
            XCTFail("Overlay container must exist")
            return
        }

        // The overlay container should be a sibling of (or above) the split view
        // in the view hierarchy.
        let subviews = contentView.subviews
        XCTAssertTrue(
            subviews.contains(where: { $0 === overlayContainer }),
            "The overlay container must be a subview of the window's content view"
        )
    }

    func testCommandPaletteIsAddedToOverlayContainer() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleCommandPalette()

        guard let overlayContainer = controller.overlayContainerView else {
            XCTFail("Overlay container must exist")
            return
        }

        XCTAssertFalse(
            overlayContainer.subviews.isEmpty,
            "After showing Command Palette, the overlay container must have subviews"
        )
    }

    func testDashboardIsAddedToOverlayContainer() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleDashboard()

        guard let overlayContainer = controller.overlayContainerView else {
            XCTFail("Overlay container must exist")
            return
        }

        XCTAssertFalse(
            overlayContainer.subviews.isEmpty,
            "After showing Dashboard, the overlay container must have subviews"
        )
    }

    func testSmartRoutingIsAddedToOverlayContainer() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.showSmartRouting()

        guard let overlayContainer = controller.overlayContainerView else {
            XCTFail("Overlay container must exist")
            return
        }

        XCTAssertFalse(
            overlayContainer.subviews.isEmpty,
            "After showing Smart Routing, the overlay container must have subviews"
        )
    }

    func testDismissingOverlayRemovesFromContainer() {
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleCommandPalette()
        controller.toggleCommandPalette()

        guard let overlayContainer = controller.overlayContainerView else {
            XCTFail("Overlay container must exist")
            return
        }

        XCTAssertTrue(
            overlayContainer.subviews.isEmpty,
            "After dismissing Command Palette, the overlay container must be empty"
        )
    }

    func testSearchBarRemainsInTerminalContainer() {
        // The search bar is a thin strip at the top of the terminal,
        // so it stays in the terminal container, not the overlay container.
        let bridge = GhosttyBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)

        controller.toggleSearchBar()

        XCTAssertTrue(
            controller.isSearchBarVisible,
            "Search bar must be visible after toggle"
        )
    }
}
