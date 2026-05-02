// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxInputEdit.swift - Tree-sitter incremental edit coordinates.

import Foundation

struct SyntaxInputEdit: Equatable {
    let startByte: Int
    let oldEndByte: Int
    let newEndByte: Int
    let startPoint: SyntaxBytePoint
    let oldEndPoint: SyntaxBytePoint
    let newEndPoint: SyntaxBytePoint

    init(
        startByte: Int,
        oldEndByte: Int,
        newEndByte: Int,
        startPoint: SyntaxBytePoint,
        oldEndPoint: SyntaxBytePoint,
        newEndPoint: SyntaxBytePoint
    ) {
        precondition(startByte >= 0 && oldEndByte >= startByte && newEndByte >= startByte)
        precondition(startByte <= Int(UInt32.max))
        precondition(oldEndByte <= Int(UInt32.max))
        precondition(newEndByte <= Int(UInt32.max))
        Self.preconditionValidPoint(startPoint)
        Self.preconditionValidPoint(oldEndPoint)
        Self.preconditionValidPoint(newEndPoint)

        self.startByte = startByte
        self.oldEndByte = oldEndByte
        self.newEndByte = newEndByte
        self.startPoint = startPoint
        self.oldEndPoint = oldEndPoint
        self.newEndPoint = newEndPoint
    }

    static func replacement(
        in oldText: String,
        range: EditorTextRange,
        replacementText: String
    ) -> SyntaxInputEdit? {
        let oldBuffer = EditorBuffer(text: oldText)
        let clampedRange = range.clamped(to: oldBuffer.utf16Length)
        let startOffset = clampedRange.location
        let oldEndOffset = clampedRange.location + clampedRange.length

        guard let startIndex = stringIndex(in: oldText, utf16Offset: startOffset),
              let oldEndIndex = stringIndex(in: oldText, utf16Offset: oldEndOffset) else {
            return nil
        }

        let newText = String(oldText[..<startIndex])
            + replacementText
            + String(oldText[oldEndIndex...])
        let newEndOffset = startOffset + (replacementText as NSString).length

        guard let newEndIndex = stringIndex(in: newText, utf16Offset: newEndOffset) else {
            return nil
        }

        return SyntaxInputEdit(
            startByte: oldText[..<startIndex].utf8.count,
            oldEndByte: oldText[..<oldEndIndex].utf8.count,
            newEndByte: newText[..<newEndIndex].utf8.count,
            startPoint: bytePoint(in: oldText, upTo: startIndex),
            oldEndPoint: bytePoint(in: oldText, upTo: oldEndIndex),
            newEndPoint: bytePoint(in: newText, upTo: newEndIndex)
        )
    }

    private static func stringIndex(in text: String, utf16Offset: Int) -> String.Index? {
        guard utf16Offset >= 0 && utf16Offset <= text.utf16.count else { return nil }
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Offset)
        return String.Index(utf16Index, within: text)
    }

    private static func bytePoint(in text: String, upTo index: String.Index) -> SyntaxBytePoint {
        var line = 0
        var byteColumn = 0
        for byte in text[..<index].utf8 {
            if byte == 0x0A {
                line += 1
                byteColumn = 0
            } else {
                byteColumn += 1
            }
        }
        return SyntaxBytePoint(line: line, byteColumn: byteColumn)
    }

    private static func preconditionValidPoint(_ point: SyntaxBytePoint) {
        precondition(point.line >= 0 && point.line <= Int(UInt32.max))
        precondition(point.byteColumn >= 0 && point.byteColumn <= Int(UInt32.max))
    }
}
