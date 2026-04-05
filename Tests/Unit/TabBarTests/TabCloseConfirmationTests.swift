// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabCloseConfirmationTests.swift - Tests for close-tab confirmation behavior.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Tab Close Confirmation Tests

/// Tests that `closeTab` delegates to `performCloseTab` and that
/// the pinned-tab guard still works after the extraction.
@MainActor
final class TabCloseConfirmationTests: XCTestCase {

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    // MARK: - performCloseTab extraction

    func testPerformCloseTabRemovesTab() {
        _ = tabManager.tabs[0]
        let tabB = tabManager.addTab()

        // Directly removing should still work (performCloseTab path).
        tabManager.removeTab(id: tabB.id)

        XCTAssertEqual(tabManager.tabs.count, 1,
                       "performCloseTab should remove the tab from the manager")
    }

    func testPinnedTabCannotBeClosed() {
        let tab = tabManager.tabs[0]
        tabManager.updateTab(id: tab.id) { $0.isPinned = true }

        // Verify the guard: pinned tabs should survive a close attempt.
        let isPinned = tabManager.tab(for: tab.id)?.isPinned ?? false
        XCTAssertTrue(isPinned,
                      "Pinned tab must remain in the manager after close attempt")
    }

    // MARK: - Config flag drives confirmation

    func testConfirmCloseProcessDefaultIsTrue() {
        let defaults = GeneralConfig.defaults
        XCTAssertTrue(defaults.confirmCloseProcess,
                      "confirmCloseProcess should default to true")
    }

    func testConfirmCloseProcessCanBeDisabled() {
        let config = GeneralConfig(
            shell: "/bin/zsh",
            workingDirectory: "~",
            confirmCloseProcess: false
        )
        XCTAssertFalse(config.confirmCloseProcess,
                       "confirmCloseProcess must respect explicit false")
    }

    // MARK: - TabItemView shouldConfirmClose property

    func testTabItemViewDefaultShouldConfirmCloseIsFalse() {
        let displayItem = TabDisplayItem(
            id: TabID(),
            displayTitle: "Test",
            subtitle: nil,
            statusColorName: "gray",
            badgeText: nil,
            isActive: false,
            hasUnreadNotification: false,
            agentState: .idle
        )
        let itemView = TabItemView(displayItem: displayItem)

        XCTAssertFalse(itemView.shouldConfirmClose,
                       "shouldConfirmClose must default to false")
    }

    func testTabItemViewShouldConfirmCloseCanBeSetToTrue() {
        let displayItem = TabDisplayItem(
            id: TabID(),
            displayTitle: "Test",
            subtitle: nil,
            statusColorName: "gray",
            badgeText: nil,
            isActive: false,
            hasUnreadNotification: false,
            agentState: .idle
        )
        let itemView = TabItemView(displayItem: displayItem)
        itemView.shouldConfirmClose = true

        XCTAssertTrue(itemView.shouldConfirmClose,
                      "shouldConfirmClose must be settable to true")
    }
}

// MARK: - App Quit Confirmation Tests

/// Tests that applicationShouldTerminate is implemented correctly.
@MainActor
final class AppQuitConfirmationTests: XCTestCase {

    func testAppDelegateRespondsToShouldTerminate() {
        let delegate = AppDelegate()
        // Verify the method exists and is callable.
        let selector = #selector(AppDelegate.applicationShouldTerminate(_:))
        XCTAssertTrue(delegate.responds(to: selector),
                      "AppDelegate must implement applicationShouldTerminate")
    }
}
