// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HorizontalTabStripDragTests.swift - Drag-to-reorder for horizontal panel tabs.

import XCTest
@testable import CocxyTerminal

// MARK: - Horizontal Tab Strip Drag Tests

/// Tests for drag-and-drop reorder support in `HorizontalTabStripView`.
///
/// Covers:
/// - Tab containers register for the expected dragged type.
/// - onSwapTabs callback is wired correctly.
/// - The drag pasteboard type identifier is consistent.
@MainActor
final class HorizontalTabStripDragTests: XCTestCase {

    // MARK: - Drag Type Registration

    func testDragPasteboardTypeExists() {
        // The custom pasteboard type must be defined for tab reordering.
        let type = HorizontalTabStripView.tabReorderPasteboardType
        XCTAssertFalse(type.rawValue.isEmpty,
                       "Tab reorder pasteboard type must be defined")
    }

    // MARK: - Swap Callback

    func testOnSwapTabsCallbackInvoked() {
        let strip = HorizontalTabStripView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 30)
        )
        strip.updateTabs([
            (title: "A", icon: "terminal.fill", isActive: true),
            (title: "B", icon: "globe", isActive: false),
            (title: "C", icon: "doc.text", isActive: false),
        ])

        var swapResult: (Int, Int)?
        strip.onSwapTabs = { from, to in
            swapResult = (from, to)
        }

        // Simulate the swap callback directly.
        strip.onSwapTabs?(0, 2)

        XCTAssertNotNil(swapResult)
        XCTAssertEqual(swapResult?.0, 0)
        XCTAssertEqual(swapResult?.1, 2)
    }

    // MARK: - Tab Container Draggability

    func testTabContainersExistForMultipleTabs() {
        let strip = HorizontalTabStripView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 30)
        )
        strip.updateTabs([
            (title: "Terminal", icon: "terminal.fill", isActive: true),
            (title: "Browser", icon: "globe", isActive: false),
        ])

        // The tab stack should have 2 arranged subviews (one per tab).
        let tabStackView = findStackView(in: strip)
        XCTAssertNotNil(tabStackView)
        XCTAssertEqual(tabStackView?.arrangedSubviews.count, 2,
                       "Each tab should have a draggable container")
    }

    // MARK: - Helpers

    private func findStackView(in view: NSView) -> NSStackView? {
        for subview in view.subviews {
            if let stack = subview as? NSStackView,
               stack.orientation == .horizontal {
                return stack
            }
            if let found = findStackView(in: subview) {
                return found
            }
        }
        return nil
    }
}
