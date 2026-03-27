// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookEventTests.swift - Tests for HookEvent model parsing and encoding.

import XCTest
@testable import CocxyTerminal

// MARK: - Hook Event Tests

/// Tests for `HookEvent` and `HookEventType` models covering:
/// - JSON parsing for all 12 lifecycle event types.
/// - Graceful handling of malformed/unknown data.
/// - Round-trip encode/decode fidelity.
/// - Optional field defaults.
final class HookEventTests: XCTestCase {

    // MARK: - SessionStart Parsing

    func testParseSessionStartJSON() throws {
        let json = """
        {
            "type": "SessionStart",
            "sessionId": "sess-001",
            "timestamp": "2026-03-17T12:00:00Z",
            "data": {
                "sessionStart": {
                    "model": "claude-sonnet-4-20250514",
                    "agentType": "claude-code",
                    "workingDirectory": "/Users/dev/project"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .sessionStart)
        XCTAssertEqual(event.sessionId, "sess-001")

        guard case .sessionStart(let data) = event.data else {
            XCTFail("Expected sessionStart data")
            return
        }
        XCTAssertEqual(data.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(data.agentType, "claude-code")
        XCTAssertEqual(data.workingDirectory, "/Users/dev/project")
    }

    // MARK: - Stop Parsing

    func testParseStopJSON() throws {
        let json = """
        {
            "type": "Stop",
            "sessionId": "sess-002",
            "timestamp": "2026-03-17T12:01:00Z",
            "data": {
                "stop": {
                    "lastMessage": "Task completed successfully",
                    "reason": "user_stop"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .stop)

        guard case .stop(let data) = event.data else {
            XCTFail("Expected stop data")
            return
        }
        XCTAssertEqual(data.lastMessage, "Task completed successfully")
        XCTAssertEqual(data.reason, "user_stop")
    }

    // MARK: - PreToolUse Parsing

    func testParsePreToolUseJSON() throws {
        let json = """
        {
            "type": "PreToolUse",
            "sessionId": "sess-003",
            "timestamp": "2026-03-17T12:02:00Z",
            "data": {
                "toolUse": {
                    "toolName": "Write",
                    "toolInput": {"path": "/src/main.swift"}
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .preToolUse)

        guard case .toolUse(let data) = event.data else {
            XCTFail("Expected toolUse data")
            return
        }
        XCTAssertEqual(data.toolName, "Write")
        XCTAssertEqual(data.toolInput?["path"], "/src/main.swift")
        XCTAssertNil(data.result)
        XCTAssertNil(data.error)
    }

    // MARK: - PostToolUse Parsing

    func testParsePostToolUseJSON() throws {
        let json = """
        {
            "type": "PostToolUse",
            "sessionId": "sess-004",
            "timestamp": "2026-03-17T12:03:00Z",
            "data": {
                "toolUse": {
                    "toolName": "Read",
                    "toolInput": {"path": "/src/main.swift"},
                    "result": "File read successfully"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .postToolUse)

        guard case .toolUse(let data) = event.data else {
            XCTFail("Expected toolUse data")
            return
        }
        XCTAssertEqual(data.toolName, "Read")
        XCTAssertEqual(data.result, "File read successfully")
        XCTAssertNil(data.error)
    }

    // MARK: - PostToolUseFailure Parsing

    func testParsePostToolUseFailureJSON() throws {
        let json = """
        {
            "type": "PostToolUseFailure",
            "sessionId": "sess-005",
            "timestamp": "2026-03-17T12:04:00Z",
            "data": {
                "toolUse": {
                    "toolName": "Bash",
                    "error": "Command failed with exit code 1"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .postToolUseFailure)

        guard case .toolUse(let data) = event.data else {
            XCTFail("Expected toolUse data")
            return
        }
        XCTAssertEqual(data.toolName, "Bash")
        XCTAssertEqual(data.error, "Command failed with exit code 1")
    }

    // MARK: - SubagentStart Parsing

    func testParseSubagentStartJSON() throws {
        let json = """
        {
            "type": "SubagentStart",
            "sessionId": "sess-006",
            "timestamp": "2026-03-17T12:05:00Z",
            "data": {
                "subagent": {
                    "subagentId": "sub-001",
                    "subagentType": "research"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .subagentStart)

        guard case .subagent(let data) = event.data else {
            XCTFail("Expected subagent data")
            return
        }
        XCTAssertEqual(data.subagentId, "sub-001")
        XCTAssertEqual(data.subagentType, "research")
    }

    // MARK: - Invalid JSON Graceful Error

    func testParseInvalidJSONReturnsError() {
        let invalidJSON = "{ this is not json }"
        let data = Data(invalidJSON.utf8)

        XCTAssertThrowsError(try makeDecoder().decode(HookEvent.self, from: data))
    }

    // MARK: - Unknown Event Type Handling

    func testParseUnknownEventTypeReturnsError() {
        let json = """
        {
            "type": "UnknownFutureEvent",
            "sessionId": "sess-007",
            "timestamp": "2026-03-17T12:06:00Z",
            "data": { "generic": {} }
        }
        """

        XCTAssertThrowsError(try makeDecoder().decode(HookEvent.self, from: Data(json.utf8)))
    }

    // MARK: - Missing Optional Fields

    func testParseEventWithMissingOptionalFields() throws {
        let json = """
        {
            "type": "SessionStart",
            "sessionId": "sess-008",
            "timestamp": "2026-03-17T12:07:00Z",
            "data": {
                "sessionStart": {}
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .sessionStart)

        guard case .sessionStart(let data) = event.data else {
            XCTFail("Expected sessionStart data")
            return
        }
        XCTAssertNil(data.model)
        XCTAssertNil(data.agentType)
        XCTAssertNil(data.workingDirectory)
    }

    // MARK: - Round-trip Encode/Decode

    func testRoundTripEncodeDecode() throws {
        let original = HookEvent(
            type: .preToolUse,
            sessionId: "sess-round-trip",
            timestamp: Date(timeIntervalSince1970: 1_742_212_800),
            data: .toolUse(ToolUseData(
                toolName: "Edit",
                toolInput: ["path": "/src/file.swift"],
                result: nil,
                error: nil
            ))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoded = try makeDecoder().decode(HookEvent.self, from: encoded)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.sessionId, original.sessionId)

        guard case .toolUse(let decodedData) = decoded.data,
              case .toolUse(let originalData) = original.data else {
            XCTFail("Data mismatch after round-trip")
            return
        }
        XCTAssertEqual(decodedData.toolName, originalData.toolName)
        XCTAssertEqual(decodedData.toolInput, originalData.toolInput)
    }

    // MARK: - All Event Types Parse

    func testAllHookEventTypesHaveCorrectRawValues() {
        XCTAssertEqual(HookEventType.sessionStart.rawValue, "SessionStart")
        XCTAssertEqual(HookEventType.sessionEnd.rawValue, "SessionEnd")
        XCTAssertEqual(HookEventType.stop.rawValue, "Stop")
        XCTAssertEqual(HookEventType.userPromptSubmit.rawValue, "UserPromptSubmit")
        XCTAssertEqual(HookEventType.preToolUse.rawValue, "PreToolUse")
        XCTAssertEqual(HookEventType.postToolUse.rawValue, "PostToolUse")
        XCTAssertEqual(HookEventType.postToolUseFailure.rawValue, "PostToolUseFailure")
        XCTAssertEqual(HookEventType.subagentStart.rawValue, "SubagentStart")
        XCTAssertEqual(HookEventType.subagentStop.rawValue, "SubagentStop")
        XCTAssertEqual(HookEventType.notification.rawValue, "Notification")
        XCTAssertEqual(HookEventType.teammateIdle.rawValue, "TeammateIdle")
        XCTAssertEqual(HookEventType.taskCompleted.rawValue, "TaskCompleted")
    }

    // MARK: - Notification Event Parsing

    func testParseNotificationEvent() throws {
        let json = """
        {
            "type": "Notification",
            "sessionId": "sess-009",
            "timestamp": "2026-03-17T12:08:00Z",
            "data": {
                "notification": {
                    "title": "Task done",
                    "body": "Build completed successfully"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .notification)

        guard case .notification(let data) = event.data else {
            XCTFail("Expected notification data")
            return
        }
        XCTAssertEqual(data.title, "Task done")
        XCTAssertEqual(data.body, "Build completed successfully")
    }

    // MARK: - TaskCompleted Event Parsing

    func testParseTaskCompletedEvent() throws {
        let json = """
        {
            "type": "TaskCompleted",
            "sessionId": "sess-010",
            "timestamp": "2026-03-17T12:09:00Z",
            "data": {
                "taskCompleted": {
                    "taskDescription": "Implemented feature X"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .taskCompleted)

        guard case .taskCompleted(let data) = event.data else {
            XCTFail("Expected taskCompleted data")
            return
        }
        XCTAssertEqual(data.taskDescription, "Implemented feature X")
    }

    // MARK: - TeammateIdle Event Parsing

    func testParseTeammateIdleEvent() throws {
        let json = """
        {
            "type": "TeammateIdle",
            "sessionId": "sess-011",
            "timestamp": "2026-03-17T12:10:00Z",
            "data": {
                "teammateIdle": {
                    "teammateId": "mate-001",
                    "reason": "waiting_for_review"
                }
            }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .teammateIdle)

        guard case .teammateIdle(let data) = event.data else {
            XCTFail("Expected teammateIdle data")
            return
        }
        XCTAssertEqual(data.teammateId, "mate-001")
        XCTAssertEqual(data.reason, "waiting_for_review")
    }

    // MARK: - Generic Event Parsing (SessionEnd, UserPromptSubmit)

    func testParseSessionEndAsGenericEvent() throws {
        let json = """
        {
            "type": "SessionEnd",
            "sessionId": "sess-012",
            "timestamp": "2026-03-17T12:11:00Z",
            "data": { "generic": {} }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .sessionEnd)

        guard case .generic = event.data else {
            XCTFail("Expected generic data for SessionEnd")
            return
        }
    }

    func testParseUserPromptSubmitAsGenericEvent() throws {
        let json = """
        {
            "type": "UserPromptSubmit",
            "sessionId": "sess-013",
            "timestamp": "2026-03-17T12:12:00Z",
            "data": { "generic": {} }
        }
        """

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event.type, .userPromptSubmit)

        guard case .generic = event.data else {
            XCTFail("Expected generic data for UserPromptSubmit")
            return
        }
    }

    // MARK: - Helpers

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
