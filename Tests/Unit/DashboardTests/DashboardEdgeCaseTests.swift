// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardEdgeCaseTests.swift - Edge case tests for Agent Intelligence Core (Fase 9).
//
// Test plan (10 edge cases):
// 1.  Dashboard con 0 agentes: panel vacio, sin crash.
// 2.  Dashboard con 20 agentes: todos visibles, sin crash.
// 3.  Hook event con sessionId vacio: no crash, sesion creada con ID vacio.
// 4.  Hook event con timestamp en el futuro: no crash.
// 5.  Rapid hook events (100 en 100ms): sin race condition en el receiver.
// 6.  setPriority en sesion inexistente: no crash.
// 7.  navigateToSession con ID invalido: no crash, sin llamada a navigator.
// 8.  Cerrar sesion mientras dashboard la muestra: row removed cleanly.
// 9.  Dashboard toggle rapido (10 veces): stable.
// 10. HookReceiver: 1000 events en serie: contador exacto.

import XCTest
import Combine
@testable import CocxyTerminal

@MainActor
final class DashboardEdgeCaseTests: XCTestCase {

    private var sut: AgentDashboardViewModel!
    private var receiver: HookEventReceiverImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AgentDashboardViewModel()
        receiver = HookEventReceiverImpl()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        receiver = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Edge Case 1: Dashboard con 0 agentes

    func testDashboardWithZeroAgentsIsEmptyAndDoesNotCrash() {
        // No events emitted. Dashboard must be in a consistent empty state.
        XCTAssertTrue(sut.sessions.isEmpty,
                       "Dashboard with no agents should have zero sessions")
        XCTAssertFalse(sut.isVisible,
                        "Dashboard should start hidden")
        XCTAssertNil(sut.mostUrgentSession(),
                     "mostUrgentSession should return nil when empty")
        XCTAssertTrue(sut.sessions(withState: .working).isEmpty,
                      "sessions(withState:) should return empty array when no sessions")
        XCTAssertNil(sut.activitySummary(for: "any-id"),
                     "activitySummary for any id should return nil when empty")
    }

    // MARK: - Edge Case 2: Dashboard con 20 agentes

    func testDashboardWith20AgentsAllVisibleAndNocrash() {
        let count = 20
        for index in 0..<count {
            let event = makeSessionStartEvent(sessionId: "sess-\(index)",
                                              projectDir: "/proj/\(index)")
            sut.processHookEvent(event)
        }

        XCTAssertEqual(sut.sessions.count, count,
                        "All 20 sessions must appear in the dashboard")

        // All sessions should be accounted for with unique IDs
        let ids = Set(sut.sessions.map { $0.id })
        XCTAssertEqual(ids.count, count,
                        "All 20 session IDs must be unique")

        // mostUrgentSession must not crash and must return one of the known sessions
        let urgent = sut.mostUrgentSession()
        XCTAssertNotNil(urgent, "mostUrgentSession should return a session when 20 are present")
        XCTAssertTrue(ids.contains(urgent!.id), "Urgent session must be one of the 20")
    }

    // MARK: - Edge Case 3: Hook event con sessionId vacio

    func testHookEventWithEmptySessionIdHandledGracefully() {
        // A real event from Claude Code should never have an empty sessionId, but
        // defensive code must not crash.
        let event = HookEvent(
            type: .sessionStart,
            sessionId: "",
            timestamp: Date(),
            data: .sessionStart(SessionStartData(agentType: "claude-code"))
        )

        // Must not crash
        sut.processHookEvent(event)

        // Session is created with the empty string as ID.
        XCTAssertEqual(sut.sessions.count, 1,
                        "Session with empty sessionId should still be created")
        XCTAssertEqual(sut.sessions.first?.id, "",
                        "Session ID must match the (empty) sessionId from the event")

        // Subsequent events with the same empty ID must update the same session.
        let toolEvent = HookEvent(
            type: .postToolUse,
            sessionId: "",
            timestamp: Date(),
            data: .toolUse(ToolUseData(toolName: "Read"))
        )
        sut.processHookEvent(toolEvent)

        XCTAssertEqual(sut.sessions.count, 1,
                        "Second event with empty sessionId should update the same session, not add a new one")
        XCTAssertEqual(sut.sessions.first?.state, .working)
    }

    // MARK: - Edge Case 4: Hook event con timestamp en el futuro

    func testHookEventWithFutureTimestampDoesNotCrash() {
        // A timestamp 100 years in the future must be accepted without crashing.
        let farFuture = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 100)

        let startEvent = HookEvent(
            type: .sessionStart,
            sessionId: "sess-future",
            timestamp: farFuture,
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, "sess-future")

