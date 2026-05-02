// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionDomainSwiftTestingTests.swift - Inline completion domain foundation tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Inline completion domain")
struct CompletionDomainSwiftTestingTests {

    @Test("context builder captures bounded UTF-16 prefix and suffix around the primary caret")
    func contextBuilderCapturesBoundedPrefixAndSuffix() throws {
        let document = EditorDocument(
            fileURL: URL(fileURLWithPath: "/tmp/Sample.swift"),
            text: "let alpha = 1\nlet beta = alp\nprint(beta)\n"
        )
        let caret = ("let alpha = 1\nlet beta = alp" as NSString).length
        let selection = EditorSelection.caret(at: caret)
        let builder = CompletionContextBuilder(maxContextUTF16Length: 16)

        let context = try #require(builder.context(
            document: document,
            selection: selection,
            languageID: "swift"
        ))

        #expect(context.languageID == "swift")
        #expect(context.fileURL == URL(fileURLWithPath: "/tmp/Sample.swift"))
        #expect(context.caretRange == EditorTextRange(location: caret, length: 0))
        #expect((context.prefix as NSString).length <= 16)
        #expect(context.prefix.hasSuffix("let beta = alp"))
        #expect(context.suffix.hasPrefix("\nprint(beta)"))
    }

    @Test("context builder refuses multi-cursor and non-caret selections")
    func contextBuilderRefusesUnsupportedSelections() {
        let document = EditorDocument(text: "let value = 1\n")
        let builder = CompletionContextBuilder()

        #expect(builder.context(
            document: document,
            selection: EditorSelection(ranges: [
                EditorTextRange(location: 3, length: 0),
                EditorTextRange(location: 8, length: 0),
            ]),
            languageID: "swift"
        ) == nil)
        #expect(builder.context(
            document: document,
            selection: EditorSelection(ranges: [EditorTextRange(location: 0, length: 3)]),
            languageID: "swift"
        ) == nil)
    }

    @Test("trigger policy is opt-in, idle-gated and code-language only")
    func triggerPolicyIsOptInIdleGatedAndCodeLanguageOnly() {
        let document = EditorDocument(text: "func total() -> Int { ret")
        let selection = EditorSelection.caret(at: document.buffer.utf16Length)
        let enabled = CompletionConfig(
            inlineAIEnabled: true,
            enabledLanguageIDs: ["swift", "python"]
        )
        let disabled = CompletionConfig.defaults

        #expect(!CompletionTriggerPolicy(config: disabled).shouldTrigger(CompletionTriggerInput(
            document: document,
            selection: selection,
            languageID: "swift",
            idleDuration: 1.0,
            insertedText: "t"
        )))
        #expect(!CompletionTriggerPolicy(config: enabled).shouldTrigger(CompletionTriggerInput(
            document: document,
            selection: selection,
            languageID: "swift",
            idleDuration: 0.05,
            insertedText: "t"
        )))
        #expect(!CompletionTriggerPolicy(config: enabled).shouldTrigger(CompletionTriggerInput(
            document: document,
            selection: selection,
            languageID: "markdown",
            idleDuration: 1.0,
            insertedText: "t"
        )))
        #expect(CompletionTriggerPolicy(config: enabled).shouldTrigger(CompletionTriggerInput(
            document: document,
            selection: selection,
            languageID: "swift",
            idleDuration: 1.0,
            insertedText: "t"
        )))
    }

    @Test("completion engine returns provider suggestions only when trigger and context are valid")
    func completionEngineReturnsProviderSuggestionsOnlyWhenValid() async throws {
        let document = EditorDocument(text: "func sum(a: Int, b: Int) -> Int { ")
        let selection = EditorSelection.caret(at: document.buffer.utf16Length)
        let provider = RecordingInlineCompletionProvider(response: InlineCompletion(
            text: "a + b }",
            replacementRange: EditorTextRange(location: document.buffer.utf16Length, length: 0),
            source: .foundationModelsOnDevice
        ))
        let engine = CompletionEngine(
            provider: provider,
            config: CompletionConfig(inlineAIEnabled: true, enabledLanguageIDs: ["swift"])
        )

        let suppressed = try await engine.suggestion(for: CompletionTriggerInput(
            document: document,
            selection: selection,
            languageID: "markdown",
            idleDuration: 1.0,
            insertedText: " "
        ))
        let suggestion = try await engine.suggestion(for: CompletionTriggerInput(
            document: document,
            selection: selection,
            languageID: "swift",
            idleDuration: 1.0,
            insertedText: " "
        ))
        let requests = await provider.requests

        #expect(suppressed == nil)
        #expect(suggestion?.text == "a + b }")
        #expect(requests.count == 1)
        #expect(requests.first?.prefix.hasSuffix("-> Int { ") == true)
    }
}

private actor RecordingInlineCompletionProvider: InlineCompletionProviding {
    let response: InlineCompletion?
    private(set) var requests: [CompletionContext] = []

    init(response: InlineCompletion?) {
        self.response = response
    }

    func completion(for context: CompletionContext) async throws -> InlineCompletion? {
        requests.append(context)
        return response
    }
}
