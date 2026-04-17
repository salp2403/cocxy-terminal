// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabRenameTests.swift - Tests for tab renaming (customTitle).

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Tab Custom Title Tests

/// Tests for the `customTitle` field on `Tab` and its effect on `displayTitle`.
///
/// Covers:
/// - Default `customTitle` is nil.
/// - `displayTitle` uses directory name when `customTitle` is nil.
/// - `displayTitle` uses `customTitle` when set.
/// - Empty `customTitle` falls back to directory-based title.
/// - `customTitle` round-trips through Codable.
@MainActor
final class TabCustomTitleTests: XCTestCase {

    func testDefaultCustomTitleIsNil() {
        let tab = Tab()
        XCTAssertNil(tab.customTitle)
    }

    func testDisplayTitleUsesDirectoryWhenNoCustomTitle() {
        let tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/Users/dev/myproject"),
            gitBranch: nil
        )
        XCTAssertEqual(tab.displayTitle, "myproject")
    }

    func testDisplayTitleUsesCustomTitleWhenSet() {
        var tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/Users/dev/myproject")
        )
        tab.customTitle = "API Server"

        XCTAssertEqual(tab.displayTitle, "API Server")
    }

    func testDisplayTitleFallsBackWhenCustomTitleIsEmpty() {
        var tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/Users/dev/myproject"),
            gitBranch: nil
        )
        tab.customTitle = ""

        XCTAssertEqual(tab.displayTitle, "myproject")
    }

    func testDisplayTitleFallsBackWhenCustomTitleIsWhitespace() {
        var tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/Users/dev/myproject"),
            gitBranch: nil
        )
        tab.customTitle = "   "

        XCTAssertEqual(tab.displayTitle, "myproject",
                       "Whitespace-only custom title should fall back to directory name")
    }

    func testDisplayTitleWithCustomTitleIgnoresGitBranch() {
        var tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/Users/dev/myproject"),
            gitBranch: "feature/login"
        )
        tab.customTitle = "API Server"

        XCTAssertEqual(tab.displayTitle, "API Server",
                       "Custom title should take priority over directory+branch")
    }

    func testCustomTitleInitParameter() {
        let tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            customTitle: "My Custom Tab"
        )
        XCTAssertEqual(tab.customTitle, "My Custom Tab")
        XCTAssertEqual(tab.displayTitle, "My Custom Tab")
    }

    func testCustomTitleDefaultsToNilInInit() {
        let tab = Tab(workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertNil(tab.customTitle)
    }

    func testCodableRoundTripWithCustomTitle() throws {
        var tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/tmp/test"),
            gitBranch: "main"
        )
        tab.customTitle = "Production DB"

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        XCTAssertEqual(decoded.customTitle, "Production DB")
        XCTAssertEqual(decoded.displayTitle, "Production DB")
    }

    func testCodableRoundTripWithNilCustomTitle() throws {
        let tab = Tab(workingDirectory: URL(fileURLWithPath: "/tmp"))

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        XCTAssertNil(decoded.customTitle)
    }
}

// MARK: - TabManager Rename Tests

/// Tests for `TabManager.renameTab(id:newTitle:)`.
///
/// Covers:
/// - Rename sets customTitle on the target tab.
/// - Rename with nil clears customTitle.
/// - Rename on nonexistent tab ID is a no-op.
/// - Rename updates displayTitle as observed by consumers.
@MainActor
final class TabManagerRenameTests: XCTestCase {

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    func testRenameTabSetsCustomTitle() {
        let tabID = tabManager.tabs[0].id
        tabManager.renameTab(id: tabID, newTitle: "My Workspace")

        XCTAssertEqual(tabManager.tabs[0].customTitle, "My Workspace")
    }

    func testRenameTabUpdatesDisplayTitle() {
        let tabID = tabManager.tabs[0].id
        tabManager.renameTab(id: tabID, newTitle: "Build Server")

        XCTAssertEqual(tabManager.tabs[0].displayTitle, "Build Server")
    }

    func testRenameTabWithNilClearsCustomTitle() {
        let tabID = tabManager.tabs[0].id
        tabManager.renameTab(id: tabID, newTitle: "Temp Name")
        tabManager.renameTab(id: tabID, newTitle: nil)

        XCTAssertNil(tabManager.tabs[0].customTitle)
    }

    func testRenameNonexistentTabIsNoOp() {
        let fakeID = TabID()
        let originalTitle = tabManager.tabs[0].displayTitle

        tabManager.renameTab(id: fakeID, newTitle: "Should Not Apply")

        XCTAssertEqual(tabManager.tabs[0].displayTitle, originalTitle)
    }

    func testRenameTabPreservesOtherFields() {
        let tabID = tabManager.tabs[0].id
        tabManager.updateTab(id: tabID) { tab in
            tab.gitBranch = "main"
            tab.processName = "claude"
        }

        tabManager.renameTab(id: tabID, newTitle: "Renamed")

        let tab = tabManager.tabs[0]
        XCTAssertEqual(tab.gitBranch, "main")
        XCTAssertEqual(tab.processName, "claude")
        XCTAssertEqual(tab.customTitle, "Renamed")
    }
}

// MARK: - TabBarViewModel Rename Tests

/// Tests for `TabBarViewModel.renameTab(id:newTitle:)`.
///
/// Covers:
/// - Rename propagates through to TabManager.
/// - Empty string clears customTitle.
/// - Whitespace-only string clears customTitle.
/// - Display items update after rename.
@MainActor
final class TabBarViewModelRenameTests: XCTestCase {

    private var tabManager: TabManager!
    private var viewModel: TabBarViewModel!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        viewModel = TabBarViewModel(tabManager: tabManager)
    }

    override func tearDown() {
        viewModel = nil
        tabManager = nil
        super.tearDown()
    }

    func testRenameTabUpdatesDisplayItem() {
        let tabID = tabManager.tabs[0].id
        viewModel.renameTab(id: tabID, newTitle: "API Server")

        XCTAssertEqual(viewModel.tabItems[0].displayTitle, "API Server")
    }

    func testRenameTabWithEmptyStringClearsTitle() {
        let tabID = tabManager.tabs[0].id
        viewModel.renameTab(id: tabID, newTitle: "Temp")
        viewModel.renameTab(id: tabID, newTitle: "")

        XCTAssertNil(tabManager.tabs[0].customTitle)
    }

    func testRenameTabTrimsWhitespace() {
        let tabID = tabManager.tabs[0].id
        viewModel.renameTab(id: tabID, newTitle: "  API Server  ")

        XCTAssertEqual(tabManager.tabs[0].customTitle, "API Server")
    }

    func testRenameTabWithOnlyWhitespaceClearsTitle() {
        let tabID = tabManager.tabs[0].id
        viewModel.renameTab(id: tabID, newTitle: "   ")

        XCTAssertNil(tabManager.tabs[0].customTitle)
    }
}
