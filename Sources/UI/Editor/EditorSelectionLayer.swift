// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorSelectionLayer.swift - Bridges NSTextView selected ranges into the editor domain model.

import AppKit

enum EditorSelectionLayer {
    @MainActor
    static func selection(from textView: NSTextView) -> EditorSelection {
        selection(from: textView.selectedRanges, maximumLength: (textView.string as NSString).length)
    }

    static func selection(from selectedRanges: [NSValue], maximumLength: Int) -> EditorSelection {
        let ranges = selectedRanges.map(\.rangeValue).map {
            EditorTextRange(location: $0.location, length: $0.length).clamped(to: maximumLength)
        }
        return EditorSelection(ranges: ranges)
    }
}
