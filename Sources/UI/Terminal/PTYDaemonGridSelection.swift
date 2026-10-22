// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonGridSelection.swift - Daemon frame selection geometry and text extraction.

import CocxyShared

struct PTYDaemonGridPosition: Equatable {
    let row: UInt16
    let column: UInt16

    func linearIndex(columnCount: UInt16) -> Int {
        Int(row) * max(1, Int(columnCount)) + Int(column)
    }
}

struct PTYDaemonGridSelection: Equatable {
    enum Mode: Equatable {
        case linear
        case rectangular
    }

    let anchor: PTYDaemonGridPosition
    let head: PTYDaemonGridPosition
    let mode: Mode

    init(
        anchor: PTYDaemonGridPosition,
        head: PTYDaemonGridPosition,
        mode: Mode = .linear
    ) {
        self.anchor = anchor
        self.head = head
        self.mode = mode
    }

    func contains(row: UInt16, column: UInt16, columnCount: UInt16) -> Bool {
        if mode == .rectangular {
            let rowRange = min(anchor.row, head.row)...max(anchor.row, head.row)
            let columnRange = min(anchor.column, head.column)...max(anchor.column, head.column)
            return rowRange.contains(row) && columnRange.contains(column)
        }
        let candidate = PTYDaemonGridPosition(row: row, column: column)
            .linearIndex(columnCount: columnCount)
        let anchorIndex = anchor.linearIndex(columnCount: columnCount)
        let headIndex = head.linearIndex(columnCount: columnCount)
        return (min(anchorIndex, headIndex)...max(anchorIndex, headIndex)).contains(candidate)
    }

    func text(in frame: PTYDaemonSurfaceFrame) -> String? {
        guard frame.columns > 0, frame.rows > 0 else { return nil }
        let columnCount = Int(frame.columns)
        let rowCount = Int(frame.rows)
        let maximumIndex = rowCount * columnCount - 1
        var glyphByIndex: [Int: UInt32] = [:]
        for cell in frame.cells {
            glyphByIndex[Int(cell.row) * columnCount + Int(cell.column)] = cell.glyph
        }

        let firstRow: Int
        let lastRow: Int
        let firstColumn: Int
        let lastColumn: Int
        if mode == .rectangular {
            firstRow = min(Int(anchor.row), Int(head.row))
            lastRow = min(max(Int(anchor.row), Int(head.row)), rowCount - 1)
            firstColumn = min(Int(anchor.column), Int(head.column))
            lastColumn = min(max(Int(anchor.column), Int(head.column)), columnCount - 1)
        } else {
            let anchorIndex = min(anchor.linearIndex(columnCount: frame.columns), maximumIndex)
            let headIndex = min(head.linearIndex(columnCount: frame.columns), maximumIndex)
            let lowerBound = min(anchorIndex, headIndex)
            let upperBound = max(anchorIndex, headIndex)
            firstRow = lowerBound / columnCount
            lastRow = upperBound / columnCount
            firstColumn = lowerBound % columnCount
            lastColumn = upperBound % columnCount
        }

        var lines: [String] = []
        for row in firstRow...lastRow {
            let rowStart = row * columnCount
            let startColumn = mode == .rectangular
                ? firstColumn
                : (row == firstRow ? firstColumn : 0)
            let endColumn = mode == .rectangular
                ? lastColumn
                : (row == lastRow ? lastColumn : columnCount - 1)
            var line = ""
            for index in (rowStart + startColumn)...(rowStart + endColumn) {
                if let glyph = glyphByIndex[index],
                   glyph != 0,
                   let scalar = UnicodeScalar(glyph) {
                    line.append(Character(scalar))
                } else {
                    line.append(" ")
                }
            }
            while line.last == " " {
                line.removeLast()
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func word(
        containing position: PTYDaemonGridPosition,
        in frame: PTYDaemonSurfaceFrame
    ) -> PTYDaemonGridSelection? {
        guard position.row < frame.rows, position.column < frame.columns else { return nil }
        let glyphs = glyphsByColumn(in: position.row, frame: frame)
        let selectedClass = characterClass(glyphs[Int(position.column)])

        var first = Int(position.column)
        while first > 0, characterClass(glyphs[first - 1]) == selectedClass {
            first -= 1
        }
        var last = Int(position.column)
        while last + 1 < glyphs.count, characterClass(glyphs[last + 1]) == selectedClass {
            last += 1
        }
        return PTYDaemonGridSelection(
            anchor: PTYDaemonGridPosition(row: position.row, column: UInt16(first)),
            head: PTYDaemonGridPosition(row: position.row, column: UInt16(last))
        )
    }

    static func logicalLine(
        containing position: PTYDaemonGridPosition,
        in frame: PTYDaemonSurfaceFrame
    ) -> PTYDaemonGridSelection? {
        guard frame.columns > 0, position.row < frame.rows else { return nil }
        let wrappedRows = Set(frame.wrappedRows.filter { $0 < frame.rows })
        var first = Int(position.row)
        while first > 0, wrappedRows.contains(UInt16(first - 1)) {
            first -= 1
        }
        var last = Int(position.row)
        while last + 1 < Int(frame.rows), wrappedRows.contains(UInt16(last)) {
            last += 1
        }
        return PTYDaemonGridSelection(
            anchor: PTYDaemonGridPosition(row: UInt16(first), column: 0),
            head: PTYDaemonGridPosition(row: UInt16(last), column: frame.columns - 1)
        )
    }

    private enum CharacterClass {
        case whitespace
        case word
        case punctuation
    }

    private static func characterClass(_ glyph: UInt32) -> CharacterClass {
        if glyph == 0 || glyph == 9 || glyph == 10 || glyph == 13 || glyph == 32 {
            return .whitespace
        }
        if (48...57).contains(glyph) ||
            (65...90).contains(glyph) ||
            (97...122).contains(glyph) ||
            glyph == 95 || glyph >= 0x80 {
            return .word
        }
        return .punctuation
    }

    private static func glyphsByColumn(
        in row: UInt16,
        frame: PTYDaemonSurfaceFrame
    ) -> [UInt32] {
        var glyphs = [UInt32](repeating: 0, count: Int(frame.columns))
        for cell in frame.cells where cell.row == row && cell.column < frame.columns {
            glyphs[Int(cell.column)] = cell.glyph
        }
        return glyphs
    }
}
