// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorOperation.swift - Atomic editor replacement operations.

import Foundation

struct EditorReplacement: Equatable {
    var range: EditorTextRange
    var text: String

    init(range: EditorTextRange, text: String) {
        self.range = range
        self.text = text
    }
}

struct EditorChange: Equatable {
    var beforeText: String
    var afterText: String
    var replacements: [EditorReplacement]
    var selectionBefore: EditorSelection
    var selectionAfter: EditorSelection

    var changedRanges: [EditorTextRange] {
        replacements.map { replacement in
            EditorTextRange(
                location: replacement.range.location,
                length: (replacement.text as NSString).length
            )
        }
    }
}
