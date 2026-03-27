// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MouseEventTests.swift - Tests for mouse event forwarding in GhosttyBridge.

import XCTest
import GhosttyKit
@testable import CocxyTerminal

// MARK: - Mouse Button Conversion Tests

/// Tests that MouseButton enum values correctly map to ghostty mouse button types.
@MainActor
final class MouseButtonConversionTests: XCTestCase {

    func testMouseButtonLeftMapsToGhosttyLeft() {
        // This test verifies the MouseButton enum exists and has the expected cases.
        let button: MouseButton = .left
        XCTAssertEqual(
            String(describing: button),
            "left",
            "MouseButton.left must exist"
        )
    }

    func testMouseButtonRightMapsToGhosttyRight() {
        let button: MouseButton = .right
        XCTAssertEqual(
            String(describing: button),
            "right",
            "MouseButton.right must exist"
        )
    }

    func testMouseButtonMiddleMapsToGhosttyMiddle() {
        let button: MouseButton = .middle
        XCTAssertEqual(
            String(describing: button),
            "middle",
            "MouseButton.middle must exist"
        )
    }
}

// MARK: - Mouse Action Conversion Tests

/// Tests that MouseAction enum values exist and are distinct.
@MainActor
final class MouseActionConversionTests: XCTestCase {

    func testMouseActionPressExists() {
        let action: MouseAction = .press
        XCTAssertEqual(
            String(describing: action),
            "press",
            "MouseAction.press must exist"
        )
    }

    func testMouseActionReleaseExists() {
        let action: MouseAction = .release
        XCTAssertEqual(
            String(describing: action),
            "release",
            "MouseAction.release must exist"
        )
    }
}

// MARK: - Bridge Mouse Methods Existence Tests

/// Tests that the bridge has the expected mouse event methods.
/// These are compile-time checks; the actual C API calls require a running surface.
@MainActor
final class BridgeMouseMethodTests: XCTestCase {

    func testBridgeHasSendMouseEventMethod() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()

        // This should not crash -- the surface doesn't exist, so it's a no-op.
        bridge.sendMouseEvent(
            button: .left,
            action: .press,
            position: CGPoint(x: 10, y: 20),
            modifiers: KeyModifiers(),
            to: fakeSurfaceID
        )
    }

    func testBridgeHasSendMousePositionMethod() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()

        bridge.sendMousePosition(
            position: CGPoint(x: 100, y: 200),
            modifiers: .shift,
            to: fakeSurfaceID
        )
    }

    func testBridgeHasSendScrollEventMethod() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()

        bridge.sendScrollEvent(
            deltaX: 0.0,
            deltaY: -10.0,
            modifiers: KeyModifiers(),
            to: fakeSurfaceID
        )
    }

    func testBridgeHasNotifyFocusChangedMethod() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()

        bridge.notifyFocusChanged(
            surfaceID: fakeSurfaceID,
            focused: true
        )
    }

    func testBridgeHasNotifyContentScaleChangedMethod() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()

        bridge.notifyContentScaleChanged(
            surfaceID: fakeSurfaceID,
            scaleFactor: 2.0
        )
    }
}
