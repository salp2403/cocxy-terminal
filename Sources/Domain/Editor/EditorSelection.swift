// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorSelection.swift - UTF-16 editor ranges and multi-cursor selection model.

import Foundation

struct EditorTextRange: Equatable, Hashable, Comparable {
    var location: Int
    var length: Int

    init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    var end: Int { location + length }
    var isCaret: Bool { length == 0 }

    static func < (lhs: EditorTextRange, rhs: EditorTextRange) -> Bool {
        if lhs.location != rhs.location { return lhs.location < rhs.location }
        return lhs.length < rhs.length
    }

    func clamped(to maximumLength: Int) -> EditorTextRange {
        let safeMaximum = max(0, maximumLength)
        let safeLocation = min(location, safeMaximum)
        let safeEnd = min(end, safeMaximum)
        return EditorTextRange(location: safeLocation, length: max(0, safeEnd - safeLocation))
    }

    func contains(_ offset: Int) -> Bool {
        if isCaret {
            return offset == location
        }
        return offset >= location && offset < end
    }

    func intersects(_ other: EditorTextRange) -> Bool {
        if isCaret && other.isCaret {
            return location == other.location
        }
        if isCaret {
            return other.contains(location)
        }
        if other.isCaret {
            return contains(other.location)
        }
        return location < other.end && other.location < end
    }

    func union(_ other: EditorTextRange) -> EditorTextRange {
        let start = min(location, other.location)
        let finish = max(end, other.end)
        return EditorTextRange(location: start, length: finish - start)
    }
}

struct EditorSelection: Equatable {
    var ranges: [EditorTextRange]
    var primaryIndex: Int

    init(ranges: [EditorTextRange], primaryIndex: Int = 0) {
        let safeRanges = ranges.isEmpty ? [EditorTextRange(location: 0, length: 0)] : ranges
        self.ranges = safeRanges
        self.primaryIndex = min(max(0, primaryIndex), safeRanges.count - 1)
    }

    static func caret(at location: Int) -> EditorSelection {
        EditorSelection(ranges: [EditorTextRange(location: location, length: 0)])
    }

    var primaryRange: EditorTextRange {
        ranges[primaryIndex]
    }

    func clamped(to maximumLength: Int) -> EditorSelection {
        EditorSelection(
            ranges: ranges.map { $0.clamped(to: maximumLength) },
            primaryIndex: primaryIndex
        )
    }

    func normalizedRanges(maximumLength: Int? = nil) -> [EditorTextRange] {
        var sorted = ranges
            .map { maximumLength.map($0.clamped(to:)) ?? $0 }
            .sorted()

        var result: [EditorTextRange] = []
        while let next = sorted.first {
            sorted.removeFirst()
            guard let last = result.last else {
                result.append(next)
                continue
            }
            if last == next {
                continue
            }
            if last.intersects(next) {
                if !last.isCaret, !next.isCaret {
                    result[result.count - 1] = last.union(next)
                } else if last.isCaret, !next.isCaret {
                    result[result.count - 1] = next
                }
                continue
            }
            result.append(next)
        }
        return result
    }
}
