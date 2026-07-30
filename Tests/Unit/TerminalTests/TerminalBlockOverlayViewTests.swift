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
        XCTAssertEqual(entries[0].headerFrame?.origin.y, 26)
        XCTAssertEqual(entries[1].headerFrame?.origin.y, 235)
        XCTAssertEqual(entries[0].headerFrame?.origin.x, 204)
        XCTAssertEqual(entries[0].headerFrame?.width, 260)
        XCTAssertEqual(entries[0].headerFrame?.height, 16)
        XCTAssertEqual(entries[0].railFrame.origin.y, 26)
        XCTAssertEqual(entries[0].railFrame.height, 55)
    }

    func testLayoutDrawsOnlyRailWhenBlockBeginsAboveViewport() throws {
        let entries = TerminalBlockOverlayLayout.entries(
            blocks: [sampleBlock(id: 4, command: "long output", startRow: 4, endRow: 14)],
            visibleStartRow: 10,
            visibleRowCount: 10,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4),
            width: 480
        )

        let entry = try XCTUnwrap(entries.first)
        XCTAssertNil(entry.headerFrame)
        XCTAssertEqual(entry.railFrame.origin.y, 4)
        XCTAssertEqual(entry.railFrame.height, 90)
    }

    func testLayoutUsesCellBoundedHeaderHeightAndRightAlignedChip() throws {
        let entries = TerminalBlockOverlayLayout.entries(
            blocks: [sampleBlock(id: 5, command: "echo", startRow: 1, endRow: 1)],
            visibleStartRow: 0,
            visibleRowCount: 10,
            cellHeight: 30,
            padding: CGPoint(x: 8, y: 4),
            width: 600
        )

        let frame = try XCTUnwrap(entries.first?.headerFrame)
        XCTAssertEqual(frame.height, 22)
        XCTAssertEqual(frame.width, 260)
        XCTAssertEqual(frame.maxX, 584)
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

    func testLayoutSkipsBlocksWithoutLiveRowMapping() {
        let block = TerminalCommandBlock(
            id: 7,
            command: "restored",
            output: "persisted output",
            exitCode: 0,
            pwd: "/tmp/project",
            startTimeNs: 100,
            endTimeNs: 200,
            durationNs: 100,
            startRow: 3,
            endRow: 4,
            streamID: 1,
            blockType: 3
        )

        let entries = TerminalBlockOverlayLayout.entries(
            blocks: [block],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4),
            width: 480
        )

        XCTAssertTrue(entries.isEmpty)
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
        XCTAssertTrue(copyButton?.isHidden == true)

        let buttonCenter = overlay.convert(
            NSPoint(x: copyButton!.bounds.midX, y: copyButton!.bounds.midY),
            from: copyButton
        )
        XCTAssertNil(overlay.hitTest(buttonCenter))

        overlay.descendantHeader(withIdentifier: "command-block-header-42")?.setHovered(true)
        XCTAssertFalse(copyButton?.isHidden == true)
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

        overlay.descendantHeader(withIdentifier: "command-block-header-7")?.setHovered(true)
        overlay.descendantButton(withIdentifier: "command-block-copy-7")?.performClick(nil)
        overlay.descendantButton(withIdentifier: "command-block-rerun-7")?.performClick(nil)

        XCTAssertEqual(copied, [7])
        XCTAssertEqual(rerun, [7])
    }

    func testShareAndBookmarkButtonsSendTheSelectedBlock() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        var shared: [UInt64] = []
        var bookmarked: [UInt64] = []
        overlay.onShareBlock = { block, sourceView in
            shared.append(block.id)
            XCTAssertTrue(sourceView is NSButton)
        }
        overlay.onToggleBookmark = { bookmarked.append($0.id) }

        overlay.update(
            blocks: [sampleBlock(id: 8, command: "git log", startRow: 3, endRow: 4)],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4)
        )
        overlay.layoutSubtreeIfNeeded()

        overlay.descendantHeader(withIdentifier: "command-block-header-8")?.setHovered(true)
        overlay.descendantButton(withIdentifier: "command-block-share-8")?.performClick(nil)
        overlay.descendantButton(withIdentifier: "command-block-bookmark-8")?.performClick(nil)

        XCTAssertEqual(shared, [8])
        XCTAssertEqual(bookmarked, [8])
    }

    func testSelectingMultipleBlocksCopiesTheSelectedBlocks() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        var singleCopied: [UInt64] = []
        var multiCopied: [[UInt64]] = []
        overlay.onCopyBlockOutput = { singleCopied.append($0.id) }
        overlay.onCopySelectedBlockOutputs = { multiCopied.append($0.map(\.id)) }

        overlay.update(
            blocks: [
                sampleBlock(id: 10, command: "pwd", startRow: 3, endRow: 4),
                sampleBlock(id: 11, command: "whoami", startRow: 6, endRow: 7)
            ],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4)
        )
        overlay.layoutSubtreeIfNeeded()

        overlay.descendantHeader(withIdentifier: "command-block-header-10")?.setHovered(true)
        overlay.descendantButton(withIdentifier: "command-block-select-10")?.performClick(nil)
        overlay.descendantHeader(withIdentifier: "command-block-header-11")?.setHovered(true)
        overlay.descendantButton(withIdentifier: "command-block-select-11")?.performClick(nil)
        overlay.descendantButton(withIdentifier: "command-block-copy-10")?.performClick(nil)

        XCTAssertEqual(singleCopied, [])
        XCTAssertEqual(multiCopied, [[10, 11]])
    }

    func testBookmarkedBlocksUseFilledBookmarkIcon() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        overlay.update(
            blocks: [sampleBlock(id: 9, command: "make", startRow: 3, endRow: 4).withBookmark(true)],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4)
        )
        overlay.layoutSubtreeIfNeeded()

        let bookmarkButton = overlay.descendantButton(withIdentifier: "command-block-bookmark-9")
        XCTAssertTrue(bookmarkButton?.isHidden == true)
        overlay.descendantHeader(withIdentifier: "command-block-header-9")?.setHovered(true)
        XCTAssertEqual(bookmarkButton?.toolTip, "Remove block bookmark")
        XCTAssertNotNil(bookmarkButton?.image)
    }

    func testActionButtonLabelsFollowConfiguredLanguage() throws {
        let overlay = TerminalBlockOverlayView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 260),
            localizer: AppLocalizer(
                languagePreference: .spanish,
                bundle: try XCTUnwrap(localizationBundle())
            )
        )
        overlay.update(
            blocks: [sampleBlock(id: 12, command: "make test", startRow: 3, endRow: 4)],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 11,
            padding: CGPoint(x: 8, y: 4)
        )
        overlay.layoutSubtreeIfNeeded()

        overlay.descendantHeader(withIdentifier: "command-block-header-12")?.setHovered(true)

        XCTAssertEqual(
            overlay.descendantButton(withIdentifier: "command-block-share-12")?.accessibilityLabel(),
            "Compartir bloque de comando"
        )
        XCTAssertEqual(
            overlay.descendantButton(withIdentifier: "command-block-copy-12")?.toolTip,
            "Copiar salida del bloque"
        )
        XCTAssertEqual(
            overlay.descendantButton(withIdentifier: "command-block-rerun-12")?.accessibilityLabel(),
            "Reejecutar bloque de comando"
        )
    }

    func testHoverOnlyIsDefaultAndCanBeDisabled() throws {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        let block = sampleBlock(id: 20, command: "echo hi", startRow: 3, endRow: 4)
        overlay.update(
            blocks: [block],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4)
        )

        let defaultHeader = try XCTUnwrap(
            overlay.descendantHeader(withIdentifier: "command-block-header-20")
        )
        let defaultDismiss = try XCTUnwrap(
            overlay.descendantButton(withIdentifier: "command-block-dismiss-20")
        )
        XCTAssertEqual(defaultHeader.alphaValue, 0.22, accuracy: 0.001)
        XCTAssertTrue(defaultDismiss.isHidden)

        defaultHeader.setHovered(true)
        XCTAssertEqual(defaultHeader.alphaValue, 1, accuracy: 0.001)
        XCTAssertFalse(defaultDismiss.isHidden)

        overlay.update(
            blocks: [block],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4),
            showOnlyOnHover: false
        )
        let persistentHeader = try XCTUnwrap(
            overlay.descendantHeader(withIdentifier: "command-block-header-20")
        )
        XCTAssertEqual(persistentHeader.alphaValue, 1, accuracy: 0.001)
        XCTAssertFalse(
            try XCTUnwrap(overlay.descendantButton(withIdentifier: "command-block-dismiss-20")).isHidden
        )
    }

    func testDismissalSurvivesUpdateAndAlternateScreenRoundTrip() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        let block = sampleBlock(id: 21, command: "pwd", startRow: 3, endRow: 4)
        var dismissed: [UInt64] = []
        overlay.onDismissBlock = { dismissed.append($0.id) }

        func update() {
            overlay.update(
                blocks: [block],
                visibleStartRow: 0,
                visibleRowCount: 24,
                cellHeight: 18,
                padding: CGPoint(x: 8, y: 4)
            )
        }

        update()
        overlay.descendantHeader(withIdentifier: "command-block-header-21")?.setHovered(true)
        overlay.descendantButton(withIdentifier: "command-block-dismiss-21")?.performClick(nil)
        XCTAssertEqual(dismissed, [21])
        XCTAssertEqual(overlay.dismissedBlockIDs, Set([21]))
        XCTAssertNil(overlay.descendantHeader(withIdentifier: "command-block-header-21"))

        update()
        XCTAssertNil(overlay.descendantHeader(withIdentifier: "command-block-header-21"))
        overlay.clear()
        update()
        XCTAssertNil(overlay.descendantHeader(withIdentifier: "command-block-header-21"))

        overlay.resetForSurfaceTeardown()
        update()
        XCTAssertNotNil(overlay.descendantHeader(withIdentifier: "command-block-header-21"))
    }

    func testDismissAllVisibleLeavesOffscreenBlocksAvailable() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        overlay.update(
            blocks: [
                sampleBlock(id: 30, command: "visible", startRow: 3, endRow: 4),
                sampleBlock(id: 31, command: "later", startRow: 30, endRow: 31),
            ],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4)
        )

        XCTAssertEqual(overlay.dismissAllVisible(), 1)
        XCTAssertEqual(overlay.dismissedBlockIDs, Set([30]))
        XCTAssertEqual(overlay.dismissAllVisible(), 0)

        overlay.update(
            blocks: [
                sampleBlock(id: 30, command: "visible", startRow: 3, endRow: 4),
                sampleBlock(id: 31, command: "later", startRow: 30, endRow: 31),
            ],
            visibleStartRow: 24,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4)
        )
        XCTAssertNotNil(overlay.descendantHeader(withIdentifier: "command-block-header-31"))
    }

    func testIdenticalUpdateDoesNotRebuildRows() {
        let overlay = TerminalBlockOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        let block = sampleBlock(id: 40, command: "echo", startRow: 3, endRow: 4)

        overlay.update(
            blocks: [block],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4)
        )
        let firstCount = overlay.rowRebuildCount
        overlay.update(
            blocks: [block],
            visibleStartRow: 0,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4)
        )
        XCTAssertEqual(overlay.rowRebuildCount, firstCount)

        overlay.update(
            blocks: [block],
            visibleStartRow: 1,
            visibleRowCount: 24,
            cellHeight: 18,
            padding: CGPoint(x: 8, y: 4)
        )
        XCTAssertEqual(overlay.rowRebuildCount, firstCount + 1)
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
            visibleStartRow: startRow,
            visibleEndRow: endRow,
            streamID: 1,
            blockType: 3
        )
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
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

    func descendantHeader(withIdentifier identifier: String) -> TerminalBlockHeaderView? {
        if let header = self as? TerminalBlockHeaderView,
           header.accessibilityIdentifier() == identifier {
            return header
        }
        for subview in subviews {
            if let found = subview.descendantHeader(withIdentifier: identifier) {
                return found
            }
        }
        return nil
    }
}
