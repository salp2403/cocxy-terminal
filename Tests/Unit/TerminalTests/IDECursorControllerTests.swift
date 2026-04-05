// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// IDECursorControllerTests.swift - Tests for IDE-like cursor positioning.

import XCTest
@testable import CocxyTerminal

@MainActor
final class IDECursorControllerTests: XCTestCase {

    // MARK: - Setup

    private func makeController() -> IDECursorController {
        let vm = TerminalViewModel()
        let view = CocxyCoreView(viewModel: vm)
        let controller = IDECursorController(
            hostView: view,
            fontSizeProvider: { [weak vm] in
                vm?.currentFontSize ?? 14.0
            },
            arrowKeySender: { _ in }
        )
        // Set known cell dimensions for predictable tests.
        controller.setCellDimensions(width: 8.0, height: 16.0)
        controller.leftPadding = 0
        controller.topPadding = 0
        return controller
    }

    // MARK: - Column Conversion

    func testColumnForXBasic() {
        let controller = makeController()
        XCTAssertEqual(controller.columnForX(0), 0)
        XCTAssertEqual(controller.columnForX(7.9), 0)
        XCTAssertEqual(controller.columnForX(8.0), 1)
        XCTAssertEqual(controller.columnForX(16.0), 2)
    }

    func testColumnForXWithPadding() {
        let controller = makeController()
        controller.leftPadding = 10
        XCTAssertEqual(controller.columnForX(10), 0)
        XCTAssertEqual(controller.columnForX(18), 1)
    }

    func testColumnForXNegativeClamps() {
        let controller = makeController()
        XCTAssertEqual(controller.columnForX(-5), 0)
    }

    func testRowForYBasic() {
        let controller = makeController()
        XCTAssertEqual(controller.rowForY(0), 0)
        XCTAssertEqual(controller.rowForY(15.9), 0)
        XCTAssertEqual(controller.rowForY(16.0), 1)
        XCTAssertEqual(controller.rowForY(32.0), 2)
    }

    // MARK: - Arrow Key Calculation

    func testArrowKeysWhenNotOnPromptLine() {
        let controller = makeController()
        controller.commandExecuted()

        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 40, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNil(result, "Should return nil when not on prompt line")
    }

    func testArrowKeysWhenDisabled() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 2)
        controller.isEnabled = false

        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 40, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNil(result)
    }

    func testArrowKeysClickOnSamePosition() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 2)
        // Cursor is at column 2. Click at column 2 (x = 16-23).
        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 18, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 0, "No movement needed")
    }

    func testArrowKeysClickRight() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 2)
        // Cursor at col 2, click at col 5 (x = 40-47).
        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 42, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 3)
        XCTAssertEqual(result?.first, .right)
    }

    func testArrowKeysClickLeft() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 2)
        controller.cursorMoved(toColumn: 10)
        // Cursor at col 10, click at col 5.
        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 42, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 5)
        XCTAssertEqual(result?.first, .left)
    }

    func testArrowKeysClickBeforePromptClampsToPrompt() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 4)
        // Cursor at col 4 (prompt end). Click at col 1 (before prompt).
        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 10, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 0,
                       "Should clamp to prompt column, same as current position")
    }

    func testArrowKeysClickOnDifferentRow() {
        let controller = makeController()
        controller.shellPromptDetected(row: 5, column: 2)
        // Click on row 3 (different from prompt row 5).
        let result = controller.arrowKeysForClick(
            at: CGPoint(x: 40, y: 48), // y=48 → row 3
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertNil(result, "Should not reposition when clicking different row")
    }

    // MARK: - Prompt Tracking

    func testShellPromptDetectedSetsState() {
        let controller = makeController()
        controller.shellPromptDetected(row: 3, column: 5)

        XCTAssertEqual(controller.promptRow, 3)
        XCTAssertEqual(controller.promptColumn, 5)
        XCTAssertEqual(controller.cursorColumn, 5)
        XCTAssertTrue(controller.isOnPromptLine)
    }

    func testCommandExecutedClearsPromptLine() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 2)
        XCTAssertTrue(controller.isOnPromptLine)

        controller.commandExecuted()
        XCTAssertFalse(controller.isOnPromptLine)
    }

    func testCursorMovedUpdatesColumn() {
        let controller = makeController()
        controller.shellPromptDetected(row: 0, column: 2)
        controller.cursorMoved(toColumn: 15)

        XCTAssertEqual(controller.cursorColumn, 15)
    }

    // MARK: - Reverse Conversion

    func testXForColumn() {
        let controller = makeController()
        // Column 0 center: 0 + 0.5 * 8 = 4.0
        XCTAssertEqual(controller.xForColumn(0), 4.0)
        // Column 5 center: 0 + 5.5 * 8 = 44.0
        XCTAssertEqual(controller.xForColumn(5), 44.0)
    }

    func testYForRow() {
        let controller = makeController()
        // Row 0 center: 0 + 0.5 * 16 = 8.0
        XCTAssertEqual(controller.yForRow(0), 8.0)
        // Row 3 center: 0 + 3.5 * 16 = 56.0
        XCTAssertEqual(controller.yForRow(3), 56.0)
    }
}

