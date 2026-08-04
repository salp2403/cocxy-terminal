// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import XCTest
@testable import CocxyTerminal

final class AppSocketDeliveryTests: XCTestCase {
    func test_sendCommand_withDroppedDelivery_returnsFailure() {
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in .internalTrusted(for: request) },
            tabManager: nil,
            hookEventReceiver: nil,
            sendTextProvider: { _ in false }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "v4-8-dropped",
            command: "send",
            params: ["text": "ls"]
        ))

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Terminal input could not be delivered")
    }

    func test_sendKeyCommand_withDroppedDelivery_returnsFailure() {
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in .internalTrusted(for: request) },
            tabManager: nil,
            hookEventReceiver: nil,
            sendKeyProvider: { _ in false }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "v4-9-dropped",
            command: "send-key",
            params: ["key": "enter"]
        ))

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Terminal input could not be delivered")
    }
}
