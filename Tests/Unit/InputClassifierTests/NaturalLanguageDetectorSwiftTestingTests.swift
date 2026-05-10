// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyInputClassifier

@Suite("Natural language detector")
struct NaturalLanguageDetectorSwiftTestingTests {

    @Test("detects English questions")
    func detectsEnglishQuestions() {
        let detector = NaturalLanguageDetector()

        let result = detector.detect("what is the weather today")

        #expect(result?.languageCode == "en")
        #expect(result?.confidence ?? 0 >= 0.75)
    }

    @Test("detects Spanish questions without requiring accents")
    func detectsSpanishQuestionsWithoutAccents() {
        let detector = NaturalLanguageDetector()

        let result = detector.detect("cual es el clima de hoy")

        #expect(result?.languageCode == "es")
        #expect(result?.confidence ?? 0 >= 0.75)
    }

    @Test("does not classify shell commands as language prompts")
    func doesNotClassifyShellCommandsAsLanguagePrompts() {
        let detector = NaturalLanguageDetector()

        #expect(detector.detect("git status") == nil)
        #expect(detector.detect("ls -la | grep README") == nil)
    }
}
