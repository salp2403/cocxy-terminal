// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxHighlightQueryExecutor.swift - Converts highlight query captures into syntax tokens.

import Foundation

struct SyntaxQueryCapture: Equatable, Hashable {
    var captureName: String
    var range: SyntaxPointRange

    init(captureName: String, range: SyntaxPointRange) {
        self.captureName = captureName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.range = range
    }
}

struct SyntaxHighlightQueryExecutor {
    typealias CollectCaptures = (SyntaxTree, SyntaxHighlightQuerySource, EditorBuffer) throws -> [SyntaxQueryCapture]

    private let collectCaptures: CollectCaptures

    init(collectCaptures: @escaping CollectCaptures = { _, _, _ in [] }) {
        self.collectCaptures = collectCaptures
    }

    func tokens(
        for tree: SyntaxTree,
        querySource: SyntaxHighlightQuerySource,
        buffer: EditorBuffer
    ) throws -> [SyntaxToken] {
        let captures = try collectCaptures(tree, querySource, buffer)
        guard !captures.isEmpty else { return [] }

        let maximumCapturedLine = captures.reduce(0) { maximumLine, capture in
            max(maximumLine, capture.range.start.line, capture.range.end.line)
        }
        let lineIndex = SyntaxTextLineIndex(buffer: buffer, throughLine: maximumCapturedLine)
        return captures.compactMap { capture -> SyntaxToken? in
            guard let role = SyntaxCaptureMapper.role(for: capture.captureName) else {
                return nil
            }

            guard let range = lineIndex.editorRange(for: capture.range) else {
                return nil
            }
            guard range.length > 0 else {
                return nil
            }

            return SyntaxToken(role: role, range: range)
        }
    }
}

private struct SyntaxTextLineIndex {
    private struct Line {
        var start: Int
        var contentEnd: Int
    }

    private let utf16Length: Int
    private let lines: [Line]

    init(buffer: EditorBuffer, throughLine maximumLine: Int) {
        self.utf16Length = buffer.utf16Length

        let nsText = buffer.text as NSString
        let starts = Self.lineStartOffsets(in: nsText, throughLine: maximumLine)
        let lineCount = min(starts.count, max(0, maximumLine) + 1)
        self.lines = (0..<lineCount).map { index in
            let start = starts[index]
            let nextStart = index + 1 < starts.count ? starts[index + 1] : nsText.length
            var contentEnd = nextStart
            while contentEnd > start {
                let character = nsText.character(at: contentEnd - 1)
                if character == 10 || character == 13 {
                    contentEnd -= 1
                } else {
                    break
                }
            }
            return Line(start: start, contentEnd: contentEnd)
        }
    }

    private static func lineStartOffsets(in nsText: NSString, throughLine maximumLine: Int) -> [Int] {
        var offsets = [0]
        guard nsText.length > 0 else { return offsets }

        let requiredStartCount = max(0, maximumLine) + 2
        for index in 0..<nsText.length where nsText.character(at: index) == 10 {
            offsets.append(index + 1)
            if offsets.count >= requiredStartCount {
                break
            }
        }
        return offsets
    }

    func editorRange(for pointRange: SyntaxPointRange) -> EditorTextRange? {
        guard let startOffset = offset(for: pointRange.start),
              let endOffset = offset(for: pointRange.end) else {
            return nil
        }

        return EditorTextRange(
            location: min(startOffset, endOffset),
            length: abs(endOffset - startOffset)
        )
        .clamped(to: utf16Length)
    }

    private func offset(for point: SyntaxPoint) -> Int? {
        guard point.line < lines.count else {
            return nil
        }
        let line = lines[point.line]
        let maximumColumn = max(0, line.contentEnd - line.start)
        guard point.column <= maximumColumn else {
            return nil
        }
        return min(line.start + point.column, line.contentEnd)
    }
}
