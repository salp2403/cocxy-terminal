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

struct TerminalDetectedContentHint: Equatable, Sendable {
    let label: String
    let content: TerminalDetectedContent
}

enum TerminalDetectedContentHintInputResult: Equatable, Sendable {
    case updated
    case cancelled
    case selected(TerminalDetectedContent)
}

struct TerminalDetectedContentHintSession: Equatable, Sendable {
    private static let labelAlphabet = Array("asdfghjklqwertyuiopzxcvbnm")

    private(set) var hints: [TerminalDetectedContentHint]
    private(set) var typedPrefix = ""

    init?(contents: [TerminalDetectedContent]) {
        var uniqueContents: [TerminalDetectedContent] = []
        uniqueContents.reserveCapacity(contents.count)
        for content in contents where content.target.isEmpty == false {
            if uniqueContents.contains(content) == false {
                uniqueContents.append(content)
            }
        }
        guard uniqueContents.isEmpty == false else { return nil }

        let labelLength = Self.labelLength(for: uniqueContents.count)
        hints = uniqueContents.enumerated().map { index, content in
            TerminalDetectedContentHint(
                label: Self.label(for: index, length: labelLength),
                content: content
            )
        }
    }

    mutating func consume(
        keyCode: UInt16,
        characters: String?
    ) -> TerminalDetectedContentHintInputResult {
        if keyCode == 53 {
            return .cancelled
        }
        if keyCode == 51 || keyCode == 117 {
            if typedPrefix.isEmpty == false {
                typedPrefix.removeLast()
            }
            return .updated
        }

        guard let characters,
              characters.count == 1 else {
            return .updated
        }
        let character = characters.uppercased()
        guard character.count == 1,
              Self.labelAlphabet.contains(where: {
                  String($0).uppercased() == character
              }) else {
            return .updated
        }

        typedPrefix.append(character)
        let candidates = hints.filter { $0.label.hasPrefix(typedPrefix) }
        guard candidates.isEmpty == false else {
            typedPrefix = ""
            return .updated
        }
        if let selected = candidates.first(where: { $0.label == typedPrefix }) {
            return .selected(selected.content)
        }
        return .updated
    }

    private static func labelLength(for count: Int) -> Int {
        let base = labelAlphabet.count
        var length = 1
        var capacity = base
        while capacity < count {
            let (nextCapacity, overflowed) = capacity.multipliedReportingOverflow(by: base)
            guard overflowed == false else { return length + 1 }
            capacity = nextCapacity
            length += 1
        }
        return length
    }

    private static func label(for index: Int, length: Int) -> String {
        let base = labelAlphabet.count
        var value = index
        var characters = [Character](repeating: labelAlphabet[0], count: length)
        for position in stride(from: length - 1, through: 0, by: -1) {
            characters[position] = labelAlphabet[value % base]
            value /= base
        }
        return String(characters).uppercased()
    }
}

