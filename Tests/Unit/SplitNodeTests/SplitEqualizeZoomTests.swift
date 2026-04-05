// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitEqualizeZoomTests.swift - Tests for equalize and zoom split features.

import XCTest
@testable import CocxyTerminal

@MainActor
final class SplitEqualizeZoomTests: XCTestCase {

    // MARK: - Equalize

    func testEqualizeSetsAllRatiosToHalf() {
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        // Change ratio away from 0.5.
        if case .split(let id, _, _, _, _) = manager.rootNode {
            manager.setRatio(splitID: id, ratio: 0.7)
        }

        manager.equalizeSplits()

        if case .split(_, _, _, _, let ratio) = manager.rootNode {
            XCTAssertEqual(ratio, 0.5, accuracy: 0.01)
        }
    }

    func testEqualizeWithNestedSplits() {
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)
        manager.splitFocused(direction: .vertical)

        manager.equalizeSplits()

        // All splits should have ratio 0.5.
        verifyAllRatios(node: manager.rootNode, expected: 0.5)
    }

    func testEqualizeWithSinglePaneIsNoOp() {
        let manager = SplitManager()
        manager.equalizeSplits()
        XCTAssertEqual(manager.rootNode.leafCount, 1)
    }

    // MARK: - Toggle Zoom

    func testToggleZoomMaximizesFocusedPane() {
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        // After split, focus is on the second child.
        // Zoom should give the focused (second) pane 95% of the space,
        // which means ratio = 0.05 (first child gets 5%).
        manager.toggleZoom()

        XCTAssertTrue(manager.isZoomed)
        if case .split(_, _, let first, _, let ratio) = manager.rootNode {
            let focusedIsInFirst = first.allLeafIDs().contains(where: { $0.leafID == manager.focusedLeafID })
            let focusedShare = focusedIsInFirst ? ratio : (1.0 - ratio)
            XCTAssertGreaterThan(focusedShare, 0.9, "Zoomed pane should take most of the space")
        }
    }

    func testToggleZoomTwiceRestoresOriginalRatio() {
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        // Set a non-default ratio.
        if case .split(let id, _, _, _, _) = manager.rootNode {
            manager.setRatio(splitID: id, ratio: 0.3)
        }

        manager.toggleZoom()
        XCTAssertTrue(manager.isZoomed)

        manager.toggleZoom()
        XCTAssertFalse(manager.isZoomed)

        if case .split(_, _, _, _, let ratio) = manager.rootNode {
            XCTAssertEqual(ratio, 0.3, accuracy: 0.01, "Should restore original ratio")
        }
    }

    func testToggleZoomWithSinglePaneIsNoOp() {
        let manager = SplitManager()
        manager.toggleZoom()
        XCTAssertFalse(manager.isZoomed)
    }

    func testHandleSplitActionEqualize() {
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)
        if case .split(let id, _, _, _, _) = manager.rootNode {
            manager.setRatio(splitID: id, ratio: 0.8)
        }

        manager.handleSplitAction(.equalizeSplits)

        if case .split(_, _, _, _, let ratio) = manager.rootNode {
            XCTAssertEqual(ratio, 0.5, accuracy: 0.01)
        }
    }

    func testHandleSplitActionToggleZoom() {
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        manager.handleSplitAction(.toggleZoom)
        XCTAssertTrue(manager.isZoomed)

        manager.handleSplitAction(.toggleZoom)
        XCTAssertFalse(manager.isZoomed)
    }

    // MARK: - Config Tests

    func testCursorStyleRawValues() {
        XCTAssertEqual(CursorStyle.block.rawValue, "block")
        XCTAssertEqual(CursorStyle.bar.rawValue, "bar")
        XCTAssertEqual(CursorStyle.underline.rawValue, "underline")
    }

    func testTerminalConfigDefaults() {
        let config = TerminalConfig.defaults
        XCTAssertEqual(config.cursorStyle, .bar)
        XCTAssertTrue(config.cursorBlink)
        XCTAssertEqual(config.cursorOpacity, 0.8)
        XCTAssertTrue(config.mouseHideWhileTyping)
        XCTAssertTrue(config.copyOnSelect)
        XCTAssertTrue(config.clipboardPasteProtection)
    }

    func testAppearanceConfigDefaults() {
        let config = AppearanceConfig.defaults
        XCTAssertEqual(config.backgroundOpacity, 1.0)
        XCTAssertEqual(config.backgroundBlurRadius, 0)
        XCTAssertNil(config.windowPaddingX)
        XCTAssertNil(config.windowPaddingY)
        XCTAssertEqual(config.effectivePaddingX, 8.0)
        XCTAssertEqual(config.effectivePaddingY, 8.0)
    }

    func testQuickTerminalConfigDefaults() {
        let config = QuickTerminalConfig.defaults
        XCTAssertEqual(config.animationDuration, 0.15)
        XCTAssertEqual(config.screen, .mouse)
    }

    // MARK: - Helpers

    private func verifyAllRatios(node: SplitNode, expected: CGFloat) {
        switch node {
        case .leaf: break
        case .split(_, _, let first, let second, let ratio):
            XCTAssertEqual(ratio, expected, accuracy: 0.01)
            verifyAllRatios(node: first, expected: expected)
            verifyAllRatios(node: second, expected: expected)
        }
    }
}
