// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionContext.swift - Bounded editor context for inline completions.

import Foundation

struct CompletionContext: Sendable, Equatable {
    let documentID: UUID
    let documentVersion: Int
    let fileURL: URL?
    let languageID: String
    let caretRange: EditorTextRange
    let prefix: String
    let suffix: String
}

struct CompletionContextBuilder: Sendable {
    let maxContextUTF16Length: Int

    init(maxContextUTF16Length: Int = CompletionConfig.defaults.maxContextUTF16Length) {
        self.maxContextUTF16Length = max(0, maxContextUTF16Length)
    }

    func context(
        document: EditorDocument,
        selection: EditorSelection,
        languageID: String
    ) -> CompletionContext? {
        let clampedSelection = selection.clamped(to: document.buffer.utf16Length)
        guard clampedSelection.ranges.count == 1,
              let caretRange = clampedSelection.ranges.first,
              caretRange.isCaret
        else {
            return nil
        }

        let text = document.text as NSString
        let prefixStart = max(0, caretRange.location - maxContextUTF16Length)
        let suffixEnd = min(text.length, caretRange.location + maxContextUTF16Length)
        let prefixRange = NSRange(location: prefixStart, length: caretRange.location - prefixStart)
        let suffixRange = NSRange(location: caretRange.location, length: suffixEnd - caretRange.location)

        return CompletionContext(
            documentID: document.id,
            documentVersion: document.version,
            fileURL: document.fileURL,
            languageID: normalizedLanguageID(languageID),
            caretRange: caretRange,
            prefix: text.substring(with: prefixRange),
            suffix: text.substring(with: suffixRange)
        )
    }

    private func normalizedLanguageID(_ rawLanguageID: String) -> String {
        rawLanguageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
