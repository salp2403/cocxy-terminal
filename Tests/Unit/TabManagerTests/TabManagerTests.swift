// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabManagerTests.swift - Tests for tab management.

import XCTest
@testable import CocxyTerminal

// MARK: - Tab Manager Tests

/// Tests for `TabManager` covering tab lifecycle and ordering.
///
/// Covers:
/// - Tab creation with default and custom working directories.
/// - Tab closure.
/// - Tab reordering.
/// - Active tab tracking.
/// - Display title generation (directory + git branch).
///
/// - Note: Full test suite in T-015.
final class TabManagerTests: XCTestCase {

    func testTabDisplayTitleWithGitBranch() {
        let tab = Tab(
            title: "Terminal",
            workingDirectory: URL(fileURLWithPath: "/Users/dev/my-project"),
            gitBranch: "main"
        )

        XCTAssertEqual(tab.displayTitle, "my-project (main)")
    }

    func testTabDisplayTitleWithoutGitBranch() {
        let tab = Tab(
            title: "Terminal",
            workingDirectory: URL(fileURLWithPath: "/Users/dev/my-project"),
            gitBranch: nil
        )

        XCTAssertEqual(tab.displayTitle, "my-project")
    }

    func testTabIdUniqueness() {
        let tab1 = Tab()
        let tab2 = Tab()

        XCTAssertNotEqual(tab1.id, tab2.id)
    }

    func testTabDefaultState() {
        let tab = Tab()

        XCTAssertFalse(tab.hasUnreadNotification)
        XCTAssertFalse(tab.isActive)
    }
}
