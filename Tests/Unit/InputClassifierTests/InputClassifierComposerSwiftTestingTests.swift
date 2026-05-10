// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyInputClassifier

@Suite("Input classifier composer")
struct InputClassifierComposerSwiftTestingTests {

    @Test("heuristic dangerous result wins before natural language")
    func heuristicDangerousResultWinsBeforeNaturalLanguage() async {
        let classifier = InputClassifierComposer()

        let result = await classifier.classify("please run rm -rf /")

        #expect(result.category == .dangerousCommand)
    }

    @Test("natural language fallback handles Spanish prompts")
    func naturalLanguageFallbackHandlesSpanishPrompts() async {
        let classifier = InputClassifierComposer()

        let result = await classifier.classify("como puedo listar archivos")

        #expect(result.category == .naturalLanguage)
        #expect(result.languageCode == "es")
    }

    @Test("shell commands bypass Foundation Models")
    func shellCommandsBypassFoundationModels() async {
        let classifier = InputClassifierComposer()

        let result = await classifier.classify("git status --short")

        #expect(result.category == .shellCommand)
        #expect(result.routingHint == .executeInShell)
    }

    @Test("result cache preserves repeated classifications")
    func resultCachePreservesRepeatedClassifications() async {
        let classifier = InputClassifierComposer()

        let first = await classifier.classify("what is the current directory")
        let second = await classifier.classify("what is the current directory")

        #expect(first == second)
    }
}
