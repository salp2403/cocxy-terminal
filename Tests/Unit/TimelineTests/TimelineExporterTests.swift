// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineExporterTests.swift - Tests for TimelineExporter.

import XCTest
@testable import CocxyTerminal

// MARK: - Timeline Exporter Tests

/// Tests for `TimelineExporter` covering:
///
/// 1. Export JSON -> valid JSON, parseable back to TimelineEvent array
/// 2. Export JSON -> contains all events with correct fields
/// 3. Export Markdown -> valid table format with header
/// 4. Export Markdown -> tools formatted correctly (tool name in Action column)
/// 5. Export Markdown -> errors marked with "x " prefix
/// 6. Export empty timeline -> empty output
/// 7. Export single event -> correct format
/// 8. Duration formatting: ms < 1000 -> "120ms", >= 1000 -> "3.4s"
/// 9. File path shows only last component
/// 10. Events without tool name use event type name
final class TimelineExporterTests: XCTestCase {

    // MARK: - Test 1: Export JSON Is Valid and Parseable

    func testExportJSONIsValidAndParseable() {
        let events = [
            makeEvent(summary: "Write: App.swift", toolName: "Write"),
            makeEvent(summary: "Read: README.md", toolName: "Read"),
        ]

        let jsonData = TimelineExporter.exportJSON(events: events)
        XCTAssertFalse(jsonData.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode([TimelineEvent].self, from: jsonData)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 2)
    }

    // MARK: - Test 2: Export JSON Contains All Fields

    func testExportJSONContainsAllEventFields() {
        let eventId = UUID()
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let event = TimelineEvent(
            id: eventId,
            timestamp: timestamp,
            type: .toolUse,
            sessionId: "sess-json",
            toolName: "Write",
            filePath: "/Users/test/App.swift",
            summary: "Write: App.swift",
            durationMs: 250,
            isError: false
        )

        let jsonData = TimelineExporter.exportJSON(events: [event])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode([TimelineEvent].self, from: jsonData)

        XCTAssertNotNil(decoded)
        let first = decoded?.first
        XCTAssertEqual(first?.id, eventId)
        XCTAssertEqual(first?.type, .toolUse)
        XCTAssertEqual(first?.sessionId, "sess-json")
        XCTAssertEqual(first?.toolName, "Write")
        XCTAssertEqual(first?.filePath, "/Users/test/App.swift")
        XCTAssertEqual(first?.summary, "Write: App.swift")
        XCTAssertEqual(first?.durationMs, 250)
        XCTAssertEqual(first?.isError, false)
    }

    // MARK: - Test 3: Export Markdown Has Valid Table Format

    func testExportMarkdownHasValidTableFormat() {
        let events = [
            makeEvent(summary: "Write: App.swift", toolName: "Write"),
        ]

        let markdown = TimelineExporter.exportMarkdown(events: events)

        XCTAssertTrue(markdown.contains("## Agent Timeline"))
        XCTAssertTrue(markdown.contains("| Time | Action | File | Duration |"))
        XCTAssertTrue(markdown.contains("|------|--------|------|----------|"))
    }

    // MARK: - Test 4: Markdown Tools Formatted Correctly

    func testMarkdownToolsFormattedCorrectly() {
        let events = [
            makeEvent(
                summary: "Write: App.swift",
                toolName: "Write",
                filePath: "/Users/test/Sources/App.swift",
                durationMs: 120
            ),
            makeEvent(
                summary: "Bash: npm test",
                toolName: "Bash",
                filePath: nil,
                durationMs: 3400
            ),
        ]

        let markdown = TimelineExporter.exportMarkdown(events: events)
        let lines = markdown.components(separatedBy: "\n")

        // Find data lines (after header)
        let dataLines = lines.filter { $0.hasPrefix("| ") && !$0.contains("Time") && !$0.contains("---") }
        XCTAssertEqual(dataLines.count, 2)

        // First line should contain Write and App.swift
        XCTAssertTrue(dataLines[0].contains("Write"))
        XCTAssertTrue(dataLines[0].contains("App.swift"))
        XCTAssertTrue(dataLines[0].contains("120ms"))

        // Second line should contain Bash and 3.4s
        XCTAssertTrue(dataLines[1].contains("Bash"))
        XCTAssertTrue(dataLines[1].contains("3.4s"))
    }

