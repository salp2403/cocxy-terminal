// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionAcceptHandler.swift - Converts inline suggestions into editor edits.

import Foundation

struct CompletionAcceptHandler {
    func replacement(
        for completion: InlineCompletion,
        document: EditorDocument
    ) -> EditorReplacement? {
        let text = completion.text
        guard !text.isEmpty else { return nil }
        let range = completion.replacementRange.clamped(to: document.buffer.utf16Length)
        return EditorReplacement(range: range, text: text)
    }
}
