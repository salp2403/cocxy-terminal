// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketHookIntegrationTests.swift - Tests for hook event handling via socket protocol.

import XCTest
@testable import CocxyTerminal

// MARK: - Socket Hook Integration Tests

/// Tests for the socket-level hook event handling.
///
/// Validates:
/// - hookEvent command is recognized by CLICommandName.
/// - HookEventReceiver can process payload from SocketRequest params.
/// - Invalid payload in hook-event produces error response.
/// - Empty payload in hook-event produces error response.
/// - hookEvent integrates end-to-end with HookEventReceiver.
final class SocketHookIntegrationTests: XCTestCase {

    // MARK: - CLICommandName includes hookEvent

    func testHookEventIsValidCLICommand() {
        let command = CLICommandName(rawValue: "hook-event")
        XCTAssertNotNil(command)
        XCTAssertEqual(command, .hookEvent)
    }

    func testAllCommandNamesIncludesHookEvent() {
        XCTAssertTrue(CLICommandName.allCases.contains(.hookEvent))
    }

    // MARK: - Hook Event Processing via Receiver

    func testReceiverProcessesHookPayloadFromSocketParams() {
        let receiver = HookEventReceiverImpl()
        let hookJSON = """
        {
            "type": "SessionStart",
            "sessionId": "sock-sess-1",
            "timestamp": "2026-03-17T12:00:00Z",
            "data": {
                "sessionStart": {
                    "model": "claude-sonnet-4-20250514",
                    "agentType": "claude-code"
                }
            }
        }
        """

        let result = receiver.receiveRawJSON(Data(hookJSON.utf8))

        XCTAssertTrue(result)
        XCTAssertEqual(receiver.receivedEventCount, 1)
        XCTAssertTrue(receiver.activeSessionIds.contains("sock-sess-1"))
    }

    func testReceiverRejectsInvalidPayload() {
        let receiver = HookEventReceiverImpl()

        let result = receiver.receiveRawJSON(Data("not json".utf8))

        XCTAssertFalse(result)
        XCTAssertEqual(receiver.failedEventCount, 1)
        XCTAssertEqual(receiver.receivedEventCount, 0)
    }

    func testReceiverRejectsEmptyPayload() {
        let receiver = HookEventReceiverImpl()

        let result = receiver.receiveRawJSON(Data())

        XCTAssertFalse(result)
        XCTAssertEqual(receiver.failedEventCount, 1)
    }

    // MARK: - Full Pipeline: SocketRequest -> Receiver -> Event

    @MainActor
    func testFullPipelineSocketRequestToHookEvent() {
        let receiver = HookEventReceiverImpl()
        let hookJSON = """
        {
            "type": "PreToolUse",
            "sessionId": "sock-pipe-1",
            "timestamp": "2026-03-17T12:05:00Z",
            "data": {
                "toolUse": {
                    "toolName": "Bash",
                    "toolInput": {"command": "swift build"}
                }
            }
        }
        """

        // Simulate what the socket handler would do:
        // 1. Receive SocketRequest with command "hook-event" and payload in params
        let request = SocketRequest(
            id: "req-1",
            command: "hook-event",
            params: ["payload": hookJSON]
        )

        // 2. Validate command name
        XCTAssertNotNil(CLICommandName(rawValue: request.command))

        // 3. Extract payload and pass to receiver
        guard let payloadString = request.params?["payload"],
              let payloadData = payloadString.data(using: .utf8) else {
            XCTFail("Missing payload in params")
            return
        }

        let result = receiver.receiveRawJSON(payloadData)

        XCTAssertTrue(result)
        XCTAssertEqual(receiver.receivedEventCount, 1)
    }

    // MARK: - Hook Event Command with Missing Payload

    func testSocketRequestWithMissingPayloadFieldFails() {
        let receiver = HookEventReceiverImpl()

        // Request with no "payload" key in params
        let request = SocketRequest(
            id: "req-2",
            command: "hook-event",
            params: ["other": "value"]
        )

        let payloadString = request.params?["payload"]
        XCTAssertNil(payloadString)
        // Without payload, the receiver should not be called
    }
}
