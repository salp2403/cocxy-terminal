// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AnimationTests.swift - Tests for animation configuration and reduce motion support.

import XCTest
@testable import CocxyTerminal

// MARK: - Animation Config Tests

/// Tests for `AnimationConfig` covering:
/// - All animation duration constants are reasonable (< 1s).
/// - `duration(_:)` returns 0 when reduce motion is enabled.
/// - `duration(_:)` returns the base duration when reduce motion is off.
/// - Reduce motion flag works dynamically.
@MainActor
final class AnimationConfigTests: XCTestCase {

    // MARK: - Duration Constants

    func testTabAppearDurationIsReasonable() {
        XCTAssertGreaterThan(AnimationConfig.tabAppearDuration, 0,
                             "Tab appear duration must be positive")
        XCTAssertLessThan(AnimationConfig.tabAppearDuration, 1.0,
                          "Tab appear duration must be less than 1 second")
    }

    func testTabDisappearDurationIsReasonable() {
        XCTAssertGreaterThan(AnimationConfig.tabDisappearDuration, 0,
                             "Tab disappear duration must be positive")
        XCTAssertLessThan(AnimationConfig.tabDisappearDuration, 1.0,
                          "Tab disappear duration must be less than 1 second")
    }

    func testSplitTransitionDurationIsReasonable() {
        XCTAssertGreaterThan(AnimationConfig.splitTransitionDuration, 0,
                             "Split transition duration must be positive")
        XCTAssertLessThan(AnimationConfig.splitTransitionDuration, 1.0,
                          "Split transition duration must be less than 1 second")
    }

    func testStateColorTransitionDurationIsReasonable() {
        XCTAssertGreaterThan(AnimationConfig.stateColorTransitionDuration, 0,
                             "State color transition must be positive")
        XCTAssertLessThan(AnimationConfig.stateColorTransitionDuration, 1.0,
                          "State color transition must be less than 1 second")
    }

    func testQuickTerminalSlideDurationIsReasonable() {
        XCTAssertGreaterThan(AnimationConfig.quickTerminalSlideDuration, 0,
                             "Quick terminal slide must be positive")
        XCTAssertLessThan(AnimationConfig.quickTerminalSlideDuration, 1.0,
                          "Quick terminal slide must be less than 1 second")
    }

    func testNotificationToastDurationIsReasonable() {
        XCTAssertGreaterThan(AnimationConfig.notificationToastDuration, 0,
                             "Notification toast duration must be positive")
        XCTAssertLessThanOrEqual(AnimationConfig.notificationToastDuration, 3.0,
                                 "Notification toast should not exceed 3 seconds")
    }

    // MARK: - Reduce Motion

    func testDurationReturnsZeroWhenReduceMotionOverrideIsEnabled() {
        let result = AnimationConfig.duration(0.3, reduceMotionOverride: true)

        XCTAssertEqual(result, 0,
                       "Duration must be 0 when reduce motion is enabled")
    }

    func testDurationReturnsBaseWhenReduceMotionOverrideIsDisabled() {
        let baseDuration: TimeInterval = 0.3

        let result = AnimationConfig.duration(baseDuration, reduceMotionOverride: false)

        XCTAssertEqual(result, baseDuration,
                       "Duration must equal base when reduce motion is disabled")
    }

    func testDurationWithVariousBaseValues() {
        let values: [TimeInterval] = [0.1, 0.25, 0.3, 0.5]

        for base in values {
            let withMotion = AnimationConfig.duration(base, reduceMotionOverride: false)
            let withoutMotion = AnimationConfig.duration(base, reduceMotionOverride: true)

            XCTAssertEqual(withMotion, base,
                           "With motion enabled, should return base \(base)")
            XCTAssertEqual(withoutMotion, 0,
                           "With motion disabled, should return 0 for base \(base)")
        }
    }

    // MARK: - All Constants Are Positive

    func testAllDurationConstantsArePositive() {
        let durations: [TimeInterval] = [
            AnimationConfig.tabAppearDuration,
            AnimationConfig.tabDisappearDuration,
            AnimationConfig.splitTransitionDuration,
            AnimationConfig.stateColorTransitionDuration,
            AnimationConfig.quickTerminalSlideDuration,
            AnimationConfig.notificationToastDuration,
        ]

        for (index, duration) in durations.enumerated() {
            XCTAssertGreaterThan(duration, 0,
                                 "Duration at index \(index) must be positive")
        }
    }
}