// MARK: - Text Selection Manager Tests

@MainActor
final class TextSelectionManagerTests: XCTestCase {

    func testURLDetectionHTTP() {
        // The URL detection is internal, test via the pattern matching.
        let text = "https://example.com/path?q=1"
        XCTAssertTrue(textContainsURL(text))
    }

    func testURLDetectionNoScheme() {
        let text = "example.com"
        XCTAssertFalse(textContainsURL(text))
    }

    func testFilePathDetection() {
        let text = "/usr/local/bin/zsh"
        XCTAssertTrue(textContainsFilePath(text))
    }

    func testFilePathDetectionTilde() {
        let text = "~/.config/cocxy/config.toml"
        XCTAssertTrue(textContainsFilePath(text))
    }

    func testDragStateTracking() {
        let manager = makeManager()
        XCTAssertFalse(manager.isDragging)

        manager.dragDidStart()
        XCTAssertTrue(manager.isDragging)

        manager.dragDidEnd()
        XCTAssertFalse(manager.isDragging)
    }

    // MARK: - Helpers

    private func makeManager() -> TextSelectionManager {
        TextSelectionManager(hostView: NSView())
    }

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>\"'\])}]+"#,
        options: .caseInsensitive
    )

    private static let filePathPattern = try! NSRegularExpression(
        pattern: #"(?:~|/)[/\w.\-@]+"#,
        options: []
    )

    private func textContainsURL(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return Self.urlPattern.firstMatch(in: text, range: range) != nil
    }

    private func textContainsFilePath(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return Self.filePathPattern.firstMatch(in: text, range: range) != nil
    }
}

// MARK: - Selection Highlight Layer Tests

final class SelectionHighlightLayerTests: XCTestCase {

    func testInitialState() {
        let layer = SelectionHighlightLayer()
        XCTAssertTrue(layer.highlightRects.isEmpty)
        XCTAssertFalse(layer.isOpaque)
    }

    func testClearHighlights() {
        let layer = SelectionHighlightLayer()
        layer.highlightRects = [CGRect(x: 0, y: 0, width: 100, height: 20)]
        XCTAssertEqual(layer.highlightRects.count, 1)

        layer.clearHighlights()
        XCTAssertTrue(layer.highlightRects.isEmpty)
    }

    func testMultipleHighlightRects() {
        let layer = SelectionHighlightLayer()
        layer.highlightRects = [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 0, y: 20, width: 80, height: 20),
            CGRect(x: 0, y: 40, width: 120, height: 20),
        ]
        XCTAssertEqual(layer.highlightRects.count, 3)
    }
}

// MARK: - IDE Cursor Indicator Layer Tests

final class IDECursorIndicatorLayerTests: XCTestCase {

    func testInitialState() {
        let layer = IDECursorIndicatorLayer()
        XCTAssertFalse(layer.isOpaque)
        XCTAssertEqual(layer.cursorX, 0)
    }

    func testCursorWidth() {
        XCTAssertEqual(IDECursorIndicatorLayer.cursorWidth, 2)
    }

    func testBlinkingStopSetsFullOpacity() {
        let layer = IDECursorIndicatorLayer()
        layer.startBlinking()
        layer.stopBlinking()
        XCTAssertEqual(layer.opacity, 1.0)
    }

    func testIsCursorVisibleSetsOpacity() {
        let layer = IDECursorIndicatorLayer()
        layer.isCursorVisible = false
        XCTAssertEqual(layer.opacity, 0.0)
        layer.isCursorVisible = true
        XCTAssertEqual(layer.opacity, 1.0)
    }
}
