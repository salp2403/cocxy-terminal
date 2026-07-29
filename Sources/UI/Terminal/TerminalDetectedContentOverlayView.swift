// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalDetectedContentOverlayView.swift - Non-interactive terminal content overlay.

import AppKit

struct TerminalDetectedContentViewport: Equatable {
    let visibleStartRow: UInt32
    let rowCount: UInt16
    let columnCount: UInt16
    let cellSize: CGSize
    let origin: CGPoint
}

@MainActor
final class TerminalDetectedContentOverlayView: NSView {
    private(set) var hoveredContent: TerminalDetectedContent?
    private(set) var viewport: TerminalDetectedContentViewport?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func showUnderline(
        for content: TerminalDetectedContent,
        viewport: TerminalDetectedContentViewport
    ) {
        hoveredContent = content
        self.viewport = viewport
        needsDisplay = true
    }

    func clear() {
        guard hoveredContent != nil || viewport != nil else { return }
        hoveredContent = nil
        viewport = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let hoveredContent, let viewport else { return }

        NSColor.controlAccentColor.setFill()
        for rect in Self.underlineRects(for: hoveredContent, viewport: viewport) {
            rect.fill()
        }
    }

    static func underlineRects(
        for content: TerminalDetectedContent,
        viewport: TerminalDetectedContentViewport
    ) -> [CGRect] {
        guard viewport.rowCount > 0,
              viewport.columnCount > 0,
              viewport.cellSize.width > 0,
              viewport.cellSize.height > 0 else {
            return []
        }
        let (visibleEndRow, overflowed) = viewport.visibleStartRow.addingReportingOverflow(
            UInt32(viewport.rowCount - 1)
        )
        guard overflowed == false,
              content.endRow >= viewport.visibleStartRow,
              content.startRow <= visibleEndRow else {
            return []
        }

        let firstRow = max(content.startRow, viewport.visibleStartRow)
        let lastRow = min(content.endRow, visibleEndRow)
        let lastColumn = viewport.columnCount - 1
        let thickness = max(1, min(2, viewport.cellSize.height * 0.1))
        var rects: [CGRect] = []
        rects.reserveCapacity(Int(lastRow - firstRow) + 1)

        for absoluteRow in firstRow...lastRow {
            let startColumn = absoluteRow == content.startRow ? content.startColumn : 0
            let endColumn = absoluteRow == content.endRow ? content.endColumn : lastColumn
            guard startColumn < viewport.columnCount else { continue }
            let clippedEndColumn = min(endColumn, lastColumn)
            guard clippedEndColumn >= startColumn else { continue }

            let visibleRow = absoluteRow - viewport.visibleStartRow
            rects.append(CGRect(
                x: viewport.origin.x + CGFloat(startColumn) * viewport.cellSize.width,
                y: viewport.origin.y
                    + CGFloat(visibleRow + 1) * viewport.cellSize.height
                    - thickness,
                width: CGFloat(clippedEndColumn - startColumn + 1) * viewport.cellSize.width,
                height: thickness
            ))
        }
        return rects
    }
}
