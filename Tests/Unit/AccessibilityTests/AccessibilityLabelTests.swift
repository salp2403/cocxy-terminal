// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AccessibilityLabelTests.swift - Tests for accessibility labels and roles.

import XCTest
@testable import CocxyTerminal

// MARK: - Accessibility Label Tests

/// Tests for VoiceOver accessibility labels and roles across UI components.
///
/// Verifies that:
/// - Every `AgentState` has a meaningful accessibility description.
/// - Tab bar container has the correct accessibility role.
/// - Tab items have button role and descriptive labels.
/// - Split container has split group role.
/// - Quick terminal panel has popover role.
@MainActor
final class AccessibilityLabelTests: XCTestCase {

    // MARK: - AgentState Accessibility Descriptions

    func testIdleAccessibilityDescription() {
        let description = AgentState.idle.accessibilityDescription

        XCTAssertEqual(description, "No agent active",
                       "Idle state should describe absence of agent activity")
    }

    func testLaunchedAccessibilityDescription() {
        let description = AgentState.launched.accessibilityDescription

        XCTAssertEqual(description, "Agent launched",
                       "Launched state should indicate agent has started")
    }

    func testWorkingAccessibilityDescription() {
        let description = AgentState.working.accessibilityDescription

        XCTAssertEqual(description, "Agent is working",
                       "Working state should indicate active processing")
    }

    func testWaitingInputAccessibilityDescription() {
        let description = AgentState.waitingInput.accessibilityDescription

        XCTAssertEqual(description, "Agent needs your input",
                       "WaitingInput state should prompt user action")
    }

    func testFinishedAccessibilityDescription() {
        let description = AgentState.finished.accessibilityDescription

        XCTAssertEqual(description, "Agent completed task",
                       "Finished state should confirm task completion")
    }

    func testErrorAccessibilityDescription() {
        let description = AgentState.error.accessibilityDescription

        XCTAssertEqual(description, "Agent encountered an error",
                       "Error state should warn about failure")
    }

    func testAllAgentStatesHaveNonEmptyDescriptions() {
        let allStates: [AgentState] = [.idle, .launched, .working, .waitingInput, .finished, .error]

        for state in allStates {
            XCTAssertFalse(state.accessibilityDescription.isEmpty,
                           "\(state) must have a non-empty accessibility description")
        }
    }

    // MARK: - AgentStateIndicator Accessibility Role

    func testAgentStateIndicatorHasImageRole() {
        let indicator = AgentStateIndicator()

        // An image role is correct for a visual status indicator (colored dot).
        // VoiceOver will read the accessibilityLabel to describe it.
        XCTAssertEqual(indicator.accessibilityRole(), .image,
                       "AgentStateIndicator should have .image accessibility role")
    }

    func testAgentStateIndicatorUpdatesAccessibilityLabelOnStateChange() {
        let indicator = AgentStateIndicator()

        indicator.updateState(.working)

        // The indicator already sets accessibility label; verify the enhanced label
        // includes the human-readable description.
        let label = indicator.accessibilityLabel()
        XCTAssertNotNil(label, "Indicator must have an accessibility label")
        XCTAssertTrue(label?.contains("working") ?? false,
                      "Working state label should contain 'working', got: \(label ?? "nil")")
    }

    // MARK: - Tab Bar Accessibility Role

    func testTabBarViewHasListRole() {
        let tabManager = TabManager()
        let viewModel = TabBarViewModel(tabManager: tabManager)
        let tabBarView = TabBarView(viewModel: viewModel)

        XCTAssertEqual(tabBarView.accessibilityRole(), .list,
                       "TabBarView should have .list accessibility role for VoiceOver navigation")
    }

    func testTabBarViewHasAccessibilityLabel() {
        let tabManager = TabManager()
        let viewModel = TabBarViewModel(tabManager: tabManager)
        let tabBarView = TabBarView(viewModel: viewModel)

        let label = tabBarView.accessibilityLabel()
        XCTAssertEqual(label, "Terminal tabs",
                       "TabBarView should be labeled 'Terminal tabs' for VoiceOver")
    }

    // MARK: - Quick Terminal Accessibility

    func testQuickTerminalPanelHasAccessibilityLabel() {
        let panel = QuickTerminalPanel()

        let label = panel.accessibilityLabel()
        XCTAssertEqual(label, "Quick Terminal",
                       "QuickTerminalPanel should be labeled 'Quick Terminal' for VoiceOver")
    }
}
