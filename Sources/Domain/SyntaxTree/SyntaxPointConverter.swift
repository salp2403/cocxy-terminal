// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxPointConverter.swift - Converts parser byte columns into editor UTF-16 points.

import Foundation

struct SyntaxBytePoint: Equatable, Hashable {
    var line: Int
    var byteColumn: Int

    init(line: Int, byteColumn: Int) {
        self.line = max(0, line)
        self.byteColumn = max(0, byteColumn)
    }
}

struct SyntaxPointConverter {
    private struct Line {
        var text: String
    }

    private let lines: [Line]

    init(text: String) {
        let buffer = EditorBuffer(text: text)
        let starts = buffer.lineStartOffsets
        let nsText = text as NSString

        self.lines = starts.enumerated().map { index, start in
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
            let length = max(0, contentEnd - start)
            return Line(text: nsText.substring(with: NSRange(location: start, length: length)))
        }
    }

    func syntaxPoint(from bytePoint: SyntaxBytePoint) -> SyntaxPoint {
        guard !lines.isEmpty else {
            return SyntaxPoint(line: 0, column: 0)
        }

        let lineIndex = min(bytePoint.line, lines.count - 1)
        return SyntaxPoint(
            line: lineIndex,
            column: utf16Column(in: lines[lineIndex].text, byteColumn: bytePoint.byteColumn)
        )
    }

    private func utf16Column(in line: String, byteColumn: Int) -> Int {
        var utf8Count = 0
        var utf16Count = 0

        for scalar in line.unicodeScalars {
            let scalarUTF8Count = scalar.utf8.count
            if utf8Count + scalarUTF8Count > byteColumn {
                return utf16Count
            }
            utf8Count += scalarUTF8Count
            utf16Count += scalar.utf16.count
        }

        return utf16Count
    }
}
