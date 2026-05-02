// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineCompletionProvider.swift - Provider contract for inline editor completions.

import Foundation

struct InlineCompletion: Sendable, Equatable {
    let text: String
    let replacementRange: EditorTextRange
    let source: CompletionProviderKind

    init(
        text: String,
        replacementRange: EditorTextRange,
        source: CompletionProviderKind
    ) {
        self.text = text
        self.replacementRange = replacementRange
        self.source = source
    }
}

protocol InlineCompletionProviding: Sendable {
    func completion(for context: CompletionContext) async throws -> InlineCompletion?
}

struct DisabledInlineCompletionProvider: InlineCompletionProviding {
    func completion(for context: CompletionContext) async throws -> InlineCompletion? {
        _ = context
        return nil
    }
}
