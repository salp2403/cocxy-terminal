// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyInputClassifier

@Suite("Heuristic input classifier")
struct HeuristicInputClassifierSwiftTestingTests {

    @Test("empty input is classified explicitly")
    func emptyInputIsClassifiedExplicitly() {
        let classifier = HeuristicInputClassifier()

        let result = classifier.classify("   ")

        #expect(result.category == .empty)
        #expect(result.confidence == 1.0)
    }

    @Test("common executable prefixes classify as shell")
    func commonExecutablePrefixesClassifyAsShell() {
        let classifier = HeuristicInputClassifier()

        #expect(classifier.classify("git status").category == .shellCommand)
        #expect(classifier.classify("swift test --filter InputClassifier").category == .shellCommand)
        #expect(classifier.classify("./scripts/build-app.sh release").category == .shellCommand)
    }

    @Test("shell operators classify as shell")
    func shellOperatorsClassifyAsShell() {
        let classifier = HeuristicInputClassifier()

        #expect(classifier.classify("echo hello | wc -c").category == .shellCommand)
        #expect(classifier.classify("mkdir -p build && swift build").category == .shellCommand)
    }

    @Test("near miss executable names classify as shell with suggestion")
    func nearMissExecutableNamesClassifyAsShellWithSuggestion() {
        let classifier = HeuristicInputClassifier()

        let result = classifier.classify("gti status")

        #expect(result.category == .shellCommand)
        #expect(result.confidence >= 0.7)
        #expect(result.suggestedCommand == "git")
    }

    @Test("dangerous dictionary takes priority")
    func dangerousDictionaryTakesPriority() {
        let classifier = HeuristicInputClassifier()

        let result = classifier.classify("rm -rf /")

        #expect(result.category == .dangerousCommand)
        #expect(result.shouldWarnBeforeExecution)
    }

    @Test("sentence-like questions are left for natural language detector")
    func sentenceLikeQuestionsAreLeftForNaturalLanguageDetector() {
        let classifier = HeuristicInputClassifier()

        let result = classifier.classify("what is the weather today")

        #expect(result.category == .unknown)
        #expect(result.confidence < 0.75)
    }
}
