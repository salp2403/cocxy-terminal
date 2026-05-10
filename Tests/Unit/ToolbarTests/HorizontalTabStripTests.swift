// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HorizontalTabStripTests.swift - Tests for horizontal tab strip view.

import XCTest
@testable import CocxyTerminal

@MainActor
final class HorizontalTabStripTests: XCTestCase {

    // MARK: - Initial State

    func testInitialTabIsTerminal() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertEqual(strip.tabs.count, 1)
        XCTAssertEqual(strip.tabs[0].title, "Terminal")
        XCTAssertTrue(strip.tabs[0].isActive)
    }

    // MARK: - Update Tabs

    func testUpdateTabsReplacesContent() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateTabs([
            (title: "Terminal 1", icon: "terminal.fill", isActive: true),
            (title: "Browser", icon: "globe", isActive: false),
        ])
        XCTAssertEqual(strip.tabs.count, 2)
        XCTAssertEqual(strip.tabs[0].title, "Terminal 1")
        XCTAssertEqual(strip.tabs[1].title, "Browser")
    }

    func testUpdateTabsWithEmptyArray() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateTabs([])
        XCTAssertEqual(strip.tabs.count, 0)
    }

    func testUpdateTabsActiveState() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateTabs([
            (title: "T1", icon: "terminal.fill", isActive: false),
            (title: "T2", icon: "terminal.fill", isActive: true),
            (title: "T3", icon: "terminal.fill", isActive: false),
        ])
        XCTAssertFalse(strip.tabs[0].isActive)
        XCTAssertTrue(strip.tabs[1].isActive)
        XCTAssertFalse(strip.tabs[2].isActive)
    }

    // MARK: - Callbacks

    func testOnAddTabCallback() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddTab = { called = true }

        strip.onAddTab?()
        XCTAssertTrue(called)
    }

    func testOnSelectTabCallback() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var selectedIndex: Int?
        strip.onSelectTab = { index in selectedIndex = index }

        strip.onSelectTab?(2)
        XCTAssertEqual(selectedIndex, 2)
    }

    // MARK: - Multiple Updates

    func testMultipleUpdatesDoNotAccumulate() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))

        strip.updateTabs([
            (title: "A", icon: "terminal.fill", isActive: true),
            (title: "B", icon: "globe", isActive: false),
        ])
        XCTAssertEqual(strip.tabs.count, 2)

        strip.updateTabs([
            (title: "X", icon: "terminal.fill", isActive: true),
        ])
        XCTAssertEqual(strip.tabs.count, 1)
        XCTAssertEqual(strip.tabs[0].title, "X")
    }

    // MARK: - Classic Top Tab Layout

    func testPanelModeKeepsCompactLeadingInset() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))

        strip.setItemKind(.panel)

        XCTAssertEqual(strip.tabContentLeadingInsetForTesting, 8)
    }

    func testWorkspaceTabModeReservesTrafficLightSpace() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))

        strip.setItemKind(.workspaceTab)

        XCTAssertGreaterThanOrEqual(strip.tabContentLeadingInsetForTesting, 140)
    }

    func testSwitchingBackToPanelRestoresCompactInset() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))

        strip.setItemKind(.workspaceTab)
        strip.setItemKind(.panel)

        XCTAssertEqual(strip.tabContentLeadingInsetForTesting, 8)
    }

    func testPanelContextMenuHasRenameItemEvenForSinglePanel() throws {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateTabs([
            (title: "Terminal", icon: "terminal.fill", isActive: true),
        ])

        let container = try XCTUnwrap(findContainer(in: strip))

        XCTAssertNotNil(container.menu?.items.first { $0.title == "Rename Panel..." })
    }

    func testWorkspaceTabContextMenuUsesRenameTabCopy() throws {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.setItemKind(.workspaceTab)
        strip.updateTabs([
            (title: "Galf", icon: "terminal.fill", isActive: true),
        ])

        let container = try XCTUnwrap(findContainer(in: strip))

        XCTAssertNotNil(container.menu?.items.first { $0.title == "Rename Tab..." })
    }

    private func findContainer(in view: NSView) -> DraggableTabContainer? {
        for subview in view.subviews {
            if let container = subview as? DraggableTabContainer {
                return container
            }
            if let container = findContainer(in: subview) {
                return container
            }
        }
        return nil
    }
}
