// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FoundationModelsInlineCompletionProvider.swift - Local-only inline completion provider.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsInlineCompletionProvider: InlineCompletionProviding {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelsInlineCompletionRuntime.isAvailable
        }
        #endif
        return false
    }

    func completion(for context: CompletionContext) async throws -> InlineCompletion? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await FoundationModelsInlineCompletionRuntime.completion(for: context)
        }
        #endif
        return nil
    }
}

enum InlineCompletionResponseSanitizer {
    static func sanitizedText(_ rawText: String, maxUTF16Length: Int = 400) -> String? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripCodeFence(from: text)
        text = stripKnownPrefixes(from: text)
        text = stripWrappingQuotes(from: text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        let nsText = text as NSString
        guard nsText.length > maxUTF16Length else { return text }
        return nsText.substring(with: NSRange(location: 0, length: max(0, maxUTF16Length)))
    }

    private static func stripCodeFence(from text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3,
              lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```"
        else { return text }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    private static func stripKnownPrefixes(from text: String) -> String {
        let prefixes = [
            "completion:",
            "suggestion:",
            "inline completion:",
        ]
        let lowercased = text.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    private static func stripWrappingQuotes(from text: String) -> String {
        guard text.count >= 2 else { return text }
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("`", "`"),
        ]
        guard let first = text.first,
              let last = text.last,
              pairs.contains(where: { $0.0 == first && $0.1 == last })
        else { return text }
        return String(text.dropFirst().dropLast())
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelsInlineCompletionRuntime {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func completion(for context: CompletionContext) async throws -> InlineCompletion? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let session = LanguageModelSession(
            model: .default,
            instructions: instructions(for: context)
        )
        let response = try await session.respond(
            to: prompt(for: context),
            options: GenerationOptions(maximumResponseTokens: 96)
        )
        guard let text = InlineCompletionResponseSanitizer.sanitizedText(response.content) else {
            return nil
        }
        return InlineCompletion(
            text: text,
            replacementRange: context.caretRange,
            source: .foundationModelsOnDevice
        )
    }

    private static func instructions(for context: CompletionContext) -> String {
        """
        You are Cocxy's local inline code completion engine.
        Return only the code text to insert at the caret.
        Do not explain, do not use Markdown fences, and do not repeat existing code.
        The provider is fully on-device. No network fallback is available.
        Language: \(context.languageID)
        """
    }

    private static func prompt(for context: CompletionContext) -> String {
        """
        Complete the code at <caret>.

        Prefix:
        \(context.prefix)
        <caret>
        Suffix:
        \(context.suffix)
        """
    }
}
#endif
