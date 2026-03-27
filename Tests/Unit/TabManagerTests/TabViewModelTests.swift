// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabViewModelTests.swift - Tests for TabViewModel presentation logic.

import XCTest
@testable import CocxyTerminal

// MARK: - Tab View Model Tests

/// Tests for `TabViewModel` presentation logic.
///
/// Covers:
/// - Display title truncation.
/// - Status color based on agent state.
/// - Badge text based on agent state.
/// - Subtitle composition from git branch and process name.
@MainActor
final class TabViewModelTests: XCTestCase {

    // MARK: - Display Title Truncation

    func testDisplayTitleShortTitleUnchanged() {
        let tab = Tab(title: "Terminal")
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.displayTitle, "Terminal")
    }

    func testDisplayTitleExactly20CharsUnchanged() {
        let title = String(repeating: "a", count: 20)
        let tab = Tab(title: title)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.displayTitle, title)
    }

    func testDisplayTitleLongTitleTruncatedWithEllipsis() {
        let title = "This is a very long terminal tab title"
        let tab = Tab(title: title)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertTrue(viewModel.displayTitle.hasSuffix("..."))
        XCTAssertLessThanOrEqual(viewModel.displayTitle.count, 23) // 20 chars + "..."
    }

    func testDisplayTitleEmptyStaysEmpty() {
        let tab = Tab(title: "")
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.displayTitle, "")
    }

    // MARK: - Status Color

    func testStatusColorIdle() {
        let tab = Tab(agentState: .idle)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.statusColorName, "gray")
    }

    func testStatusColorWorking() {
        let tab = Tab(agentState: .working)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.statusColorName, "blue")
    }

    func testStatusColorLaunched() {
        let tab = Tab(agentState: .launched)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.statusColorName, "blue")
    }

    func testStatusColorWaitingInput() {
        let tab = Tab(agentState: .waitingInput)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.statusColorName, "yellow")
    }

    func testStatusColorFinished() {
        let tab = Tab(agentState: .finished)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.statusColorName, "green")
    }

    func testStatusColorError() {
        let tab = Tab(agentState: .error)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.statusColorName, "red")
    }

    // MARK: - Badge Text

    func testBadgeTextIdleIsNil() {
        let tab = Tab(agentState: .idle)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertNil(viewModel.badgeText)
    }

    func testBadgeTextWorking() {
        let tab = Tab(agentState: .working)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.badgeText, "Working")
    }

    func testBadgeTextWaitingInput() {
        let tab = Tab(agentState: .waitingInput)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.badgeText, "Input")
    }

    func testBadgeTextFinished() {
        let tab = Tab(agentState: .finished)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.badgeText, "Done")
    }

    func testBadgeTextError() {
        let tab = Tab(agentState: .error)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.badgeText, "Error")
    }

    func testBadgeTextLaunched() {
        let tab = Tab(agentState: .launched)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.badgeText, "Launched")
    }

    // MARK: - Subtitle

    func testSubtitleWithGitBranchAndProcessName() {
        let tab = Tab(gitBranch: "main", processName: "node")
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.subtitle, "main \u{2022} node")
    }

    func testSubtitleWithOnlyGitBranch() {
        let tab = Tab(gitBranch: "develop", processName: nil)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.subtitle, "develop")
    }

    func testSubtitleWithOnlyProcessName() {
        let tab = Tab(gitBranch: nil, processName: "zsh")
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.subtitle, "zsh")
    }

    func testSubtitleWithNeitherIsNil() {
        let tab = Tab(gitBranch: nil, processName: nil)
        let viewModel = TabViewModel(tab: tab)

        XCTAssertNil(viewModel.subtitle)
    }

    // MARK: - Tab Update

    func testUpdateTabRefreshesProperties() {
        let tab = Tab(title: "Old", agentState: .idle, processName: "zsh")
        let viewModel = TabViewModel(tab: tab)

        XCTAssertEqual(viewModel.displayTitle, "Old")
        XCTAssertEqual(viewModel.statusColorName, "gray")

        var updatedTab = tab
        updatedTab.title = "New"
        updatedTab.agentState = .working
        updatedTab.processName = "claude"
        viewModel.update(with: updatedTab)

        XCTAssertEqual(viewModel.displayTitle, "New")
        XCTAssertEqual(viewModel.statusColorName, "blue")
        XCTAssertEqual(viewModel.subtitle, "claude")
    }
}
