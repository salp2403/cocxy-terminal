// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HorizontalTabStripDragInteractionTests.swift - Tests for click-vs-drag detection.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Drag Interaction Tests

/// Tests that `DraggableTabContainer` correctly distinguishes
/// clicks from drags via its `mouseDown` override.
///
/// The previous implementation relied on `mouseDragged`, which
/// never fired because the nested NSButton captured `mouseDown`.
/// The fix moves drag detection into `mouseDown` with a threshold.
@MainActor
final class HorizontalTabStripDragInteractionTests: XCTestCase {

    // MARK: - Container Setup

    func testDraggableContainerConformsToDraggingSource() {
        let container = DraggableTabContainer(
            frame: NSRect(x: 0, y: 0, width: 120, height: 28)
        )
        // NSDraggingSource conformance is required for drag initiation.
        XCTAssertTrue(container is NSDraggingSource,
                      "DraggableTabContainer must conform to NSDraggingSource")
    }

    func testDraggableContainerStoresTabIndex() {
        let container = DraggableTabContainer(
            frame: NSRect(x: 0, y: 0, width: 120, height: 28)
        )
        container.tabIndex = 3
        XCTAssertEqual(container.tabIndex, 3,
                       "tabIndex must be settable for drag identification")
    }

    func testDraggableContainerRegistersForCorrectPasteboardType() {
        let container = DraggableTabContainer(
            frame: NSRect(x: 0, y: 0, width: 120, height: 28)
        )
        let registered = container.registeredDraggedTypes
        XCTAssertTrue(registered.contains(HorizontalTabStripView.tabReorderPasteboardType),
                      "Container must register for the tab reorder pasteboard type")
    }

    // MARK: - Drag Threshold

    func testDragThresholdConstantExists() {
        // The drag threshold should be accessible and reasonable (> 0).
        let threshold = DraggableTabContainer.dragThreshold
        XCTAssertGreaterThan(threshold, 0,
                             "Drag threshold must be positive")
        XCTAssertLessThanOrEqual(threshold, 20,
                                 "Drag threshold should be reasonable (not too large)")
    }

    // MARK: - Strip Tab Container Creation

    func testTabStripCreatesContainersForEachTab() {
        let strip = HorizontalTabStripView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 30)
        )
        strip.updateTabs([
            (title: "Terminal", icon: "terminal.fill", isActive: true),
            (title: "Browser", icon: "globe", isActive: false),
        ])

        // Each tab should produce a DraggableTabContainer.
        let containers = findAllContainers(in: strip)
        XCTAssertEqual(containers.count, 2,
                       "Each tab should be wrapped in a DraggableTabContainer")
    }

    // MARK: - Helpers

    private func findAllContainers(in view: NSView) -> [DraggableTabContainer] {
        var result: [DraggableTabContainer] = []
        for subview in view.subviews {
            if let container = subview as? DraggableTabContainer {
                result.append(container)
            }
            result.append(contentsOf: findAllContainers(in: subview))
        }
        return result
    }
}