@MainActor
final class TerminalDetectedContentOverlayView: NSView {
    private(set) var hoveredContent: TerminalDetectedContent?
    private(set) var viewport: TerminalDetectedContentViewport?
    private(set) var hints: [TerminalDetectedContentHint] = []
    private(set) var hintPrefix = ""

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
        hints = []
        hintPrefix = ""
        needsDisplay = true
    }

    func showHints(
        _ hints: [TerminalDetectedContentHint],
        matching prefix: String,
        viewport: TerminalDetectedContentViewport
    ) {
        hoveredContent = nil
        self.viewport = viewport
        self.hints = hints
        hintPrefix = prefix
        needsDisplay = true
    }

    func clearHover() {
        guard hoveredContent != nil else { return }
        hoveredContent = nil
        if hints.isEmpty {
            viewport = nil
        }
        needsDisplay = true
    }

    func clearHints() {
        guard hints.isEmpty == false || hintPrefix.isEmpty == false else { return }
        hints = []
        hintPrefix = ""
        if hoveredContent == nil {
            viewport = nil
        }
        needsDisplay = true
    }

    func clear() {
        guard hoveredContent != nil || viewport != nil || hints.isEmpty == false else { return }
        hoveredContent = nil
        viewport = nil
        hints = []
        hintPrefix = ""
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let viewport else { return }

        if hints.isEmpty == false {
            drawHints(in: viewport)
            return
        }
        guard let hoveredContent else { return }

        NSColor.controlAccentColor.setFill()
        for rect in Self.underlineRects(for: hoveredContent, viewport: viewport) {
            rect.fill()
        }
    }

    private func drawHints(in viewport: TerminalDetectedContentViewport) {
        NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
        for hint in hints {
            for rect in Self.underlineRects(for: hint.content, viewport: viewport) {
                rect.fill()
            }
        }

        let badgeRects = Self.hintBadgeRects(for: hints, viewport: viewport)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

        for (hint, rect) in zip(hints, badgeRects) {
            guard rect.isNull == false else { continue }
            let matchesPrefix = hintPrefix.isEmpty || hint.label.hasPrefix(hintPrefix)
            let fillColor = matchesPrefix
                ? NSColor.controlAccentColor
                : NSColor.windowBackgroundColor.withAlphaComponent(0.9)
            let strokeColor = matchesPrefix
                ? NSColor.controlAccentColor
                : NSColor.separatorColor
            let textColor = matchesPrefix
                ? NSColor.selectedControlTextColor
                : NSColor.secondaryLabelColor
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            fillColor.setFill()
            path.fill()
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            hint.label.draw(
                in: rect.insetBy(dx: 4, dy: 2),
                withAttributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph,
                ]
            )
        }
    }

    static func hintBadgeRects(
        for hints: [TerminalDetectedContentHint],
        viewport: TerminalDetectedContentViewport
    ) -> [CGRect] {
        guard viewport.rowCount > 0,
              viewport.columnCount > 0,
              viewport.cellSize.width > 0,
              viewport.cellSize.height > 0 else {
            return []
        }
        let viewportRect = CGRect(
            x: viewport.origin.x,
            y: viewport.origin.y,
            width: CGFloat(viewport.columnCount) * viewport.cellSize.width,
            height: CGFloat(viewport.rowCount) * viewport.cellSize.height
        )
        var placed: [CGRect] = []
        placed.reserveCapacity(hints.count)

        for hint in hints {
            guard let anchor = underlineRects(for: hint.content, viewport: viewport).first else {
                placed.append(.null)
                continue
            }
            let badgeSize = CGSize(
                width: max(18, CGFloat(hint.label.count * 8 + 10)),
                height: min(18, viewport.cellSize.height)
            )
            let preferred = CGPoint(
                x: anchor.minX,
                y: anchor.maxY - viewport.cellSize.height
                    + max(0, (viewport.cellSize.height - badgeSize.height) / 2)
            )
            let verticalStep = badgeSize.height + 2
            let offsets: [CGPoint] = [
                .zero,
                CGPoint(x: badgeSize.width + 2, y: 0),
                CGPoint(x: -badgeSize.width - 2, y: 0),
                CGPoint(x: 0, y: verticalStep),
                CGPoint(x: 0, y: -verticalStep),
            ]
            let candidates = offsets.map { offset in
                clampedBadgeRect(
                    origin: CGPoint(x: preferred.x + offset.x, y: preferred.y + offset.y),
                    size: badgeSize,
                    viewportRect: viewportRect
                )
            }
            let localCandidate = candidates.first { candidate in
                placed.allSatisfy { existing in
                    existing.isNull || existing.insetBy(dx: -1, dy: -1).intersects(candidate) == false
                }
            }
            let selected = localCandidate ?? nearestAvailableBadgeRect(
                to: preferred,
                size: badgeSize,
                viewportRect: viewportRect,
                avoiding: placed
            )
            placed.append(selected)
        }
        return placed
    }

    private static func nearestAvailableBadgeRect(
        to preferredOrigin: CGPoint,
        size: CGSize,
        viewportRect: CGRect,
        avoiding placed: [CGRect]
    ) -> CGRect {
        let horizontalStep = size.width + 2
        let verticalStep = size.height + 2
        let availableWidth = max(0, viewportRect.width - size.width)
        let availableHeight = max(0, viewportRect.height - size.height)
        let columnCount = max(1, Int(floor(availableWidth / horizontalStep)) + 1)
        let rowCount = max(1, Int(floor(availableHeight / verticalStep)) + 1)
        let candidates = (0..<rowCount).flatMap { row in
            (0..<columnCount).map { column in
                CGRect(
                    x: viewportRect.minX + CGFloat(column) * horizontalStep,
                    y: viewportRect.minY + CGFloat(row) * verticalStep,
                    width: min(size.width, viewportRect.width),
                    height: min(size.height, viewportRect.height)
                )
            }
        }.sorted { lhs, rhs in
            squaredDistance(from: lhs.origin, to: preferredOrigin)
                < squaredDistance(from: rhs.origin, to: preferredOrigin)
        }

        return candidates.first { candidate in
            placed.allSatisfy { existing in
                existing.isNull || existing.insetBy(dx: -1, dy: -1).intersects(candidate) == false
            }
        } ?? .null
    }

    private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func clampedBadgeRect(
        origin: CGPoint,
        size: CGSize,
        viewportRect: CGRect
    ) -> CGRect {
        CGRect(
            x: min(max(origin.x, viewportRect.minX), max(viewportRect.minX, viewportRect.maxX - size.width)),
            y: min(max(origin.y, viewportRect.minY), max(viewportRect.minY, viewportRect.maxY - size.height)),
            width: min(size.width, viewportRect.width),
            height: min(size.height, viewportRect.height)
        )
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
