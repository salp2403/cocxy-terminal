// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CoreGraphics
import Testing
@testable import CocxyTerminal

@MainActor
struct TerminalDetectedContentOverlaySwiftTestingTests {
    @Test("single-row spans map to stable cell geometry")
    func singleRowSpanGeometry() throws {
        let rects = TerminalDetectedContentOverlayView.underlineRects(
            for: detected(startRow: 12, startColumn: 3, endRow: 12, endColumn: 7),
            viewport: TerminalDetectedContentViewport(
                visibleStartRow: 10,
                rowCount: 5,
                columnCount: 20,
                cellSize: CGSize(width: 8, height: 16),
                origin: CGPoint(x: 4, y: 2)
            )
        )

        let rect = try #require(rects.first)
        #expect(rects.count == 1)
        #expect(rect.minX == 28)
        #expect(abs(rect.minY - 48.4) < 0.001)
        #expect(rect.width == 40)
        #expect(abs(rect.height - 1.6) < 0.001)
    }

    @Test("wrapped spans are clipped to visible rows and columns")
    func wrappedSpanGeometryIsClipped() {
        let rects = TerminalDetectedContentOverlayView.underlineRects(
            for: detected(startRow: 9, startColumn: 6, endRow: 11, endColumn: 4),
            viewport: TerminalDetectedContentViewport(
                visibleStartRow: 10,
                rowCount: 2,
                columnCount: 10,
                cellSize: CGSize(width: 7, height: 15),
                origin: .zero
            )
        )

        #expect(rects == [
            CGRect(x: 0, y: 13.5, width: 70, height: 1.5),
            CGRect(x: 0, y: 28.5, width: 35, height: 1.5),
        ])
    }

    @Test("offscreen and overflowed viewports produce no geometry")
    func invalidViewportsProduceNoGeometry() {
        let content = detected(startRow: 1, startColumn: 0, endRow: 1, endColumn: 2)
        #expect(TerminalDetectedContentOverlayView.underlineRects(
            for: content,
            viewport: TerminalDetectedContentViewport(
                visibleStartRow: 10,
                rowCount: 2,
                columnCount: 10,
                cellSize: CGSize(width: 8, height: 16),
                origin: .zero
            )
        ).isEmpty)
        #expect(TerminalDetectedContentOverlayView.underlineRects(
            for: content,
            viewport: TerminalDetectedContentViewport(
                visibleStartRow: UInt32.max,
                rowCount: 2,
                columnCount: 10,
                cellSize: CGSize(width: 8, height: 16),
                origin: .zero
            )
        ).isEmpty)
    }

    private func detected(
        startRow: UInt32,
        startColumn: UInt16,
        endRow: UInt32,
        endColumn: UInt16
    ) -> TerminalDetectedContent {
        TerminalDetectedContent(
            kind: .url,
            text: "https://cocxy.dev",
            target: "https://cocxy.dev",
            startRow: startRow,
            startColumn: startColumn,
            endRow: endRow,
            endColumn: endColumn,
            line: nil,
            column: nil,
            isExplicitHyperlink: false
        )
    }
}
