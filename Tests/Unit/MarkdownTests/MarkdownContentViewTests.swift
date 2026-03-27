// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownContentViewTests.swift - Tests for embeddable markdown viewer.

import XCTest
@testable import CocxyTerminal

@MainActor
final class MarkdownContentViewTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithNilPathSetsFilePathNil() {
        let view = MarkdownContentView(filePath: nil)
        XCTAssertNil(view.filePath)
    }

    func testInitWithValidPathSetsFilePath() {
        let url = createTempMarkdownFile(content: "# Hello")
        let view = MarkdownContentView(filePath: url)
        XCTAssertEqual(view.filePath, url)
        cleanup(url)
    }

    func testInitCreatesSubviews() {
        let view = MarkdownContentView(filePath: nil)
        // Should have header + scroll view = at least 2 subviews
        XCTAssertGreaterThanOrEqual(view.subviews.count, 2)
    }

    // MARK: - File Loading

    func testLoadFileUpdatesFilePath() {
        let view = MarkdownContentView()
        let url = createTempMarkdownFile(content: "# Test")
        view.loadFile(url)
        XCTAssertEqual(view.filePath, url)
        cleanup(url)
    }

    func testLoadFileWithInvalidPathDoesNotCrash() {
        let view = MarkdownContentView()
        let badURL = URL(fileURLWithPath: "/nonexistent/path/to/file.md")
        view.loadFile(badURL)
        XCTAssertEqual(view.filePath, badURL)
        // Should not crash, just show error text
    }

    func testLoadMultipleFilesUpdatesPath() {
        let view = MarkdownContentView()
        let url1 = createTempMarkdownFile(content: "# First")
        let url2 = createTempMarkdownFile(content: "# Second")
        view.loadFile(url1)
        XCTAssertEqual(view.filePath, url1)
        view.loadFile(url2)
        XCTAssertEqual(view.filePath, url2)
        cleanup(url1)
        cleanup(url2)
    }

    // MARK: - View Structure

    func testViewHasLayerBacking() {
        let view = MarkdownContentView()
        XCTAssertTrue(view.wantsLayer)
    }

    func testHeaderHeight() {
        let view = MarkdownContentView()
        // Header is constrained to 32pt height
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.layoutSubtreeIfNeeded()
        // First subview should be the header
        if let header = view.subviews.first {
            XCTAssertEqual(header.frame.height, 32, accuracy: 1.0)
        }
    }

    // MARK: - Helpers

    private func createTempMarkdownFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
