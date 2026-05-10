// Copyright (c) 2026 Said Arturo Lopez. MIT License.

public actor InputClassifierComposer: InputClassifierEngine {
    private let heuristicClassifier: HeuristicInputClassifier
    private let naturalLanguageDetector: NaturalLanguageDetector
    private let foundationModelsClassifier: FoundationModelsInputClassifier?
    private var cache: [String: InputClassification] = [:]

    public init(
        heuristicClassifier: HeuristicInputClassifier = HeuristicInputClassifier(),
        naturalLanguageDetector: NaturalLanguageDetector = NaturalLanguageDetector(),
        foundationModelsClassifier: FoundationModelsInputClassifier? = FoundationModelsInputClassifier()
    ) {
        self.heuristicClassifier = heuristicClassifier
        self.naturalLanguageDetector = naturalLanguageDetector
        self.foundationModelsClassifier = foundationModelsClassifier
    }

    public func classify(_ input: String) async -> InputClassification {
        let key = ShellInputRecognizer.normalized(input)
        if let cached = cache[key] {
            return cached
        }

        let heuristicResult = heuristicClassifier.classify(input)
        switch heuristicResult.category {
        case .empty, .dangerousCommand, .shellCommand:
            cache[key] = heuristicResult
            return heuristicResult
        case .naturalLanguage, .unknown:
            break
        }

        if let detection = naturalLanguageDetector.detect(input) {
            let result = InputClassification(
                category: .naturalLanguage,
                confidence: detection.confidence,
                languageCode: detection.languageCode,
                routingHint: .offerAgentRouting
            )
            cache[key] = result
            return result
        }

        if let foundationModelsClassifier,
           let result = await foundationModelsClassifier.classify(input) {
            cache[key] = result
            return result
        }

        cache[key] = heuristicResult
        return heuristicResult
    }
}
