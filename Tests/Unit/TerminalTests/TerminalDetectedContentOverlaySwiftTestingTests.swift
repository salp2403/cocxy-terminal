// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CoreGraphics
import Testing
@testable import CocxyTerminal

@MainActor
struct TerminalDetectedContentOverlaySwiftTestingTests {
    @Test("hint labels follow a stable home-row order")
    func hintLabelsAreStable() throws {
        var session = try #require(TerminalDetectedContentHintSession(contents: [
            detected(startRow: 0, startColumn: 0, endRow: 0, endColumn: 2, target: "one"),
            detected(startRow: 1, startColumn: 0, endRow: 1, endColumn: 2, target: "two"),
            detected(startRow: 2, startColumn: 0, endRow: 2, endColumn: 2, target: "three"),
        ]))

        #expect(session.hints.map(\.label) == ["A", "S", "D"])
        let expected = session.hints[1].content
        #expect(session.consume(keyCode: 0, characters: "s") == .selected(expected))
    }

    @Test("large hint sets use unambiguous fixed-width prefixes")
    func largeHintSetsUsePrefixes() throws {
        let contents = (0..<27).map { index in
            detected(
                startRow: UInt32(index),
                startColumn: 0,
                endRow: UInt32(index),
                endColumn: 2,
                target: "target-\(index)"
            )
        }
        var session = try #require(TerminalDetectedContentHintSession(contents: contents))

        #expect(session.hints.first?.label == "AA")
        #expect(session.hints.last?.label == "SA")
        #expect(session.consume(keyCode: 1, characters: "s") == .updated)
        #expect(session.typedPrefix == "S")
        #expect(session.consume(keyCode: 0, characters: "a") == .selected(contents[26]))
    }

    @Test("Escape and delete update hint input without selecting content")
    func hintInputSupportsCancellationAndDelete() throws {
        let contents = (0..<27).map { index in
            detected(
                startRow: UInt32(index),
                startColumn: 0,
                endRow: UInt32(index),
                endColumn: 2,
                target: "target-\(index)"
            )
        }
        var session = try #require(TerminalDetectedContentHintSession(contents: contents))

        #expect(session.consume(keyCode: 0, characters: "a") == .updated)
        #expect(session.typedPrefix == "A")
        #expect(session.consume(keyCode: 51, characters: "\u{8}") == .updated)
        #expect(session.typedPrefix.isEmpty)
        #expect(session.consume(keyCode: 53, characters: "\u{1B}") == .cancelled)
    }

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

    @Test("nearby hint badges choose non-overlapping positions")
    func nearbyHintBadgesDoNotOverlap() throws {
        let session = try #require(TerminalDetectedContentHintSession(contents: [
            detected(startRow: 0, startColumn: 0, endRow: 0, endColumn: 3, target: "one"),
            detected(startRow: 0, startColumn: 1, endRow: 0, endColumn: 4, target: "two"),
        ]))
        let rects = TerminalDetectedContentOverlayView.hintBadgeRects(
            for: session.hints,
            viewport: TerminalDetectedContentViewport(
                visibleStartRow: 0,
                rowCount: 2,
                columnCount: 20,
                cellSize: CGSize(width: 8, height: 18),
                origin: .zero
            )
        )

        #expect(rects.count == 2)
        #expect(rects[0].intersects(rects[1]) == false)
    }

    @Test("dense hint badges remain visible and non-overlapping")
    func denseHintBadgesDoNotOverlap() throws {
        let contents = (0..<30).map { index in
            detected(
                startRow: 0,
                startColumn: 0,
                endRow: 0,
                endColumn: 3,
                target: "target-\(index)"
            )
        }
        let session = try #require(TerminalDetectedContentHintSession(contents: contents))
        let rects = TerminalDetectedContentOverlayView.hintBadgeRects(
            for: session.hints,
            viewport: TerminalDetectedContentViewport(
                visibleStartRow: 0,
                rowCount: 12,
                columnCount: 80,
                cellSize: CGSize(width: 8, height: 18),
                origin: .zero
            )
        )

        #expect(rects.count == contents.count)
        #expect(rects.allSatisfy { $0.isNull == false })
        for index in rects.indices {
            for otherIndex in rects.indices where otherIndex > index {
                #expect(rects[index].intersects(rects[otherIndex]) == false)
            }
        }
    }

    private func detected(
        startRow: UInt32,
        startColumn: UInt16,
        endRow: UInt32,
        endColumn: UInt16,
        target: String = "https://cocxy.dev"
    ) -> TerminalDetectedContent {
        TerminalDetectedContent(
            kind: .url,
            text: target,
            target: target,
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
