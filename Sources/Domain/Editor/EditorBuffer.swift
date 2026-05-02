// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorBuffer.swift - Plain text buffer using NSTextView-compatible UTF-16 offsets.

import Foundation

struct EditorBuffer: Equatable {
    private(set) var text: String

    init(text: String = "") {
        self.text = text
    }

    var utf16Length: Int {
        (text as NSString).length
    }

    var lineCount: Int {
        guard utf16Length > 0 else { return 1 }
        var count = 1
        let nsText = text as NSString
        for index in 0..<nsText.length where nsText.character(at: index) == 10 {
            count += 1
        }
        return count
    }

    var lineStartOffsets: [Int] {
        let nsText = text as NSString
        var offsets = [0]
        guard nsText.length > 0 else { return offsets }
        for index in 0..<nsText.length where nsText.character(at: index) == 10 {
            offsets.append(index + 1)
        }
        return offsets
    }

    func string(in range: EditorTextRange) -> String {
        let clamped = range.clamped(to: utf16Length)
        return (text as NSString).substring(with: NSRange(location: clamped.location, length: clamped.length))
    }

    func lineAndColumn(for offset: Int) -> (line: Int, column: Int) {
        let safeOffset = min(max(0, offset), utf16Length)
        let starts = lineStartOffsets
        var line = 0
        for (index, start) in starts.enumerated() where start <= safeOffset {
            line = index
        }
        return (line: line, column: safeOffset - starts[line])
    }

    func offset(line requestedLine: Int, column requestedColumn: Int) -> Int {
        let starts = lineStartOffsets
        let line = min(max(0, requestedLine), starts.count - 1)
        let start = starts[line]
        let nextStart = line + 1 < starts.count ? starts[line + 1] : utf16Length
        let contentEnd = trimmedLineEnd(start: start, end: nextStart)
        return min(start + max(0, requestedColumn), contentEnd)
    }

    func lineRange(containing offset: Int) -> EditorTextRange {
        let safeOffset = min(max(0, offset), utf16Length)
        let nsRange = (text as NSString).lineRange(for: NSRange(location: safeOffset, length: 0))
        return EditorTextRange(location: nsRange.location, length: nsRange.length)
    }

    @discardableResult
    mutating func replace(_ replacement: EditorReplacement) -> EditorChange {
        replace([replacement], selectionBefore: .caret(at: replacement.range.location))
    }

    @discardableResult
    mutating func replaceSelection(_ selection: EditorSelection, with replacementText: String) -> EditorChange {
        let clampedSelection = selection.clamped(to: utf16Length)
        let replacements = clampedSelection.normalizedRanges(maximumLength: utf16Length)
            .map { EditorReplacement(range: $0, text: replacementText) }
        return replace(replacements, selectionBefore: clampedSelection)
    }

    @discardableResult
    mutating func deleteBackward(_ selection: EditorSelection) -> EditorChange {
        let clampedSelection = selection.clamped(to: utf16Length)
        let nsText = text as NSString
        let replacements = clampedSelection.normalizedRanges(maximumLength: utf16Length).compactMap { range in
            if !range.isCaret {
                return EditorReplacement(range: range, text: "")
            }
            guard range.location > 0 else { return nil }
            let composedRange = nsText.rangeOfComposedCharacterSequence(at: range.location - 1)
            return EditorReplacement(
                range: EditorTextRange(location: composedRange.location, length: composedRange.length),
                text: ""
            )
        }
        return replace(replacements, selectionBefore: clampedSelection)
    }

    @discardableResult
    mutating func replace(_ replacements: [EditorReplacement], selectionBefore: EditorSelection) -> EditorChange {
        let beforeText = text
        let nsText = NSMutableString(string: text)
        let normalized = normalizedReplacements(replacements)
        guard !normalized.isEmpty else {
            return EditorChange(
                beforeText: beforeText,
                afterText: beforeText,
                replacements: [],
                selectionBefore: selectionBefore,
                selectionAfter: selectionBefore
            )
        }
        var delta = 0
        var afterRanges: [EditorTextRange] = []

        for replacement in normalized {
            let adjustedLocation = replacement.range.location + delta
            let nsRange = NSRange(location: adjustedLocation, length: replacement.range.length)
            nsText.replaceCharacters(in: nsRange, with: replacement.text)
            let replacementLength = (replacement.text as NSString).length
            afterRanges.append(EditorTextRange(location: adjustedLocation + replacementLength, length: 0))
            delta += replacementLength - replacement.range.length
        }

        text = nsText as String
        return EditorChange(
            beforeText: beforeText,
            afterText: text,
            replacements: normalized,
            selectionBefore: selectionBefore,
            selectionAfter: EditorSelection(ranges: afterRanges)
        )
    }

    private func normalizedReplacements(_ replacements: [EditorReplacement]) -> [EditorReplacement] {
        let sorted = replacements
            .map { EditorReplacement(range: $0.range.clamped(to: utf16Length), text: $0.text) }
            .sorted { lhs, rhs in lhs.range < rhs.range }

        var result: [EditorReplacement] = []
        for replacement in sorted {
            guard let last = result.last else {
                result.append(replacement)
                continue
            }
            if last.range == replacement.range, last.text == replacement.text {
                continue
            }
            if last.range.intersects(replacement.range) {
                if !last.range.isCaret, !replacement.range.isCaret {
                    let union = last.range.union(replacement.range)
                    result[result.count - 1] = EditorReplacement(range: union, text: replacement.text)
                } else if last.range.isCaret, !replacement.range.isCaret {
                    result[result.count - 1] = replacement
                }
                continue
            }
            result.append(replacement)
        }
        return result
    }

    private func trimmedLineEnd(start: Int, end: Int) -> Int {
        let nsText = text as NSString
        var contentEnd = end
        while contentEnd > start {
            let character = nsText.character(at: contentEnd - 1)
            if character == 10 || character == 13 {
                contentEnd -= 1
            } else {
                break
            }
        }
        return contentEnd
    }
}
