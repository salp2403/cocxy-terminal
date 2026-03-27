// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateIndicatorTests.swift - Tests for agent state visual indicator.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent State Indicator Tests

/// Tests for `AgentStateIndicator` covering:
/// - Color mapping for each agent state.
/// - Badge text for each agent state.
/// - Accessibility label for each agent state.
/// - Reduce motion disables pulse animation.
/// - Indicator size is 12x12pt.
/// - State change updates the indicator.
/// - Idle state has no badge.
/// - Working state has pulse animation flag.
@MainActor
final class AgentStateIndicatorTests: XCTestCase {

    private var sut: AgentStateIndicator!

    override func setUp() {
        super.setUp()
        sut = AgentStateIndicator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Color Mapping

    func testIdleStateColorIsTertiaryLabel() {
        sut.updateState(.idle)

        XCTAssertEqual(sut.currentColorName, "tertiaryLabel",
                       "Idle state should use tertiary label color")
    }

    func testWorkingStateColorIsBlue() {
        sut.updateState(.working)

        XCTAssertEqual(sut.currentColorName, "systemBlue",
                       "Working state should use system blue")
    }

    func testWaitingInputStateColorIsYellow() {
        sut.updateState(.waitingInput)

        XCTAssertEqual(sut.currentColorName, "systemYellow",
                       "WaitingInput state should use system yellow")
    }

    func testFinishedStateColorIsGreen() {
        sut.updateState(.finished)

        XCTAssertEqual(sut.currentColorName, "systemGreen",
                       "Finished state should use system green")
    }

    func testErrorStateColorIsRed() {
        sut.updateState(.error)

        XCTAssertEqual(sut.currentColorName, "systemRed",
                       "Error state should use system red")
    }

    func testLaunchedStateColorIsBlue() {
        sut.updateState(.launched)

        XCTAssertEqual(sut.currentColorName, "systemBlue",
                       "Launched state should use system blue (same as working)")
    }

    // MARK: - Badge Text

    func testIdleStateHasNoBadge() {
        sut.updateState(.idle)

        XCTAssertNil(sut.currentBadgeText,
                     "Idle state should not show a badge")
    }

    func testWorkingStateHasNoBadge() {
        sut.updateState(.working)

        XCTAssertNil(sut.currentBadgeText,
                     "Working state uses pulse animation, not a badge")
    }

    func testWaitingInputStateHasQuestionBadge() {
        sut.updateState(.waitingInput)

        XCTAssertEqual(sut.currentBadgeText, "?",
                       "WaitingInput state should show '?' badge")
    }

    func testFinishedStateHasCheckBadge() {
        sut.updateState(.finished)

        XCTAssertEqual(sut.currentBadgeText, "\u{2713}",
                       "Finished state should show checkmark badge")
    }

    func testErrorStateHasExclamationBadge() {
        sut.updateState(.error)

        XCTAssertEqual(sut.currentBadgeText, "!",
                       "Error state should show '!' badge")
    }

    // MARK: - Accessibility Label

    func testIdleAccessibilityLabel() {
        sut.updateState(.idle)

        XCTAssertEqual(sut.currentAccessibilityLabel, "Agent state: idle")
    }

    func testWorkingAccessibilityLabel() {
        sut.updateState(.working)

        XCTAssertEqual(sut.currentAccessibilityLabel, "Agent state: working")
    }

    func testWaitingInputAccessibilityLabel() {
        sut.updateState(.waitingInput)

        XCTAssertEqual(sut.currentAccessibilityLabel, "Agent state: waiting for input")
    }

    func testFinishedAccessibilityLabel() {
        sut.updateState(.finished)

        XCTAssertEqual(sut.currentAccessibilityLabel, "Agent state: finished")
    }

    func testErrorAccessibilityLabel() {
        sut.updateState(.error)

        XCTAssertEqual(sut.currentAccessibilityLabel, "Agent state: error")
    }

    // MARK: - Pulse Animation Flag

    func testWorkingStateHasPulseEnabled() {
        sut.updateState(.working)

        XCTAssertTrue(sut.isPulseAnimationEnabled,
                      "Working state should enable pulse animation")
    }

    func testIdleStateHasPulseDisabled() {
        sut.updateState(.idle)

        XCTAssertFalse(sut.isPulseAnimationEnabled,
                       "Idle state should not pulse")
    }

    func testFinishedStateHasPulseDisabled() {
        sut.updateState(.finished)

        XCTAssertFalse(sut.isPulseAnimationEnabled,
                       "Finished state should not pulse")
    }

    func testLaunchedStateHasPulseEnabled() {
        sut.updateState(.launched)

        XCTAssertTrue(sut.isPulseAnimationEnabled,
                      "Launched state should enable pulse animation (agent starting)")
    }

    // MARK: - Reduce Motion

    func testReduceMotionDisablesPulseAnimation() {
        sut.reduceMotionEnabled = true
        sut.updateState(.working)

        XCTAssertFalse(sut.isPulseAnimationActive,
                       "Pulse animation should be inactive when reduce motion is enabled")
    }

    func testReduceMotionDoesNotAffectColor() {
        sut.reduceMotionEnabled = true
        sut.updateState(.working)

        XCTAssertEqual(sut.currentColorName, "systemBlue",
                       "Color should not be affected by reduce motion")
    }

    // MARK: - Indicator Size

    func testIndicatorSizeIs16x16() {
        XCTAssertEqual(AgentStateIndicator.indicatorSize, 16.0,
                       "Indicator should be 16x16 points for better visibility")
    }

    // MARK: - State Change Updates Indicator

    func testStateChangeUpdatesColorFromIdleToWorking() {
        sut.updateState(.idle)
        XCTAssertEqual(sut.currentColorName, "tertiaryLabel")

        sut.updateState(.working)
        XCTAssertEqual(sut.currentColorName, "systemBlue")
    }

    func testStateChangeUpdatesBadgeFromWorkingToError() {
        sut.updateState(.working)
        XCTAssertNil(sut.currentBadgeText)

        sut.updateState(.error)
        XCTAssertEqual(sut.currentBadgeText, "!")
    }
}
