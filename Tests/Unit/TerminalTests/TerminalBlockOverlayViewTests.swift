// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import XCTest
@testable import CocxyTerminal

@MainActor
final class TerminalBlockOverlayViewTests: XCTestCase {

    func testLayoutPositionsVisibleBlocksByAbsoluteHistoryRows() {
        let blocks = [
            sampleBlock(id: 10, command: "swift test", startRow: 12, endRow: 16),
            sampleBlock(id: 11, command: "git status", startRow: 31, endRow: 33),
        ]

        let entries = TerminalBlockOverlayLayout.entries(
            blocks: blocks,
            visibleStartRow: 10,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4),
            width: 480
        )

        XCTAssertEqual(entries.map(\.block.id), [10, 11])
        XCTAssertEqual(entries[0].frame.origin.y, 26)
        XCTAssertEqual(entries[1].frame.origin.y, 235)
        XCTAssertEqual(entries[0].frame.origin.x, 16)
        XCTAssertEqual(entries[0].frame.width, 448)
        XCTAssertEqual(entries[0].railFrame.origin.y, 26)
        XCTAssertEqual(entries[0].railFrame.height, 55)
    }

    func testLayoutSkipsBlocksOutsideTheVisibleViewport() {
        let blocks = [
            sampleBlock(id: 1, command: "older", startRow: 1, endRow: 4),
            sampleBlock(id: 2, command: "visible", startRow: 15, endRow: 17),
            sampleBlock(id: 3, command: "future", startRow: 25, endRow: 27),
        ]

        let entries = TerminalBlockOverlayLayout.entries(
            blocks: blocks,
            visibleStartRow: 10,
            visibleRowCount: 10,
            cellHeight: 12,
            padding: CGPoint(x: 8, y: 4),
            width: 360
        )

        XCTAssertEqual(entries.map(\.block.id), [2])
    }

    func testOverlayPassesThroughBackgroundAndKeepsButtonsInteractive() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        overlay.update(
            blocks: [sampleBlock(id: 42, command: "echo hi", startRow: 3, endRow: 4)],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4)
        )
        overlay.layoutSubtreeIfNeeded()

        XCTAssertNil(
            overlay.hitTest(NSPoint(x: 20, y: 220)),
            "Empty overlay background must not block terminal selection or clicks."
        )

        let copyButton = overlay.descendantButton(withIdentifier: "command-block-copy-42")
        XCTAssertNotNil(copyButton)

        let buttonCenter = overlay.convert(
            NSPoint(x: copyButton!.bounds.midX, y: copyButton!.bounds.midY),
            from: copyButton
        )
        XCTAssertTrue(
            overlay.hitTest(buttonCenter) === copyButton,
            "Action buttons must remain clickable even though the overlay background is pass-through."
        )
    }

    func testCopyAndRerunButtonsSendTheSelectedBlock() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        var copied: [UInt64] = []
        var rerun: [UInt64] = []
        overlay.onCopyBlockOutput = { copied.append($0.id) }
        overlay.onRerunBlock = { rerun.append($0.id) }

        overlay.update(
            blocks: [sampleBlock(id: 7, command: "pwd", startRow: 3, endRow: 4)],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4)
        )
        overlay.layoutSubtreeIfNeeded()

        overlay.descendantButton(withIdentifier: "command-block-copy-7")?.performClick(nil)
        overlay.descendantButton(withIdentifier: "command-block-rerun-7")?.performClick(nil)

        XCTAssertEqual(copied, [7])
        XCTAssertEqual(rerun, [7])
    }

    private func sampleBlock(
        id: UInt64,
        command: String,
        startRow: UInt32,
        endRow: UInt32
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            command: command,
            output: "output for \(command)",
            exitCode: 0,
            pwd: "/tmp/project",
            startTimeNs: 100,
            endTimeNs: 200,
            durationNs: 100,
            startRow: startRow,
            endRow: endRow,
            streamID: 1,
            blockType: 3
        )
    }
}

private extension NSView {
    func descendantButton(withIdentifier identifier: String) -> NSButton? {
        if let button = self as? NSButton,
           button.accessibilityIdentifier() == identifier {
            return button
        }
        for subview in subviews {
            if let found = subview.descendantButton(withIdentifier: identifier) {
                return found
            }
        }
        return nil
    }
}
