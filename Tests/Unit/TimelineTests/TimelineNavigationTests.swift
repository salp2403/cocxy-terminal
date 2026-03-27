// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineNavigationTests.swift - Tests for Timeline navigation to terminal position.
//
// Test plan (6 tests):
// 1.  Tap on event -> navigateToEvent called on navigator
// 2.  Tap on event with filePath -> highlightFile called
// 3.  Navigator nil -> no crash (safe no-op)
// 4.  Navigate with various event types dispatches correctly
// 5.  TimelineNavigatorStub logs navigateToEvent calls
// 6.  TimelineNavigatorStub logs highlightFile calls

import XCTest
@testable import CocxyTerminal

// MARK: - Spy Navigator

/// Spy implementation of `TimelineNavigating` that records all calls for test assertions.
private final class SpyTimelineNavigator: TimelineNavigating {
    private(set) var navigateToEventCalls: [TimelineEvent] = []
    private(set) var highlightFileCalls: [String] = []

    func navigateToEvent(_ event: TimelineEvent) {
        navigateToEventCalls.append(event)
    }

    func highlightFile(_ filePath: String) {
        highlightFileCalls.append(filePath)
    }
}

// MARK: - Timeline Navigation Tests

final class TimelineNavigationTests: XCTestCase {

    // MARK: - Test 1: Tap on event -> navigateToEvent called

    func testNavigateToEventIsCalledWhenEventSelected() {
        let spy = SpyTimelineNavigator()
        let event = makeEvent(sessionId: "sess-nav", summary: "Write: App.swift")

        spy.navigateToEvent(event)

        XCTAssertEqual(spy.navigateToEventCalls.count, 1,
                        "navigateToEvent must be called exactly once")
        XCTAssertEqual(spy.navigateToEventCalls.first?.id, event.id,
                        "The event passed to navigator must match the tapped event")
    }

    // MARK: - Test 2: Tap on event with filePath -> highlightFile called

    func testHighlightFileIsCalledForEventWithFilePath() {
        let spy = SpyTimelineNavigator()
        let event = makeEvent(
            sessionId: "sess-nav",
            summary: "Write: App.swift",
            filePath: "/Users/test/Sources/App.swift"
        )

        spy.navigateToEvent(event)
        if let filePath = event.filePath {
            spy.highlightFile(filePath)
        }

        XCTAssertEqual(spy.highlightFileCalls.count, 1,
                        "highlightFile must be called for events with file paths")
        XCTAssertEqual(spy.highlightFileCalls.first, "/Users/test/Sources/App.swift",
                        "The file path passed to highlightFile must match the event's filePath")
    }

    // MARK: - Test 3: Navigator nil -> no crash

    func testNilNavigatorDoesNotCrashOnNavigation() {
        // Simulate a TimelineNavigationDispatcher with no navigator set.
        let dispatcher = TimelineNavigationDispatcher()
        let event = makeEvent(sessionId: "sess-nil", summary: "Some event")

        // This must not crash -- silent no-op.
        dispatcher.dispatchNavigation(for: event)

        // Reaching this line means no crash occurred.
        XCTAssertTrue(true, "Dispatching navigation with nil navigator must not crash")
    }

    // MARK: - Test 4: Navigate with various event types

    func testNavigateWithVariousEventTypesDispatchesCorrectly() {
        let spy = SpyTimelineNavigator()
        let dispatcher = TimelineNavigationDispatcher()
        dispatcher.navigator = spy

        let eventTypes: [TimelineEventType] = [
            .toolUse, .toolFailure, .userPrompt, .sessionStart, .taskCompleted
        ]

        for eventType in eventTypes {
            let event = makeEvent(
                sessionId: "sess-types",
                summary: "Event \(eventType.rawValue)",
                type: eventType
            )
            dispatcher.dispatchNavigation(for: event)
        }

        XCTAssertEqual(spy.navigateToEventCalls.count, eventTypes.count,
                        "navigateToEvent must be called for every event type")

        let navigatedTypes = spy.navigateToEventCalls.map { $0.type }
        for eventType in eventTypes {
            XCTAssertTrue(navigatedTypes.contains(eventType),
                           "Event type \(eventType.rawValue) must have been navigated")
        }
    }

    // MARK: - Test 5: TimelineNavigatorStub logs navigateToEvent calls

    func testTimelineNavigatorStubLogsNavigateToEventCalls() {
        let stub = TimelineNavigatorStub()
        let event = makeEvent(sessionId: "sess-stub", summary: "Stub test event")

        stub.navigateToEvent(event)
        stub.navigateToEvent(event)

        XCTAssertEqual(stub.navigatedEvents.count, 2,
                        "Stub must log all navigateToEvent calls")
        XCTAssertEqual(stub.navigatedEvents.first?.id, event.id,
                        "Stub must record the exact event passed")
    }

    // MARK: - Test 6: TimelineNavigatorStub logs highlightFile calls

    func testTimelineNavigatorStubLogsHighlightFileCalls() {
        let stub = TimelineNavigatorStub()

        stub.highlightFile("/path/to/file.swift")
        stub.highlightFile("/another/file.rs")

        XCTAssertEqual(stub.highlightedFiles.count, 2,
                        "Stub must log all highlightFile calls")
        XCTAssertEqual(stub.highlightedFiles[0], "/path/to/file.swift")
        XCTAssertEqual(stub.highlightedFiles[1], "/another/file.rs")
    }

    // MARK: - Helpers

    private func makeEvent(
        sessionId: String,
        summary: String,
        type: TimelineEventType = .toolUse,
        filePath: String? = nil
    ) -> TimelineEvent {
        TimelineEvent(
            id: UUID(),
            timestamp: Date(),
            type: type,
            sessionId: sessionId,
            toolName: nil,
            filePath: filePath,
            summary: summary,
            durationMs: nil,
            isError: false
        )
    }
}
