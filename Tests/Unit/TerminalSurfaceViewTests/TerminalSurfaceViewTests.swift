// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalSurfaceViewTests.swift - Tests for TerminalSurfaceView configuration.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - TerminalSurfaceView Layer Configuration Tests

/// Tests that verify the Metal layer is correctly configured for GPU rendering.
@MainActor
final class TerminalSurfaceViewLayerTests: XCTestCase {

    func testViewWantsLayer() {
        let view = TerminalSurfaceView()
        XCTAssertTrue(
            view.wantsLayer,
            "TerminalSurfaceView must have wantsLayer = true for Metal rendering"
        )
    }

    func testViewLayerContentsRedrawPolicyIsNever() {
        let view = TerminalSurfaceView()
        // libghostty handles all rendering via Metal directly.
        // The layer should not redraw automatically.
        XCTAssertEqual(
            view.layerContentsRedrawPolicy,
            .never,
            "Layer contents redraw policy must be .never (libghostty handles rendering)"
        )
    }

    func testViewIsNotFlipped() {
        let view = TerminalSurfaceView()
        // libghostty uses top-left origin coordinate system.
        XCTAssertTrue(
            view.isFlipped,
            "TerminalSurfaceView must be flipped (top-left origin for libghostty)"
        )
    }
}

// MARK: - TerminalSurfaceView Responder Tests

/// Tests that the view correctly handles first responder status for keyboard focus.
@MainActor
final class TerminalSurfaceViewResponderTests: XCTestCase {

    func testAcceptsFirstResponder() {
        let view = TerminalSurfaceView()
        XCTAssertTrue(
            view.acceptsFirstResponder,
            "TerminalSurfaceView must accept first responder for keyboard input"
        )
    }
}

// MARK: - TerminalSurfaceView ViewModel Integration Tests

/// Tests that the view correctly integrates with its ViewModel.
@MainActor
final class TerminalSurfaceViewViewModelTests: XCTestCase {

    func testViewHoldsReferenceToViewModel() {
        let viewModel = TerminalViewModel()
        let view = TerminalSurfaceView(viewModel: viewModel)
        XCTAssertTrue(
            view.viewModel === viewModel,
            "View must hold a reference to its ViewModel"
        )
    }

    func testViewCreatesDefaultViewModelWhenNotProvided() {
        let view = TerminalSurfaceView()
        XCTAssertNotNil(
            view.viewModel,
            "View must create a default ViewModel when none is provided"
        )
    }
}

// MARK: - TerminalSurfaceView Event Translation Tests

/// Tests that NSEvent keyboard events are correctly translated to domain KeyEvent types.
@MainActor
final class TerminalSurfaceViewEventTranslationTests: XCTestCase {

    func testTranslateModifierFlagsShift() {
        let nsFlags: NSEvent.ModifierFlags = .shift
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertTrue(
            keyModifiers.contains(.shift),
            "NSEvent .shift must translate to KeyModifiers .shift"
        )
    }

    func testTranslateModifierFlagsControl() {
        let nsFlags: NSEvent.ModifierFlags = .control
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertTrue(
            keyModifiers.contains(.control),
            "NSEvent .control must translate to KeyModifiers .control"
        )
    }

    func testTranslateModifierFlagsOption() {
        let nsFlags: NSEvent.ModifierFlags = .option
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertTrue(
            keyModifiers.contains(.option),
            "NSEvent .option must translate to KeyModifiers .option"
        )
    }

    func testTranslateModifierFlagsCommand() {
        let nsFlags: NSEvent.ModifierFlags = .command
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertTrue(
            keyModifiers.contains(.command),
            "NSEvent .command must translate to KeyModifiers .command"
        )
    }

    func testTranslateModifierFlagsCombined() {
        let nsFlags: NSEvent.ModifierFlags = [.shift, .command]
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertTrue(
            keyModifiers.contains(.shift) && keyModifiers.contains(.command),
            "Combined NSEvent modifiers must translate to combined KeyModifiers"
        )
    }

    func testTranslateModifierFlagsEmpty() {
        let nsFlags = NSEvent.ModifierFlags()
        let keyModifiers = TerminalSurfaceView.translateModifierFlags(nsFlags)
        XCTAssertEqual(
            keyModifiers,
            KeyModifiers(),
            "Empty NSEvent modifiers must translate to empty KeyModifiers"
        )
    }
}

// MARK: - TerminalSurfaceView Focus State Tests

/// Tests that the view correctly tracks focus state.
@MainActor
final class TerminalSurfaceViewFocusTests: XCTestCase {

    func testDefaultFocusStateIsFalse() {
        let view = TerminalSurfaceView()
        XCTAssertFalse(
            view.isFocused,
            "View must not be focused by default"
        )
    }
}
