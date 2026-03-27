// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandDurationTrackingTests.swift - Tests for OSC 133 command duration tracking.

import XCTest
@testable import CocxyTerminal

// MARK: - Command Duration Tracking Tests

/// Tests for command duration tracking via OSC 133 shell integration.
///
/// Covers:
/// - OSCNotification enum has commandStarted and commandFinished cases.
/// - Duration formatting for milliseconds, seconds, and minutes.
/// - Tab command state transitions (start -> running -> finish).
/// - Exit code handling (success vs non-zero).
@MainActor
final class CommandDurationTrackingTests: XCTestCase {

    // MARK: - OSCNotification Cases

    func testOSCNotificationHasCommandStartedCase() {
        let notification = OSCNotification.commandStarted
        if case .commandStarted = notification {
            // Expected
        } else {
            XCTFail("OSCNotification should have a commandStarted case")
        }
    }

    func testOSCNotificationHasCommandFinishedCase() {
        let notification = OSCNotification.commandFinished(exitCode: 0)
        if case .commandFinished(let code) = notification {
            XCTAssertEqual(code, 0)
        } else {
            XCTFail("OSCNotification should have a commandFinished case with exit code")
        }
    }

    func testCommandFinishedWithNilExitCode() {
        let notification = OSCNotification.commandFinished(exitCode: nil)
        if case .commandFinished(let code) = notification {
            XCTAssertNil(code)
        } else {
            XCTFail("OSCNotification.commandFinished should accept nil exit code")
        }
    }

    // MARK: - Duration Formatting

    func testFormatDurationMilliseconds() {
        let result = CommandDurationFormatter.format(0.045)
        XCTAssertEqual(result, "45ms")
    }

    func testFormatDurationSubSecondRoundsDown() {
        let result = CommandDurationFormatter.format(0.999)
        XCTAssertEqual(result, "999ms")
    }

    func testFormatDurationOneSecond() {
        let result = CommandDurationFormatter.format(1.0)
        XCTAssertEqual(result, "1.0s")
    }

    func testFormatDurationSeconds() {
        let result = CommandDurationFormatter.format(5.37)
        XCTAssertEqual(result, "5.4s")
    }

    func testFormatDurationUnderOneMinute() {
        let result = CommandDurationFormatter.format(59.9)
        XCTAssertEqual(result, "59.9s")
    }

    func testFormatDurationOneMinute() {
        let result = CommandDurationFormatter.format(60.0)
        XCTAssertEqual(result, "1m0s")
    }

    func testFormatDurationMinutesAndSeconds() {
        let result = CommandDurationFormatter.format(125.0)
        XCTAssertEqual(result, "2m5s")
    }

    func testFormatDurationZero() {
        let result = CommandDurationFormatter.format(0.0)
        XCTAssertEqual(result, "0ms")
    }

    // MARK: - Tab Command State Transitions

    func testTabCommandStartClearsOldDuration() {
        var tab = Tab()
        tab.lastCommandDuration = 5.0
        tab.lastCommandExitCode = 0

        // Simulate command start.
        let startTime = Date()
        tab.lastCommandStartedAt = startTime
        tab.lastCommandDuration = nil
        tab.lastCommandExitCode = nil

        XCTAssertTrue(tab.isCommandRunning)
        XCTAssertNil(tab.lastCommandDuration)
        XCTAssertNil(tab.lastCommandExitCode)
    }

    func testTabCommandFinishCalculatesDuration() {
        var tab = Tab()
        let startTime = Date().addingTimeInterval(-3.5)
        tab.lastCommandStartedAt = startTime

        // Simulate command finish.
        let duration = Date().timeIntervalSince(startTime)
        tab.lastCommandDuration = duration
        tab.lastCommandExitCode = 0
        tab.lastCommandStartedAt = nil

        XCTAssertFalse(tab.isCommandRunning)
        XCTAssertNotNil(tab.lastCommandDuration)
        XCTAssertGreaterThan(tab.lastCommandDuration!, 3.0)
        XCTAssertEqual(tab.lastCommandExitCode, 0)
    }

    func testTabCommandFinishWithNonZeroExitCode() {
        var tab = Tab()
        tab.lastCommandStartedAt = Date().addingTimeInterval(-1.0)

        // Simulate command finish with error.
        tab.lastCommandDuration = 1.0
        tab.lastCommandExitCode = 127
        tab.lastCommandStartedAt = nil

        XCTAssertFalse(tab.isCommandRunning)
        XCTAssertEqual(tab.lastCommandExitCode, 127)
    }
}
