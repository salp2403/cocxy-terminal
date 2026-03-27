// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ResizeTests.swift - Tests for terminal resize, debounce and scale changes.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Resize Throttle Configuration Tests

/// Tests for the resize throttle mechanism during live window resize.
@MainActor
final class ResizeThrottleTests: XCTestCase {

    func testResizeThrottleIntervalIsConfigured() {
        XCTAssertEqual(
            TerminalSurfaceView.liveResizeThrottleInterval, 1.0 / 60.0,
            accuracy: 0.001,
            "Live resize throttle must be approximately 16ms (60fps)"
        )
    }

    func testResizeOutsideLiveResizeIsImmediate() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)
        XCTAssertFalse(
            view.inLiveResize,
            "View must not be in live resize by default"
        )
    }
}

// MARK: - Terminal Size Calculation Tests

/// Tests that terminal size is correctly calculated from pixel dimensions.
@MainActor
final class TerminalSizeCalculationTests: XCTestCase {

    func testTerminalSizeStoresPixelDimensions() {
        let size = TerminalSize(
            columns: 80, rows: 24,
            pixelWidth: 960, pixelHeight: 576
        )
        XCTAssertEqual(size.pixelWidth, 960)
        XCTAssertEqual(size.pixelHeight, 576)
    }

    func testTerminalSizeStoresCharacterDimensions() {
        let size = TerminalSize(
            columns: 120, rows: 40,
            pixelWidth: 1440, pixelHeight: 960
        )
        XCTAssertEqual(size.columns, 120)
        XCTAssertEqual(size.rows, 40)
    }

    func testTerminalSizeEquality() {
        let size1 = TerminalSize(columns: 80, rows: 24, pixelWidth: 960, pixelHeight: 576)
        let size2 = TerminalSize(columns: 80, rows: 24, pixelWidth: 960, pixelHeight: 576)
        let size3 = TerminalSize(columns: 100, rows: 30, pixelWidth: 1200, pixelHeight: 720)

        XCTAssertEqual(size1, size2, "Identical terminal sizes must be equal")
        XCTAssertNotEqual(size1, size3, "Different terminal sizes must not be equal")
    }
}

// MARK: - Content Scale Tests

/// Tests for Retina content scale factor handling.
@MainActor
final class ContentScaleTests: XCTestCase {

    func testViewHasLayerBackedForMetalRendering() {
        let view = TerminalSurfaceView()
        XCTAssertTrue(
            view.wantsLayer,
            "View must be layer-backed for Metal rendering and scale changes"
        )
    }

    func testBridgeAcceptsContentScaleNotification() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()

        // Must not crash (no surface registered = no-op).
        bridge.notifyContentScaleChanged(surfaceID: fakeSurfaceID, scaleFactor: 2.0)
        bridge.notifyContentScaleChanged(surfaceID: fakeSurfaceID, scaleFactor: 1.0)
    }
}

// MARK: - Resize Overlay Tests

/// Tests for the optional size overlay shown during resize.
@MainActor
final class ResizeOverlayTests: XCTestCase {

    func testResizeOverlayDefaultsToHidden() {
        let overlay = ResizeOverlayState()
        XCTAssertFalse(overlay.isVisible, "Overlay must not be visible by default")
    }

    func testResizeOverlayShowsColumnsAndRows() {
        var overlay = ResizeOverlayState()
        overlay.show(columns: 80, rows: 24)

        XCTAssertTrue(overlay.isVisible, "Overlay must be visible after show()")
        XCTAssertEqual(overlay.columns, 80)
        XCTAssertEqual(overlay.rows, 24)
    }

    func testResizeOverlayHide() {
        var overlay = ResizeOverlayState()
        overlay.show(columns: 100, rows: 30)
        overlay.hide()

        XCTAssertFalse(overlay.isVisible, "Overlay must not be visible after hide()")
    }

    func testResizeOverlayDisplayString() {
        var overlay = ResizeOverlayState()
        overlay.show(columns: 80, rows: 24)

        XCTAssertEqual(
            overlay.displayString, "80x24",
            "Display string must show 'columnsXrows'"
        )
    }
}