    // MARK: - Test 5: Markdown Errors Marked with x

    func testMarkdownErrorsMarkedWithCross() {
        let events = [
            makeEvent(
                summary: "Edit: config.toml failed",
                type: .toolFailure,
                toolName: "Edit",
                filePath: "/Users/test/config.toml",
                isError: true
            ),
        ]

        let markdown = TimelineExporter.exportMarkdown(events: events)

        // The action should be "x Edit"
        XCTAssertTrue(markdown.contains("x Edit"))
    }

    // MARK: - Test 6: Export Empty Timeline

    func testExportEmptyTimelineReturnsEmptyOutput() {
        let jsonData = TimelineExporter.exportJSON(events: [])
        XCTAssertFalse(jsonData.isEmpty) // Should be "[]"

        let jsonString = String(data: jsonData, encoding: .utf8)
        XCTAssertNotNil(jsonString)
        // Should parse as empty array
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode([TimelineEvent].self, from: jsonData)
        XCTAssertEqual(decoded?.count, 0)

        let markdown = TimelineExporter.exportMarkdown(events: [])
        XCTAssertEqual(markdown, "")
    }

    // MARK: - Test 7: Export Single Event Correct Format

    func testExportSingleEventCorrectFormat() {
        let event = makeEvent(
            summary: "Finished",
            type: .taskCompleted,
            toolName: nil,
            filePath: nil,
            durationMs: nil
        )

        let markdown = TimelineExporter.exportMarkdown(events: [event])
        let lines = markdown.components(separatedBy: "\n")

        // Should have: title + blank line + table header + separator + 1 data line = 5 lines
        XCTAssertEqual(lines.count, 5)

        let dataLine = lines[4]
        XCTAssertTrue(dataLine.contains("Task Completed"))
        XCTAssertTrue(dataLine.contains("--")) // no file and no duration
    }

    // MARK: - Test 8: Duration Formatting

    func testDurationFormattingMillisecondsAndSeconds() {
        // Less than 1000ms -> "120ms"
        XCTAssertEqual(TimelineExporter.formatDuration(120), "120ms")
        XCTAssertEqual(TimelineExporter.formatDuration(0), "0ms")
        XCTAssertEqual(TimelineExporter.formatDuration(999), "999ms")

        // 1000ms or more -> "X.Xs"
        XCTAssertEqual(TimelineExporter.formatDuration(1000), "1.0s")
        XCTAssertEqual(TimelineExporter.formatDuration(3400), "3.4s")
        XCTAssertEqual(TimelineExporter.formatDuration(15000), "15.0s")
        XCTAssertEqual(TimelineExporter.formatDuration(1500), "1.5s")

        // Nil -> "--"
        XCTAssertEqual(TimelineExporter.formatDuration(nil), "--")
    }

    // MARK: - Test 9: File Path Shows Only Last Component

    func testFilePathShowsOnlyLastComponent() {
        let event = makeEvent(
            summary: "Read: very-nested.swift",
            toolName: "Read",
            filePath: "/Users/test/project/deeply/nested/path/very-nested.swift"
        )

        let markdown = TimelineExporter.exportMarkdown(events: [event])
        XCTAssertTrue(markdown.contains("very-nested.swift"))
        // Should NOT contain the full path
        XCTAssertFalse(markdown.contains("/Users/test/project"))
    }

    // MARK: - Test 10: Events Without Tool Name Use Type Name

    func testEventsWithoutToolNameUseEventTypeName() {
        let event = makeEvent(
            summary: "Session started",
            type: .sessionStart,
            toolName: nil
        )

        let markdown = TimelineExporter.exportMarkdown(events: [event])
        XCTAssertTrue(markdown.contains("Session Start"))
    }

    // MARK: - Helpers

    private func makeEvent(
        summary: String,
        type: TimelineEventType = .toolUse,
        toolName: String? = "Write",
        filePath: String? = nil,
        durationMs: Int? = nil,
        isError: Bool = false
    ) -> TimelineEvent {
        TimelineEvent(
            id: UUID(),
            timestamp: Date(),
            type: type,
            sessionId: "test-session",
            toolName: toolName,
            filePath: filePath,
            summary: summary,
            durationMs: durationMs,
            isError: isError
        )
    }
}
