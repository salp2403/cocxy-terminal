// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import NaturalLanguage

public struct NaturalLanguageDetection: Sendable, Equatable {
    public let languageCode: String
    public let confidence: Double
}

public struct NaturalLanguageDetector: Sendable {
    public init() {}

    public func detect(_ input: String) -> NaturalLanguageDetection? {
        let normalized = ShellInputRecognizer.normalized(input)
        guard normalized.count >= 6 else { return nil }
        guard !ShellInputRecognizer.looksLikeShellCommand(normalized) else { return nil }

        let lowered = normalized.lowercased()
        let englishScore = score(lowered, indicators: englishIndicators)
        let spanishScore = score(lowered, indicators: spanishIndicators)
        let sentenceLike = isSentenceLike(lowered)

        if spanishScore > 0, spanishScore >= englishScore {
            return NaturalLanguageDetection(
                languageCode: "es",
                confidence: min(0.95, 0.75 + Double(spanishScore) * 0.05)
            )
        }

        if englishScore > 0 {
            return NaturalLanguageDetection(
                languageCode: "en",
                confidence: min(0.95, 0.75 + Double(englishScore) * 0.05)
            )
        }

        guard sentenceLike else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        if let englishConfidence = hypotheses[.english], englishConfidence >= 0.55 {
            return NaturalLanguageDetection(languageCode: "en", confidence: englishConfidence)
        }
        if let spanishConfidence = hypotheses[.spanish], spanishConfidence >= 0.55 {
            return NaturalLanguageDetection(languageCode: "es", confidence: spanishConfidence)
        }

        return nil
    }

    private var englishIndicators: [String] {
        [
            "what", "how", "why", "when", "where", "who", "which", "please",
            "explain", "help", "weather", "can you", "could you", "current directory",
        ]
    }

    private var spanishIndicators: [String] {
        [
            "que", "qué", "cual", "cuál", "como", "cómo", "porque", "por qué",
            "clima", "ayuda", "explica", "listar", "archivos", "puedo",
        ]
    }

    private func score(_ input: String, indicators: [String]) -> Int {
        indicators.reduce(0) { total, indicator in
            input.contains(indicator) ? total + 1 : total
        }
    }

    private func isSentenceLike(_ input: String) -> Bool {
        input.contains("?")
            || input.split(separator: " ").count >= 4
            || input.hasPrefix("please ")
    }
}
