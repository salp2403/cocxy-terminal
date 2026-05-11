// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitDiffLayout.swift - Side-by-side row layout for parsed diff hunks.

import Foundation

enum SplitDiffSide: String, Sendable, Equatable {
    case left
    case right
}

struct SplitDiffLineCell: Identifiable, Equatable, Sendable {
    let side: SplitDiffSide
    let kind: DiffLineKind
    let content: String
    let lineNumber: Int?

    var id: String {
        "\(side.rawValue):\(lineNumber.map(String.init) ?? "-"):\(kind):\(content)"
    }

    init(line: DiffLine, side: SplitDiffSide) {
        self.side = side
        self.kind = line.kind
        self.content = line.content
        self.lineNumber = side == .left ? line.oldLineNumber : line.newLineNumber
    }
}

struct SplitDiffRow: Identifiable, Equatable, Sendable {
    let left: SplitDiffLineCell?
    let right: SplitDiffLineCell?

    var id: String {
        "\(left?.id ?? "left-empty")|\(right?.id ?? "right-empty")"
    }

    var isReplacement: Bool {
        left?.kind == .deletion && right?.kind == .addition
    }
}

enum SplitDiffLayout {
    static func rows(for hunk: DiffHunk) -> [SplitDiffRow] {
        rows(for: hunk.lines)
    }

    static func rows(for lines: [DiffLine]) -> [SplitDiffRow] {
        var rows: [SplitDiffRow] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            switch line.kind {
            case .context:
                rows.append(
                    SplitDiffRow(
                        left: SplitDiffLineCell(line: line, side: .left),
                        right: SplitDiffLineCell(line: line, side: .right)
                    )
                )
                index += 1

            case .deletion:
                let deletions = collect(.deletion, from: lines, startingAt: &index)
                let additions = collect(.addition, from: lines, startingAt: &index)
                let rowCount = max(deletions.count, additions.count)

                for offset in 0..<rowCount {
                    rows.append(
                        SplitDiffRow(
                            left: deletions[safe: offset].map { SplitDiffLineCell(line: $0, side: .left) },
                            right: additions[safe: offset].map { SplitDiffLineCell(line: $0, side: .right) }
                        )
                    )
                }

            case .addition:
                let additions = collect(.addition, from: lines, startingAt: &index)
                for addition in additions {
                    rows.append(
                        SplitDiffRow(
                            left: nil,
                            right: SplitDiffLineCell(line: addition, side: .right)
                        )
                    )
                }
            }
        }

        return rows
    }

    private static func collect(
        _ kind: DiffLineKind,
        from lines: [DiffLine],
        startingAt index: inout Int
    ) -> [DiffLine] {
        var collected: [DiffLine] = []
        while index < lines.count, lines[index].kind == kind {
            collected.append(lines[index])
            index += 1
        }
        return collected
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
