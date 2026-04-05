// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandDurationTrackerTests.swift - Tests for the OSC 133 command duration tracker.

import XCTest
@testable import CocxyTerminal

// MARK: - Command Duration Tracker Tests

/// Tests for `CommandDurationTracker`: the lightweight OSC 133 parser
/// that extracts command start (;B) and command finished (;D) events.
///
/// Covers:
/// - OSC 133;B emits commandStarted notification.
/// - OSC 133;D emits commandFinished notification (with and without exit code).
/// - OSC 133;A and ;C are ignored (not relevant for command tracking).
/// - Both BEL and ST terminators.
/// - Incremental parsing across split chunks.
/// - Mixed data (plain text + OSC sequences).
/// - Non-133 OSC sequences are ignored.
final class CommandDurationTrackerTests: XCTestCase {

    // MARK: - Helpers

    private func makeNotificationBox() -> LockedBox<[OSCNotification]> {
        LockedBox([])
    }

    private func makeTracker(received: LockedBox<[OSCNotification]>) -> CommandDurationTracker {
        CommandDurationTracker { notification in
            received.withValue { $0.append(notification) }
        }
    }

    /// Builds an OSC sequence terminated by BEL (0x07).
    private func oscSequenceBEL(code: Int, payload: String) -> Data {
        var bytes: [UInt8] = [0x1B, 0x5D]
        bytes.append(contentsOf: "\(code)".utf8)
        bytes.append(0x3B)
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x07)
        return Data(bytes)
    }

    /// Builds an OSC sequence terminated by ST (ESC \).
    private func oscSequenceST(code: Int, payload: String) -> Data {
        var bytes: [UInt8] = [0x1B, 0x5D]
        bytes.append(contentsOf: "\(code)".utf8)
        bytes.append(0x3B)
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x1B)
        bytes.append(0x5C)
        return Data(bytes)
    }

    // MARK: - OSC 133;B (Command Start)

    func testOSC133BEmitsCommandStarted() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 133, payload: "B")
        tracker.processBytes(data)

        let notifications = received.withValue { $0 }
        XCTAssertEqual(notifications.count, 1)
        if case .commandStarted = notifications.first {
            // Expected.
        } else {
            XCTFail("Expected .commandStarted, got \(String(describing: notifications.first))")
        }
    }

    func testOSC133BWithSTTerminator() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceST(code: 133, payload: "B")
        tracker.processBytes(data)

        let notifications = received.withValue { $0 }
        XCTAssertEqual(notifications.count, 1)
        if case .commandStarted = notifications.first {
            // Expected.
        } else {
            XCTFail("Expected .commandStarted with ST terminator")
        }
    }

    // MARK: - OSC 133;D (Command Finished)

    func testOSC133DEmitsCommandFinishedWithoutExitCode() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 133, payload: "D")
        tracker.processBytes(data)

        let notifications = received.withValue { $0 }
        XCTAssertEqual(notifications.count, 1)
        if case .commandFinished(let exitCode) = notifications.first {
            XCTAssertNil(exitCode)
        } else {
            XCTFail("Expected .commandFinished, got \(String(describing: notifications.first))")
        }
    }

    func testOSC133DWithExitCodeZero() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 133, payload: "D;0")
        tracker.processBytes(data)

        let notifications = received.withValue { $0 }
        XCTAssertEqual(notifications.count, 1)
        if case .commandFinished(let exitCode) = notifications.first {
            XCTAssertEqual(exitCode, 0)
        } else {
            XCTFail("Expected .commandFinished with exit code 0")
        }
    }

    func testOSC133DWithNonZeroExitCode() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 133, payload: "D;127")
        tracker.processBytes(data)

        let notifications = received.withValue { $0 }
        XCTAssertEqual(notifications.count, 1)
        if case .commandFinished(let exitCode) = notifications.first {
            XCTAssertEqual(exitCode, 127)
        } else {
            XCTFail("Expected .commandFinished with exit code 127")
        }
    }

    // MARK: - Ignored Sequences

    func testOSC133AIsIgnored() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 133, payload: "A")
        tracker.processBytes(data)

        XCTAssertTrue(received.withValue { $0.isEmpty }, "OSC 133;A should be ignored by the command tracker")
    }

    func testOSC133CIsIgnored() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 133, payload: "C")
        tracker.processBytes(data)

        XCTAssertTrue(received.withValue { $0.isEmpty }, "OSC 133;C should be ignored by the command tracker")
    }

    func testNonOSC133SequencesAreIgnored() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let data = oscSequenceBEL(code: 9, payload: "Task completed")
        tracker.processBytes(data)

        XCTAssertTrue(received.withValue { $0.isEmpty }, "Non-133 OSC sequences should be ignored")
    }

    // MARK: - Incremental Parsing

    func testIncrementalParsingAcrossChunks() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        let fullSequence = oscSequenceBEL(code: 133, payload: "B")
        let midpoint = fullSequence.count / 2
        let chunk1 = fullSequence.prefix(midpoint)
        let chunk2 = fullSequence.suffix(from: midpoint)

        tracker.processBytes(Data(chunk1))
        XCTAssertTrue(received.withValue { $0.isEmpty }, "Incomplete sequence should not emit")

        tracker.processBytes(Data(chunk2))
        XCTAssertEqual(received.withValue { $0.count }, 1)
    }

    // MARK: - Mixed Data

    func testMixedDataWithPlainText() {
        let received = makeNotificationBox()
        let tracker = makeTracker(received: received)

        var data = Data("ls -la\n".utf8)
        data.append(oscSequenceBEL(code: 133, payload: "B"))
        data.append(Data("total 42\n".utf8))
        data.append(oscSequenceBEL(code: 133, payload: "D;0"))

        tracker.processBytes(data)

        let notifications = received.withValue { $0 }
        XCTAssertEqual(notifications.count, 2)
        if case .commandStarted = notifications[0] {
            // Expected.
        } else {
            XCTFail("First notification should be commandStarted")
        }
        if case .commandFinished(let code) = notifications[1] {
            XCTAssertEqual(code, 0)
        } else {
            XCTFail("Second notification should be commandFinished")
        }
    }
}
