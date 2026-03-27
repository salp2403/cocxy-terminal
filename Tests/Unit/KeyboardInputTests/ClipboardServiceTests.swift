// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClipboardServiceTests.swift - Tests for clipboard read/write abstraction.

import XCTest
@testable import CocxyTerminal

// MARK: - Clipboard Service Protocol Tests

/// Tests that the clipboard service protocol and implementation work correctly.
///
/// The clipboard service abstracts NSPasteboard access for testability.
/// Tests use a mock implementation to verify behavior without touching
/// the real system clipboard.
@MainActor
final class ClipboardServiceTests: XCTestCase {

    // MARK: - Mock Clipboard

    func testMockClipboardWriteAndRead() {
        let clipboard = MockClipboardService()
        clipboard.write("hello world")
        XCTAssertEqual(clipboard.read(), "hello world",
                       "Written text must be readable")
    }

    func testMockClipboardReadReturnsNilWhenEmpty() {
        let clipboard = MockClipboardService()
        XCTAssertNil(clipboard.read(), "Empty clipboard must return nil")
    }

    func testMockClipboardOverwritesPrevious() {
        let clipboard = MockClipboardService()
        clipboard.write("first")
        clipboard.write("second")
        XCTAssertEqual(clipboard.read(), "second",
                       "Writing must overwrite previous content")
    }

    func testMockClipboardClearRemovesContent() {
        let clipboard = MockClipboardService()
        clipboard.write("something")
        clipboard.clear()
        XCTAssertNil(clipboard.read(), "Clear must remove clipboard content")
    }

    // MARK: - System Clipboard Service

    func testSystemClipboardServiceConformsToProtocol() {
        let clipboard: ClipboardServiceProtocol = SystemClipboardService()
        XCTAssertNotNil(clipboard, "SystemClipboardService must conform to protocol")
    }
}
