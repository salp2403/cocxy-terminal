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

struct LocalCodeTokenEmbeddingProvider: CodebaseEmbeddingProviding {
    let dimensions: Int
    let maxTokens: Int

    init(dimensions: Int = 256, maxTokens: Int = 4_096) {
        self.dimensions = max(16, dimensions)
        self.maxTokens = max(1, maxTokens)
    }

    var identifier: String {
        "local-code-token-on-device"
    }

    var isAvailable: Bool {
        true
    }

    func embedding(for text: String) throws -> [Double] {
        let tokens = Self.tokens(in: text)
        guard !tokens.isEmpty else {
            throw CodebaseEmbeddingProviderError.emptyInput
        }

        var vector = Array(repeating: 0.0, count: dimensions)
        for token in tokens.prefix(maxTokens) {
            let hash = Self.stableHash(token)
            let index = Int(hash % UInt64(dimensions))
            let sign = (hash & 0x8000_0000_0000_0000) == 0 ? 1.0 : -1.0
            let weight = token.count <= 2 ? 0.35 : 1.0
            vector[index] += sign * weight
        }

        let magnitude = sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
        guard magnitude > 0 else {
            throw CodebaseEmbeddingProviderError.emptyEmbedding(identifier)
        }
        return vector.map { $0 / magnitude }
    }

    private static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var previousWasLowercaseOrDigit = false

        func flush() {
            guard current.count >= 2 else {
                current.removeAll(keepingCapacity: true)
                return
            }
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for character in text {
            guard character.isLetter || character.isNumber else {
                flush()
                previousWasLowercaseOrDigit = false
                continue
            }
            if character.isUppercase, previousWasLowercaseOrDigit {
                flush()
            }
            current += character.lowercased()
            previousWasLowercaseOrDigit = character.isLowercase || character.isNumber
        }
        flush()
        return tokens
    }

    private static func stableHash(_ token: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
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
