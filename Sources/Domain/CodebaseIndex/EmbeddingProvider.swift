// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EmbeddingProvider.swift - On-device text embeddings for codebase indexing.

import Foundation
import NaturalLanguage

protocol CodebaseEmbeddingProviding: Sendable {
    var identifier: String { get }
    var isAvailable: Bool { get }

    func embedding(for text: String) throws -> [Double]
}

enum CodebaseEmbeddingProviderError: Error, Sendable, Equatable {
    case emptyInput
    case providerUnavailable(String)
    case emptyEmbedding(String)
    case nonFiniteEmbedding(String)
}

struct NaturalLanguageCodebaseEmbeddingProvider: CodebaseEmbeddingProviding {
    let preferredLanguages: [NLLanguage]
    let maxInputCharacters: Int

    init(preferredLanguages: [NLLanguage] = [.english, .spanish], maxInputCharacters: Int = 1_024) {
        self.preferredLanguages = preferredLanguages
        self.maxInputCharacters = max(1, maxInputCharacters)
    }

    var identifier: String {
        "natural-language-on-device"
    }

    var isAvailable: Bool {
        if #available(macOS 11.0, *) {
            return candidateLanguages(for: "code search")
                .contains { NLEmbedding.sentenceEmbedding(for: $0) != nil }
        }
        return false
    }

    func embedding(for text: String) throws -> [Double] {
        let normalized = String(Self.normalizedInput(text).prefix(maxInputCharacters))
        guard !normalized.isEmpty else {
            throw CodebaseEmbeddingProviderError.emptyInput
        }

        guard #available(macOS 11.0, *) else {
            throw CodebaseEmbeddingProviderError.providerUnavailable(identifier)
        }

        for language in candidateLanguages(for: normalized) {
            let vector = autoreleasepool { () -> [Double]? in
                guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
                    return nil
                }
                return embedding.vector(for: normalized)
            }
            guard let vector, !vector.isEmpty
            else {
                continue
            }
            guard vector.allSatisfy(\.isFinite) else {
                throw CodebaseEmbeddingProviderError.nonFiniteEmbedding(identifier)
            }
            return vector
        }

        throw CodebaseEmbeddingProviderError.emptyEmbedding(identifier)
    }

    private func candidateLanguages(for text: String) -> [NLLanguage] {
        var languages: [NLLanguage] = []
        if let detected = NLLanguageRecognizer.dominantLanguage(for: text) {
            languages.append(detected)
        }
        languages.append(contentsOf: preferredLanguages)
        languages.append(.english)

        var seen = Set<String>()
        return languages.filter { language in
            seen.insert(language.rawValue).inserted
        }
    }

    private static func normalizedInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
