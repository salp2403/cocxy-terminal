// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionEngine.swift - Coordinates inline completion trigger, context and provider.

import Foundation

struct CompletionEngine: Sendable {
    let provider: any InlineCompletionProviding
    let config: CompletionConfig

    init(
        provider: any InlineCompletionProviding = DisabledInlineCompletionProvider(),
        config: CompletionConfig = .defaults
    ) {
        self.provider = provider
        self.config = config
    }

    func suggestion(for input: CompletionTriggerInput) async throws -> InlineCompletion? {
        let policy = CompletionTriggerPolicy(config: config)
        guard policy.shouldTrigger(input),
              let languageID = input.languageID
        else {
            return nil
        }

        let builder = CompletionContextBuilder(maxContextUTF16Length: config.maxContextUTF16Length)
        guard let context = builder.context(
            document: input.document,
            selection: input.selection,
            languageID: languageID
        ) else {
            return nil
        }

        guard let suggestion = try await provider.completion(for: context),
              !suggestion.text.isEmpty
        else {
            return nil
        }

        return suggestion
    }
}
