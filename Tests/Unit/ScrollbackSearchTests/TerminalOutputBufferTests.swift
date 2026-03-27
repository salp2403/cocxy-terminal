// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalOutputBufferTests.swift - Tests for the terminal output buffer.

import XCTest
@testable import CocxyTerminal

// MARK: - Terminal Output Buffer Tests

/// Tests for `TerminalOutputBuffer` covering:
///
/// - Initial state is empty.
/// - Appending data produces lines.
/// - Buffer respects maximum line count.
/// - Lines are accessible for search.
/// - Buffer can be cleared.
/// - Partial lines are handled correctly.
@MainActor
final class TerminalOutputBufferTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        XCTAssertTrue(buffer.lines.isEmpty,
                      "Buffer must start empty")
        XCTAssertEqual(buffer.lineCount, 0)
    }

    // MARK: - Append Data

    func testAppendDataProducesLines() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        buffer.append("Hello, world!\n".data(using: .utf8)!)

        XCTAssertEqual(buffer.lineCount, 1)
        XCTAssertEqual(buffer.lines.first, "Hello, world!")
    }

    func testAppendMultipleLinesAtOnce() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        buffer.append("line1\nline2\nline3\n".data(using: .utf8)!)

        XCTAssertEqual(buffer.lineCount, 3)
        XCTAssertEqual(buffer.lines[0], "line1")
        XCTAssertEqual(buffer.lines[1], "line2")
        XCTAssertEqual(buffer.lines[2], "line3")
    }

    func testAppendIncrementalData() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        buffer.append("part1".data(using: .utf8)!)
        buffer.append("part2\n".data(using: .utf8)!)

        XCTAssertEqual(buffer.lineCount, 1)
        XCTAssertEqual(buffer.lines.first, "part1part2")
    }

    // MARK: - Maximum Line Count

    func testBufferRespectsMaxLineCount() {
        let buffer = TerminalOutputBuffer(maxLineCount: 3)

        buffer.append("a\nb\nc\nd\ne\n".data(using: .utf8)!)

        XCTAssertEqual(buffer.lineCount, 3,
                       "Buffer must not exceed maxLineCount")
        // Should keep the most recent lines.
        XCTAssertEqual(buffer.lines[0], "c")
        XCTAssertEqual(buffer.lines[1], "d")
        XCTAssertEqual(buffer.lines[2], "e")
    }

    // MARK: - Clear

    func testClearRemovesAllLines() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)
        buffer.append("some data\n".data(using: .utf8)!)

        buffer.clear()

        XCTAssertTrue(buffer.lines.isEmpty)
        XCTAssertEqual(buffer.lineCount, 0)
    }

    // MARK: - Strip ANSI

    func testAnsiEscapeCodesAreStripped() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        // ESC[32m (green text) + "hello" + ESC[0m (reset)
        let ansiText = "\u{1B}[32mhello\u{1B}[0m\n"
        buffer.append(ansiText.data(using: .utf8)!)

        XCTAssertEqual(buffer.lines.first, "hello",
                       "ANSI escape codes must be stripped from buffer lines")
    }

    // MARK: - Carriage Return Handling

    func testCarriageReturnIsHandled() {
        let buffer = TerminalOutputBuffer(maxLineCount: 1000)

        buffer.append("hello\r\n".data(using: .utf8)!)

        XCTAssertEqual(buffer.lineCount, 1)
        XCTAssertEqual(buffer.lines.first, "hello")
    }
}