        // Follow up with a tool use with the same future timestamp.
        let toolEvent = HookEvent(
            type: .postToolUse,
            sessionId: "sess-future",
            timestamp: farFuture,
            data: .toolUse(ToolUseData(toolName: "Write"))
        )
        sut.processHookEvent(toolEvent)

        XCTAssertEqual(sut.sessions.first?.lastActivityTime, farFuture,
                        "Future timestamp must be stored without modification")
        // No crash is the main assertion -- we reach this line if all is well.
    }

    // MARK: - Edge Case 5: Rapid hook events (100 en 100ms) sin race condition

    func testRapidHookEventsFromBackgroundThreadsDoNotCauseRaceConditions() {
        // HookEventReceiverImpl uses NSLock for thread safety.
        // Fire 100 SessionStart events from concurrent background threads.
        // Capture receiver into a local constant so the closure captures a
        // non-@MainActor reference to the @unchecked Sendable object.
        let iterations = 100
        let group = DispatchGroup()
        let localReceiver = receiver!
        let jsonTemplate = { (i: Int) -> String in
            """
            {
                "type": "SessionStart",
                "sessionId": "sess-rapid-\(i)",
                "timestamp": "2026-03-17T12:00:00Z",
                "data": {
                    "sessionStart": {
                        "agentType": "claude-code"
                    }
                }
            }
            """
        }

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let data = Data(jsonTemplate(i).utf8)
                _ = localReceiver.receiveRawJSON(data)
                group.leave()
            }
        }

        let expectation = expectation(description: "All 100 concurrent events processed")
        group.notify(queue: .main) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10.0)

        // All 100 must have been counted as successes.
        XCTAssertEqual(receiver.receivedEventCount, iterations,
                        "All \(iterations) rapid events must be counted as received")
        XCTAssertEqual(receiver.failedEventCount, 0,
                        "No events should fail if the JSON is valid")

        // All session IDs must be in the active set.
        XCTAssertEqual(receiver.activeSessionIds.count, iterations,
                        "All \(iterations) sessions must be tracked as active after rapid fire")
    }

    // MARK: - Edge Case 6: setPriority en sesion inexistente

    func testSetPriorityOnNonExistentSessionDoesNotCrash() {
        // No sessions exist. This call must be a silent no-op.
        sut.setPriority(.focus, for: "ghost-session-id")

        // Dashboard state must remain unchanged.
        XCTAssertTrue(sut.sessions.isEmpty,
                       "Sessions must remain empty after setPriority on nonexistent ID")
    }

    func testSetPriorityOnNonExistentSessionAfterOtherSessionsExistDoesNotCorruptState() {
        // Create a real session first.
        let event = makeSessionStartEvent(sessionId: "sess-real")
        sut.processHookEvent(event)

        XCTAssertEqual(sut.sessions.count, 1)

        // Now try to set priority on a non-existent session. Must be a no-op.
        sut.setPriority(.priority, for: "definitely-does-not-exist")

        // Real session is untouched.
        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, "sess-real")
        XCTAssertEqual(sut.sessions.first?.priority, .standard,
                        "Real session priority must not change after setPriority on nonexistent ID")
    }

    // MARK: - Edge Case 7: navigateToSession con ID invalido

    func testNavigateToSessionWithInvalidIdDoesNotCrash() {
        let navigator = MockEdgeCaseNavigator()
        sut.tabNavigator = navigator

        // No sessions exist. Must be a silent no-op.
        sut.navigateToSession("completely-invalid-id-12345")

        XCTAssertEqual(navigator.focusTabCallCount, 0,
                        "focusTab must not be called for nonexistent session ID")
    }

    func testNavigateToSessionWithInvalidIdWhenSessionsExistDoesNotCrash() {
        let navigator = MockEdgeCaseNavigator()
        sut.tabNavigator = navigator

        // Create a real session so the store is not empty.
        let event = makeSessionStartEvent(sessionId: "sess-valid")
        sut.processHookEvent(event)

        // Navigate to a different, nonexistent ID.
        sut.navigateToSession("invalid-id-not-in-store")

        XCTAssertEqual(navigator.focusTabCallCount, 0,
                        "focusTab must not be called for nonexistent session ID")
    }

    // MARK: - Edge Case 8: Cerrar sesion mientras dashboard la muestra

    func testSessionEndWhileDashboardIsVisibleRemovesRowCleanly() {
        // Show the dashboard first.
        sut.toggleVisibility()
        XCTAssertTrue(sut.isVisible)

        // Add 3 sessions.
        for index in 0..<3 {
            sut.processHookEvent(makeSessionStartEvent(sessionId: "sess-visible-\(index)"))
        }
        XCTAssertEqual(sut.sessions.count, 3)

        // Close the middle session while the panel is visible.
        let endEvent = HookEvent(
            type: .sessionEnd,
            sessionId: "sess-visible-1",
            timestamp: Date(),
            data: .generic
        )
        sut.processHookEvent(endEvent)

        XCTAssertEqual(sut.sessions.count, 2,
                        "Closed session must be removed from the visible dashboard")
        XCTAssertFalse(sut.sessions.map { $0.id }.contains("sess-visible-1"),
                        "The closed session ID must not appear in the session list")
        XCTAssertTrue(sut.isVisible,
                       "Dashboard visibility must not be affected by session removal")

        // Remaining sessions must be the first and the third.
        let remainingIds = Set(sut.sessions.map { $0.id })
        XCTAssertTrue(remainingIds.contains("sess-visible-0"))
        XCTAssertTrue(remainingIds.contains("sess-visible-2"))
    }

    // MARK: - Edge Case 9: Dashboard toggle rapido (10 veces)

    func testRapidDashboardToggleRemainsStable() {
        XCTAssertFalse(sut.isVisible, "Must start hidden")

        let toggleCount = 10
        for _ in 0..<toggleCount {
            sut.toggleVisibility()
        }

        // 10 toggles starting from false: result is false (even number of toggles).
        XCTAssertFalse(sut.isVisible,
                        "After \(toggleCount) rapid toggles (even count), isVisible must be false")
    }

    func testRapidDashboardToggleWithSessionsPresent() {
        // Add some sessions to ensure toggle does not affect session data.
        for index in 0..<5 {
            sut.processHookEvent(makeSessionStartEvent(sessionId: "sess-tg-\(index)"))
        }

        for _ in 0..<10 {
            sut.toggleVisibility()
        }

        // Sessions must be unaffected by toggles.
        XCTAssertEqual(sut.sessions.count, 5,
                        "Session count must not be affected by rapid toggles")
    }

    // MARK: - Edge Case 10: HookReceiver: 1000 events - todos contados correctamente

    func testHookReceiverCounts1000EventsCorrectly() {
        // Send 1000 valid events in series (single thread to verify counter correctness).
        let total = 1000
        let baseJSON = { (i: Int) -> String in
            """
            {
                "type": "SessionStart",
                "sessionId": "sess-bulk-\(i)",
                "timestamp": "2026-03-17T12:00:00Z",
                "data": {
                    "sessionStart": {
                        "agentType": "claude-code"
                    }
                }
            }
            """
        }

        for i in 0..<total {
            let data = Data(baseJSON(i).utf8)
            let result = receiver.receiveRawJSON(data)
            XCTAssertTrue(result, "Event \(i) must be received successfully")
        }

        XCTAssertEqual(receiver.receivedEventCount, total,
                        "receivedEventCount must be exactly \(total) after \(total) valid events")
        XCTAssertEqual(receiver.failedEventCount, 0,
                        "failedEventCount must remain 0 for all-valid inputs")
        XCTAssertEqual(receiver.activeSessionIds.count, total,
                        "All \(total) sessions must be active (no SessionEnd sent)")
    }

    func testHookReceiverCountsMixedValidAndInvalidCorrectly() {
        // Send alternating valid/invalid events.
        let validJSON = """
        {
            "type": "SessionStart",
            "sessionId": "sess-mixed",
            "timestamp": "2026-03-17T12:00:00Z",
            "data": { "sessionStart": { "agentType": "claude-code" } }
        }
        """
        let invalidJSON = "not json at all"

        let rounds = 50
        for _ in 0..<rounds {
            _ = receiver.receiveRawJSON(Data(validJSON.utf8))
            _ = receiver.receiveRawJSON(Data(invalidJSON.utf8))
        }

        // Each round: 1 success + 1 failure.
        // Note: the same sessionId "sess-mixed" is reused so activeSessionIds stays at 1.
        XCTAssertEqual(receiver.receivedEventCount, rounds,
                        "receivedEventCount must equal number of valid events")
        XCTAssertEqual(receiver.failedEventCount, rounds,
                        "failedEventCount must equal number of invalid events")
    }
}

// MARK: - Test Helpers

extension DashboardEdgeCaseTests {

    private func makeSessionStartEvent(
        sessionId: String,
        projectDir: String = "/Users/test/project",
        agentType: String = "claude-code"
    ) -> HookEvent {
        HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                agentType: agentType,
                workingDirectory: projectDir
            ))
        )
    }
}

// MARK: - Mock Navigator

/// Minimal DashboardTabNavigating mock for edge case tests.
@MainActor
private final class MockEdgeCaseNavigator: DashboardTabNavigating {
    private(set) var focusedTabIds: [TabID] = []
    var focusTabCallCount: Int { focusedTabIds.count }

    func focusTab(id: TabID) {
        focusedTabIds.append(id)
    }
}
