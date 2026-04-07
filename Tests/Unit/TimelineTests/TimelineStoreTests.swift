// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineStoreTests.swift - Tests for AgentTimelineStoreImpl.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Timeline Store Tests

/// Tests for `AgentTimelineStoreImpl` covering:
///
/// 1. Add event -> retrievable by session ID
/// 2. Events for session -> filtered correctly
/// 3. Multiple sessions -> isolated from each other
/// 4. Max 1000 events -> FIFO eviction of oldest
/// 5. Event count returns correct value
/// 6. Clear events removes all events for session
/// 7. Empty session -> returns empty array
/// 8. Hook event -> auto-mapped to timeline event (via addEvent)
/// 9. Pattern detection -> fallback event with stateChange type
/// 10. Publisher emits on addEvent
/// 11. Thread safety: add from multiple queues concurrently
/// 12. All events across sessions returns merged sorted list
/// 13. Export JSON delegates to TimelineExporter
/// 14. Export Markdown delegates to TimelineExporter
final class TimelineStoreTests: XCTestCase {

    private var sut: AgentTimelineStoreImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AgentTimelineStoreImpl()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Test 1: Add Event Is Retrievable

    func testAddEventIsRetrievableBySessionId() {
        let event = makeEvent(sessionId: "sess-1", summary: "Write: App.swift")

        sut.addEvent(event)

        let retrieved = sut.events(for: "sess-1")
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.id, event.id)
        XCTAssertEqual(retrieved.first?.summary, "Write: App.swift")
    }

    // MARK: - Test 2: Events Filtered by Session

    func testEventsForSessionFilteredCorrectly() {
        let event1 = makeEvent(sessionId: "sess-A", summary: "Event A")
        let event2 = makeEvent(sessionId: "sess-B", summary: "Event B")
        let event3 = makeEvent(sessionId: "sess-A", summary: "Event A2")

        sut.addEvent(event1)
        sut.addEvent(event2)
        sut.addEvent(event3)

        let sessAEvents = sut.events(for: "sess-A")
        XCTAssertEqual(sessAEvents.count, 2)
        XCTAssertEqual(sessAEvents[0].summary, "Event A")
        XCTAssertEqual(sessAEvents[1].summary, "Event A2")

        let sessBEvents = sut.events(for: "sess-B")
        XCTAssertEqual(sessBEvents.count, 1)
        XCTAssertEqual(sessBEvents[0].summary, "Event B")
    }

    // MARK: - Test 3: Multiple Sessions Are Isolated

    func testMultipleSessionsAreIsolated() {
        for i in 0..<5 {
            sut.addEvent(makeEvent(sessionId: "session-\(i)", summary: "Event \(i)"))
        }

        for i in 0..<5 {
            let events = sut.events(for: "session-\(i)")
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.summary, "Event \(i)")
        }

        // Cross-check: no contamination
        XCTAssertTrue(sut.events(for: "session-99").isEmpty)
    }

    // MARK: - Test 4: FIFO Eviction at Max Capacity

    func testFIFOEvictionAtMaxCapacity() {
        let store = AgentTimelineStoreImpl(maxEventsPerSession: 5)

        // Add 7 events -- first 2 should be evicted
        for i in 0..<7 {
            store.addEvent(makeEvent(
                sessionId: "sess-evict",
                summary: "Event \(i)"
            ))
        }

        let events = store.events(for: "sess-evict")
        XCTAssertEqual(events.count, 5)
        // The first 2 (Event 0, Event 1) should have been evicted
        XCTAssertEqual(events[0].summary, "Event 2")
        XCTAssertEqual(events[4].summary, "Event 6")
    }

    // MARK: - Test 5: Event Count Correct

    func testEventCountReturnsCorrectValue() {
        XCTAssertEqual(sut.eventCount(for: "empty"), 0)

        sut.addEvent(makeEvent(sessionId: "counted", summary: "A"))
        XCTAssertEqual(sut.eventCount(for: "counted"), 1)

        sut.addEvent(makeEvent(sessionId: "counted", summary: "B"))
        sut.addEvent(makeEvent(sessionId: "counted", summary: "C"))
        XCTAssertEqual(sut.eventCount(for: "counted"), 3)

        // Different session should not affect count
        sut.addEvent(makeEvent(sessionId: "other", summary: "D"))
        XCTAssertEqual(sut.eventCount(for: "counted"), 3)
        XCTAssertEqual(sut.eventCount(for: "other"), 1)
    }

    // MARK: - Test 6: Clear Events Removes Session

    func testClearEventsRemovesAllEventsForSession() {
        sut.addEvent(makeEvent(sessionId: "sess-clear", summary: "A"))
        sut.addEvent(makeEvent(sessionId: "sess-clear", summary: "B"))
        sut.addEvent(makeEvent(sessionId: "sess-keep", summary: "C"))

        XCTAssertEqual(sut.eventCount(for: "sess-clear"), 2)

        sut.clearEvents(for: "sess-clear")

        XCTAssertEqual(sut.eventCount(for: "sess-clear"), 0)
        XCTAssertTrue(sut.events(for: "sess-clear").isEmpty)
        // Other session unaffected
        XCTAssertEqual(sut.eventCount(for: "sess-keep"), 1)
    }

    // MARK: - Test 7: Empty Session Returns Empty Array

    func testEmptySessionReturnsEmptyArray() {
        let events = sut.events(for: "nonexistent-session")
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(sut.eventCount(for: "nonexistent-session"), 0)
    }

    // MARK: - Test 8: Hook Event Maps to Timeline Event

    func testHookToolUseEventMapsToTimelineEvent() {
        let event = TimelineEvent(
            type: .toolUse,
            sessionId: "sess-hook",
            toolName: "Write",
            filePath: "/Users/test/Sources/App.swift",
            summary: "Write: App.swift",
            durationMs: 120,
            isError: false
        )

        sut.addEvent(event)

        let retrieved = sut.events(for: "sess-hook")
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.type, .toolUse)
        XCTAssertEqual(retrieved.first?.toolName, "Write")
        XCTAssertEqual(retrieved.first?.filePath, "/Users/test/Sources/App.swift")
        XCTAssertEqual(retrieved.first?.durationMs, 120)
        XCTAssertFalse(retrieved.first?.isError ?? true)
    }

    func testHookEventMappingPreservesWindowMetadata() {
        let windowID = WindowID()
        let hookEvent = HookEvent(
            type: .postToolUse,
            sessionId: "sess-window",
            timestamp: Date(),
            data: .toolUse(ToolUseData(
                toolName: "Write",
                toolInput: ["file_path": "/Users/test/Sources/App.swift"]
            ))
        )

        let event = TimelineEvent.from(
            hookEvent: hookEvent,
            windowID: windowID,
            windowLabel: "Window 2"
        )
        sut.addEvent(event)

        let retrieved = sut.events(for: "sess-window")
        XCTAssertEqual(retrieved.first?.windowID, windowID)
        XCTAssertEqual(retrieved.first?.windowLabel, "Window 2")
    }

    // MARK: - Test 9: Pattern Detection Fallback Event

    func testPatternDetectionFallbackEventAddedAsStateChange() {
        let event = TimelineEvent(
            type: .stateChange,
            sessionId: "sess-pattern",
            summary: "Agent detected: working",
            isError: false
        )

        sut.addEvent(event)

        let retrieved = sut.events(for: "sess-pattern")
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.type, .stateChange)
        XCTAssertNil(retrieved.first?.toolName)
        XCTAssertEqual(retrieved.first?.summary, "Agent detected: working")
    }

    // MARK: - Test 10: Publisher Emits on Add

    func testPublisherEmitsOnAddEvent() {
        var emittedValues: [[TimelineEvent]] = []
        let expectation = expectation(description: "Publisher emits")
        expectation.expectedFulfillmentCount = 2

        sut.eventsPublisher(for: "sess-pub")
            .sink { events in
                emittedValues.append(events)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.addEvent(makeEvent(sessionId: "sess-pub", summary: "First"))
        sut.addEvent(makeEvent(sessionId: "sess-pub", summary: "Second"))

        waitForExpectations(timeout: 2.0)

        XCTAssertEqual(emittedValues.count, 2)
        XCTAssertEqual(emittedValues[0].count, 1)
        XCTAssertEqual(emittedValues[1].count, 2)
    }

    // MARK: - Test 11: Thread Safety

    func testThreadSafetyAddFromMultipleQueues() {
        let store = AgentTimelineStoreImpl()
        let expectation = expectation(description: "All concurrent adds complete")
        let totalEvents = 100
        let dispatchGroup = DispatchGroup()

        for i in 0..<totalEvents {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                store.addEvent(self.makeEvent(
                    sessionId: "sess-concurrent",
                    summary: "Concurrent event \(i)"
                ))
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)

        // All 100 events should be stored (max is 1000, so no eviction)
        XCTAssertEqual(store.eventCount(for: "sess-concurrent"), totalEvents)
        XCTAssertEqual(store.events(for: "sess-concurrent").count, totalEvents)
    }

    // MARK: - Test 12: All Events Across Sessions

    func testAllEventsAcrossSessionsReturnsSortedMergedList() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 1500)

        sut.addEvent(makeEvent(sessionId: "sess-X", summary: "X", timestamp: date1))
        sut.addEvent(makeEvent(sessionId: "sess-Y", summary: "Y", timestamp: date2))
        sut.addEvent(makeEvent(sessionId: "sess-Z", summary: "Z", timestamp: date3))

        let all = sut.allEvents
        XCTAssertEqual(all.count, 3)
        // Sorted by timestamp: date1, date3, date2
        XCTAssertEqual(all[0].summary, "X")   // 1000
        XCTAssertEqual(all[1].summary, "Z")   // 1500
        XCTAssertEqual(all[2].summary, "Y")   // 2000
    }

    // MARK: - Test 13: Export JSON Delegates to Exporter

    func testExportJSONProducesValidJSON() {
        sut.addEvent(makeEvent(sessionId: "sess-json", summary: "JSON test"))

        let jsonData = sut.exportJSON(for: "sess-json")
        XCTAssertFalse(jsonData.isEmpty)

        // Should be parseable back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode([TimelineEvent].self, from: jsonData)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?.summary, "JSON test")
    }

    // MARK: - Test 14: Export Markdown Delegates to Exporter

    func testExportMarkdownProducesValidTable() {
        sut.addEvent(makeEvent(
            sessionId: "sess-md",
            summary: "Write: App.swift",
            toolName: "Write",
            filePath: "/Users/test/Sources/App.swift",
            durationMs: 120
        ))

        let markdown = sut.exportMarkdown(for: "sess-md")
        XCTAssertTrue(markdown.contains("## Agent Timeline"))
        XCTAssertTrue(markdown.contains("| Time | Action | File | Duration |"))
        XCTAssertTrue(markdown.contains("Write"))
        XCTAssertTrue(markdown.contains("App.swift"))
        XCTAssertTrue(markdown.contains("120ms"))
    }

    // MARK: - Helpers

    private func makeEvent(
        sessionId: String,
        summary: String,
        type: TimelineEventType = .toolUse,
        toolName: String? = nil,
        filePath: String? = nil,
        durationMs: Int? = nil,
        isError: Bool = false,
        timestamp: Date = Date()
    ) -> TimelineEvent {
        TimelineEvent(
            id: UUID(),
            timestamp: timestamp,
            type: type,
            sessionId: sessionId,
            toolName: toolName,
            filePath: filePath,
            summary: summary,
            durationMs: durationMs,
            isError: isError
        )
    }
}
