// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookEventReceiverTests.swift - Tests for the hook event receiver.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Hook Event Receiver Tests

/// Tests for `HookEventReceiverImpl` covering:
/// - Valid event reception and Combine publishing.
/// - Invalid JSON handling (no crash, no publish).
/// - Multiple events published in order.
/// - Active session tracking (add/remove).
/// - Event counter increments.
/// - Thread safety with concurrent calls.
/// - Diagnostics (received/failed counts).
/// - Empty data handling.
@MainActor
final class HookEventReceiverTests: XCTestCase {

    private var sut: HookEventReceiverImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = HookEventReceiverImpl()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Valid Event Reception

    func testReceiveValidEventPublishesViaCombine() {
        let json = makeSessionStartJSON(sessionId: "sess-recv-1")
        var receivedEvents: [HookEvent] = []

        sut.eventPublisher
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)

        let result = sut.receiveRawJSON(Data(json.utf8))

        XCTAssertTrue(result)
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.sessionId, "sess-recv-1")
        XCTAssertEqual(receivedEvents.first?.type, .sessionStart)
    }

    // MARK: - Invalid JSON Handling

    func testReceiveInvalidJSONDoesNotCrashOrPublish() {
        var receivedEvents: [HookEvent] = []

        sut.eventPublisher
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)

        let result = sut.receiveRawJSON(Data("{ invalid json }".utf8))

        XCTAssertFalse(result)
        XCTAssertTrue(receivedEvents.isEmpty)
    }

    func testReceiveEmptyDataDoesNotCrashOrPublish() {
        var receivedEvents: [HookEvent] = []

        sut.eventPublisher
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)

        let result = sut.receiveRawJSON(Data())

        XCTAssertFalse(result)
        XCTAssertTrue(receivedEvents.isEmpty)
    }

    // MARK: - Multiple Events in Order

    func testMultipleEventsPublishedInOrder() {
        var receivedSessionIds: [String] = []

        sut.eventPublisher
            .sink { event in
                receivedSessionIds.append(event.sessionId)
            }
            .store(in: &cancellables)

        let sessions = ["sess-a", "sess-b", "sess-c"]
        for sessionId in sessions {
            let json = makeSessionStartJSON(sessionId: sessionId)
            _ = sut.receiveRawJSON(Data(json.utf8))
        }

        XCTAssertEqual(receivedSessionIds, sessions)
    }

    // MARK: - Active Session Tracking

    func testSessionStartAddsToActiveSessions() {
        let json = makeSessionStartJSON(sessionId: "sess-active-1")
        _ = sut.receiveRawJSON(Data(json.utf8))

        XCTAssertTrue(sut.activeSessionIds.contains("sess-active-1"))
    }

    func testSessionEndRemovesFromActiveSessions() {
        // First add a session
        let startJSON = makeSessionStartJSON(sessionId: "sess-remove-1")
        _ = sut.receiveRawJSON(Data(startJSON.utf8))

        XCTAssertTrue(sut.activeSessionIds.contains("sess-remove-1"))

        // Then end it
        let endJSON = makeSessionEndJSON(sessionId: "sess-remove-1")
        _ = sut.receiveRawJSON(Data(endJSON.utf8))

        XCTAssertFalse(sut.activeSessionIds.contains("sess-remove-1"))
    }

    func testStopEventRemovesFromActiveSessions() {
        let startJSON = makeSessionStartJSON(sessionId: "sess-stop-1")
        _ = sut.receiveRawJSON(Data(startJSON.utf8))

        let stopJSON = makeStopJSON(sessionId: "sess-stop-1")
        _ = sut.receiveRawJSON(Data(stopJSON.utf8))

        XCTAssertFalse(sut.activeSessionIds.contains("sess-stop-1"))
    }

    func testMultipleSessionsTrackedIndependently() {
        let start1 = makeSessionStartJSON(sessionId: "sess-multi-1")
        let start2 = makeSessionStartJSON(sessionId: "sess-multi-2")
        _ = sut.receiveRawJSON(Data(start1.utf8))
        _ = sut.receiveRawJSON(Data(start2.utf8))

        XCTAssertEqual(sut.activeSessionIds.count, 2)
        XCTAssertTrue(sut.activeSessionIds.contains("sess-multi-1"))
        XCTAssertTrue(sut.activeSessionIds.contains("sess-multi-2"))

        // End only session 1
        let end1 = makeSessionEndJSON(sessionId: "sess-multi-1")
        _ = sut.receiveRawJSON(Data(end1.utf8))

        XCTAssertEqual(sut.activeSessionIds.count, 1)
        XCTAssertFalse(sut.activeSessionIds.contains("sess-multi-1"))
        XCTAssertTrue(sut.activeSessionIds.contains("sess-multi-2"))
    }

    // MARK: - Event Counter

    func testEventCounterIncrementsOnSuccess() {
        let json = makeSessionStartJSON(sessionId: "sess-count-1")
        _ = sut.receiveRawJSON(Data(json.utf8))
        _ = sut.receiveRawJSON(Data(json.utf8))

        XCTAssertEqual(sut.receivedEventCount, 2)
        XCTAssertEqual(sut.failedEventCount, 0)
    }

    func testFailedCounterIncrementsOnInvalidJSON() {
        _ = sut.receiveRawJSON(Data("bad".utf8))
        _ = sut.receiveRawJSON(Data("also bad".utf8))

        XCTAssertEqual(sut.receivedEventCount, 0)
        XCTAssertEqual(sut.failedEventCount, 2)
    }

    func testMixedSuccessAndFailureCounts() {
        let validJSON = makeSessionStartJSON(sessionId: "sess-mix")
        _ = sut.receiveRawJSON(Data(validJSON.utf8))
        _ = sut.receiveRawJSON(Data("bad".utf8))
        _ = sut.receiveRawJSON(Data(validJSON.utf8))

        XCTAssertEqual(sut.receivedEventCount, 2)
        XCTAssertEqual(sut.failedEventCount, 1)
    }

    // MARK: - Thread Safety

    func testConcurrentReceiveDoesNotCrash() {
        let iterations = 100
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let json = self.makeSessionStartJSON(sessionId: "sess-thread-\(i)")
                _ = self.sut.receiveRawJSON(Data(json.utf8))
                group.leave()
            }
        }

        let expectation = expectation(description: "All concurrent operations complete")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)

        // Total should be 100 received, 0 failed
        XCTAssertEqual(sut.receivedEventCount, iterations)
        XCTAssertEqual(sut.failedEventCount, 0)
    }

    // MARK: - Helpers

    private func makeSessionStartJSON(sessionId: String) -> String {
        """
        {
            "type": "SessionStart",
            "sessionId": "\(sessionId)",
            "timestamp": "2026-03-17T12:00:00Z",
            "data": {
                "sessionStart": {
                    "model": "claude-sonnet-4-20250514",
                    "agentType": "claude-code"
                }
            }
        }
        """
    }

    private func makeSessionEndJSON(sessionId: String) -> String {
        """
        {
            "type": "SessionEnd",
            "sessionId": "\(sessionId)",
            "timestamp": "2026-03-17T12:30:00Z",
            "data": { "generic": {} }
        }
        """
    }

    private func makeStopJSON(sessionId: String) -> String {
        """
        {
            "type": "Stop",
            "sessionId": "\(sessionId)",
            "timestamp": "2026-03-17T12:30:00Z",
            "data": {
                "stop": {
                    "lastMessage": "Done",
                    "reason": "end_turn"
                }
            }
        }
        """
    }
}
