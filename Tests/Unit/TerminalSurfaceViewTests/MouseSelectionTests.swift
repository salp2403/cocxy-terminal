// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MouseSelectionTests.swift - Tests for mouse selection, click counting and clipboard.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Mouse Click Count Tracking Tests

/// Tests that the view correctly tracks click count for word/line selection.
@MainActor
final class MouseClickCountTests: XCTestCase {

    func testMouseDownUpdatesClickCountOnViewModel() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)

        view.handleMouseDown(at: CGPoint(x: 10, y: 20), clickCount: 1)
        XCTAssertEqual(
            viewModel.lastClickCount, 1,
            "Single click must record clickCount 1 on the view model"
        )
    }

    func testDoubleClickRecordsClickCountTwo() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)

        view.handleMouseDown(at: CGPoint(x: 10, y: 20), clickCount: 2)
        XCTAssertEqual(
            viewModel.lastClickCount, 2,
            "Double click must record clickCount 2 for word selection"
        )
    }

    func testTripleClickRecordsClickCountThree() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)

        view.handleMouseDown(at: CGPoint(x: 10, y: 20), clickCount: 3)
        XCTAssertEqual(
            viewModel.lastClickCount, 3,
            "Triple click must record clickCount 3 for line selection"
        )
    }
}

// MARK: - Mouse Drag Selection State Tests

/// Tests that click+drag tracking is correctly managed on the view model.
@MainActor
final class MouseDragSelectionTests: XCTestCase {

    func testMouseDownStartsDragState() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)

        view.handleMouseDown(at: CGPoint(x: 10, y: 20), clickCount: 1)
        XCTAssertTrue(
            viewModel.isDragging,
            "mouseDown must set isDragging to true"
        )
    }

    func testMouseUpEndsDragState() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)

        view.handleMouseDown(at: CGPoint(x: 10, y: 20), clickCount: 1)
        view.handleMouseUp(at: CGPoint(x: 50, y: 20))
        XCTAssertFalse(
            viewModel.isDragging,
            "mouseUp must set isDragging to false"
        )
    }
}

// MARK: - Auto Copy on Selection Tests

/// Tests that auto-copy configuration is tracked on the view model.
@MainActor
final class AutoCopyOnSelectionTests: XCTestCase {

    func testAutoCopyIsEnabledByDefault() {
        let viewModel = TerminalViewModel()
        XCTAssertTrue(
            viewModel.autoCopyOnSelect,
            "autoCopyOnSelect must default to true"
        )
    }

    func testAutoCopyCanBeDisabled() {
        let viewModel = TerminalViewModel()
        viewModel.autoCopyOnSelect = false
        XCTAssertFalse(
            viewModel.autoCopyOnSelect,
            "autoCopyOnSelect must be configurable"
        )
    }
}

// MARK: - Scroll Enhancement Tests

/// Tests for smooth scrolling properties and natural scrolling respect.
@MainActor
final class ScrollEnhancementTests: XCTestCase {

    func testScrollDeltaPreservesFractionalValues() {
        let scrollDelta = ScrollDelta(
            deltaX: 0.0,
            deltaY: -2.5,
            hasPreciseScrollingDeltas: true,
            momentumPhase: .none
        )

        XCTAssertEqual(scrollDelta.deltaY, -2.5, accuracy: 0.001,
            "Scroll delta must preserve fractional values for smooth scrolling"
        )
        XCTAssertTrue(
            scrollDelta.hasPreciseScrollingDeltas,
            "Trackpad scrolls must report precise scrolling deltas"
        )
    }

    func testScrollDeltaTracksMomentumPhase() {
        let inertiaScroll = ScrollDelta(
            deltaX: 0.0,
            deltaY: -0.8,
            hasPreciseScrollingDeltas: true,
            momentumPhase: .changed
        )

        XCTAssertEqual(
            inertiaScroll.momentumPhase, .changed,
            "Scroll delta must track momentum phase for inertia scrolling"
        )
    }

    func testScrollDeltaMomentumPhaseNoneForDiscreteScroll() {
        let discreteScroll = ScrollDelta(
            deltaX: 0.0,
            deltaY: -3.0,
            hasPreciseScrollingDeltas: false,
            momentumPhase: .none
        )

        XCTAssertEqual(
            discreteScroll.momentumPhase, .none,
            "Discrete mouse scroll must have momentumPhase .none"
        )
        XCTAssertFalse(
            discreteScroll.hasPreciseScrollingDeltas,
            "Discrete mouse scroll must not report precise deltas"
        )
    }
}

// MARK: - Mouse Button Type Extended Tests

/// Tests for middle mouse button support and additional mouse events.
@MainActor
final class MouseButtonExtendedTests: XCTestCase {

    func testMiddleMouseButtonExists() {
        let button: MouseButton = .middle
        XCTAssertEqual(
            String(describing: button), "middle",
            "MouseButton.middle must exist for middle-click paste"
        )
    }

    func testMouseActionTypesAreDistinct() {
        let press: MouseAction = .press
        let release: MouseAction = .release

        XCTAssertNotEqual(
            String(describing: press),
            String(describing: release),
            "Press and release must be distinct actions"
        )
    }
}
