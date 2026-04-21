// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HorizontalTabStripCloseTests.swift - Tests for close button on horizontal tabs.

import XCTest
@testable import CocxyTerminal

@MainActor
final class HorizontalTabStripCloseTests: XCTestCase {

    // MARK: - Close Callback Wiring

    func testOnCloseTabCallbackExists() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var closedIndex: Int?
        strip.onCloseTab = { index in closedIndex = index }

        strip.onCloseTab?(1)
        XCTAssertEqual(closedIndex, 1)
    }

    func testOnCloseTabCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onCloseTab)
    }

    // MARK: - Close Button Visibility

    func testCloseButtonHiddenWithSingleTab() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateTabs([
            (title: "Terminal", icon: "terminal.fill", isActive: true),
        ])

        let closeButtons = findCloseButtons(in: strip)
        // With a single tab, close buttons should either not exist or be hidden.
        XCTAssertTrue(
            closeButtons.isEmpty || closeButtons.allSatisfy { $0.isHidden },
            "Close button should not be visible with a single tab"
        )
    }

    func testCloseButtonVisibleWithMultipleTabs() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateTabs([
            (title: "Terminal 1", icon: "terminal.fill", isActive: true),
            (title: "Browser", icon: "globe", isActive: false),
        ])

        let closeButtons = findCloseButtons(in: strip)
        XCTAssertFalse(
            closeButtons.isEmpty,
            "Close buttons should exist when there are multiple tabs"
        )
    }

    func testWorkspaceTabModeUsesTabCloseLabel() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.setItemKind(.workspaceTab)
        strip.updateTabs([
            (title: "One", icon: "terminal.fill", isActive: true),
            (title: "Two", icon: "terminal.fill", isActive: false),
        ])

        let closeButtons = findCloseButtons(in: strip, label: "Close tab")
        XCTAssertEqual(closeButtons.count, 2)
    }

    func testPanelModeUsesPanelCloseLabel() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.setItemKind(.panel)
        strip.updateTabs([
            (title: "Terminal", icon: "terminal.fill", isActive: true),
            (title: "Browser", icon: "globe", isActive: false),
        ])

        let closeButtons = findCloseButtons(in: strip, label: "Close panel")
        XCTAssertEqual(closeButtons.count, 2)
    }

    // MARK: - Helpers

    private func findCloseButtons(in view: NSView, label: String? = nil) -> [NSButton] {
        var result: [NSButton] = []
        for subview in view.subviews {
            findCloseButtonsRecursive(in: subview, label: label, result: &result)
        }
        return result
    }

    private func findCloseButtonsRecursive(in view: NSView, label: String?, result: inout [NSButton]) {
        if let button = view as? NSButton,
           ["Close tab", "Close panel"].contains(button.accessibilityLabel() ?? ""),
           label == nil || button.accessibilityLabel() == label {
            result.append(button)
        }
        for child in view.subviews {
            findCloseButtonsRecursive(in: child, label: label, result: &result)
        }
    }
}
