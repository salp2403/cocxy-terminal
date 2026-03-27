// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserTabTests.swift - Tests for browser tab model and multi-tab management.

import XCTest
import Combine
@testable import CocxyTerminal

@MainActor
final class BrowserTabTests: XCTestCase {

    // MARK: - BrowserTab Model

    func testBrowserTabInitialization() {
        let url = URL(string: "https://example.com")!
        let tab = BrowserTab(url: url)

        XCTAssertEqual(tab.url, url)
        XCTAssertEqual(tab.title, "New Tab")
        XCTAssertFalse(tab.isLoading)
    }

    func testBrowserTabDefaultURL() {
        let tab = BrowserTab()

        XCTAssertEqual(tab.url.absoluteString, "http://localhost:3000")
        XCTAssertEqual(tab.title, "New Tab")
    }

    func testBrowserTabHasUniqueID() {
        let tab1 = BrowserTab()
        let tab2 = BrowserTab()
        XCTAssertNotEqual(tab1.id, tab2.id)
    }

    // MARK: - Multi-Tab Management in ViewModel

    func testViewModelStartsWithOneTab() {
        let vm = BrowserViewModel()
        XCTAssertEqual(vm.browserTabs.count, 1)
        XCTAssertNotNil(vm.activeTabID)
    }

    func testAddTabIncreasesTabCount() {
        let vm = BrowserViewModel()
        vm.addBrowserTab()
        XCTAssertEqual(vm.browserTabs.count, 2)
    }

    func testAddTabSetsNewTabAsActive() {
        let vm = BrowserViewModel()
        let initialActiveID = vm.activeTabID
        vm.addBrowserTab()

        XCTAssertNotEqual(vm.activeTabID, initialActiveID)
        XCTAssertEqual(vm.activeTabID, vm.browserTabs.last?.id)
    }

    func testCloseTabDecreasesTabCount() {
        let vm = BrowserViewModel()
        vm.addBrowserTab()
        XCTAssertEqual(vm.browserTabs.count, 2)

        let tabToClose = vm.browserTabs.last!.id
        vm.closeBrowserTab(tabToClose)
        XCTAssertEqual(vm.browserTabs.count, 1)
    }

    func testCloseLastRemainingTabIsNoOp() {
        let vm = BrowserViewModel()
        XCTAssertEqual(vm.browserTabs.count, 1)

        let onlyTabID = vm.browserTabs.first!.id
        vm.closeBrowserTab(onlyTabID)
        XCTAssertEqual(vm.browserTabs.count, 1, "Cannot close the last remaining tab")
    }

    func testCloseActiveTabActivatesNeighbor() {
        let vm = BrowserViewModel()
        vm.addBrowserTab()
        vm.addBrowserTab()
        XCTAssertEqual(vm.browserTabs.count, 3)

        let middleTab = vm.browserTabs[1]
        vm.selectBrowserTab(middleTab.id)
        XCTAssertEqual(vm.activeTabID, middleTab.id)

        vm.closeBrowserTab(middleTab.id)
        XCTAssertEqual(vm.browserTabs.count, 2)
        XCTAssertNotNil(vm.activeTabID)
        XCTAssertNotEqual(vm.activeTabID, middleTab.id)
    }

    func testSelectTabChangesActiveTab() {
        let vm = BrowserViewModel()
        vm.addBrowserTab()

        let firstTab = vm.browserTabs.first!
        vm.selectBrowserTab(firstTab.id)
        XCTAssertEqual(vm.activeTabID, firstTab.id)
    }

    func testSelectNonExistentTabIsNoOp() {
        let vm = BrowserViewModel()
        let originalActive = vm.activeTabID
        vm.selectBrowserTab(UUID())
        XCTAssertEqual(vm.activeTabID, originalActive)
    }

    func testAddTabWithURLSetsCorrectURL() {
        let vm = BrowserViewModel()
        let customURL = URL(string: "https://docs.swift.org")!
        vm.addBrowserTab(url: customURL)

        XCTAssertEqual(vm.browserTabs.last?.url, customURL)
    }

    func testActiveTabURLSyncsWithURLString() {
        let vm = BrowserViewModel()
        vm.navigate(to: "https://example.com")

        let activeTab = vm.browserTabs.first { $0.id == vm.activeTabID }
        XCTAssertEqual(activeTab?.url.absoluteString, "https://example.com")
    }

    // MARK: - Tab Title Updates

    func testPageTitleUpdatesActiveTab() {
        let vm = BrowserViewModel()
        vm.updateActiveTabTitle("Swift Documentation")

        let activeTab = vm.browserTabs.first { $0.id == vm.activeTabID }
        XCTAssertEqual(activeTab?.title, "Swift Documentation")
    }
}
