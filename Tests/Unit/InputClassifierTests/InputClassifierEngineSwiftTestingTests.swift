// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyInputClassifier

@Suite("Input classifier engine")
struct InputClassifierEngineSwiftTestingTests {

    @Test("classifier detects dangerous destructive commands")
    func classifierDetectsDangerousDestructiveCommands() async {
        let engine = InputClassifierComposer()

        let result = await engine.classify("rm -rf /")

        #expect(result.category == .dangerousCommand)
        #expect(result.confidence >= 0.9)
        #expect(result.dangerReason != nil)
    }

    @Test("classifier detects English natural language")
    func classifierDetectsEnglishNaturalLanguage() async {
        let engine = InputClassifierComposer()

        let result = await engine.classify("what is the weather")

        #expect(result.category == .naturalLanguage)
        #expect(result.languageCode == "en")
    }

    @Test("classifier detects Spanish natural language")
    func classifierDetectsSpanishNaturalLanguage() async {
        let engine = InputClassifierComposer()

        let result = await engine.classify("cual es el clima")

        #expect(result.category == .naturalLanguage)
        #expect(result.languageCode == "es")
    }

    @Test("classifier detects shell commands with high confidence")
    func classifierDetectsShellCommandsWithHighConfidence() async {
        let engine = InputClassifierComposer()

        let result = await engine.classify("git status")

        #expect(result.category == .shellCommand)
        #expect(result.confidence >= 0.85)
    }
}
