// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodebaseQuerySuggestions.swift - Local query suggestions for codebase search.

import Foundation

struct CodebaseQuerySuggestionRequest: Sendable, Equatable {
    let query: String
    let scopePath: String?
    let limit: Int

    init(query: String, scopePath: String? = nil, limit: Int = 10) {
        self.query = query
        self.scopePath = scopePath
        self.limit = limit
    }
}

struct CodebaseQuerySuggestion: Sendable, Equatable {
    let text: String
    let sourcePath: String?
    let score: Double
}

extension CodebaseIndex {
    func suggestions(_ request: CodebaseQuerySuggestionRequest) throws -> [CodebaseQuerySuggestion] {
        let searchRoot: URL
        if let scopePath = request.scopePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !scopePath.isEmpty {
            searchRoot = try workspace.requireDirectory(scopePath)
        } else {
            searchRoot = workspace.rootURL
        }

        return try CodebaseQuerySuggestionEngine(
            workspace: workspace,
            maxFileBytes: maxFileBytes
        ).suggestions(
            query: request.query,
            startingAt: searchRoot,
            limit: request.limit
        )
    }
}

private struct CodebaseQuerySuggestionEngine {
    let workspace: AgentWorkspace
    let maxFileBytes: Int
    let maxContentCharacters: Int
    let maxIdentifiersPerFile: Int

    init(
        workspace: AgentWorkspace,
        maxFileBytes: Int,
        maxContentCharacters: Int = 120_000,
        maxIdentifiersPerFile: Int = 2_000
    ) {
        self.workspace = workspace
        self.maxFileBytes = maxFileBytes
        self.maxContentCharacters = max(1, maxContentCharacters)
        self.maxIdentifiersPerFile = max(1, maxIdentifiersPerFile)
    }

    func suggestions(query: String, startingAt rootURL: URL, limit: Int) throws -> [CodebaseQuerySuggestion] {
        let normalizedQuery = Self.normalizedPhrase(query)
        let queryTokens = Set(Self.words(in: normalizedQuery))
        let scanner = CodebaseIndexFileScanner(workspace: workspace, maxFileBytes: maxFileBytes)
        var bestByText: [String: CodebaseQuerySuggestion] = [:]

        for file in scanner.regularFiles(startingAt: rootURL) {
            for phrase in Self.phrases(in: file.relativePath) {
                consider(
                    phrase,
                    sourcePath: file.relativePath,
                    baseScore: 8,
                    normalizedQuery: normalizedQuery,
                    queryTokens: queryTokens,
                    bestByText: &bestByText
                )
            }

            guard let content = try? scanner.readTextFile(file) else {
                continue
            }
            for identifier in Self.identifiers(in: String(content.prefix(maxContentCharacters))).prefix(maxIdentifiersPerFile) {
                for phrase in Self.phrases(in: identifier) {
                    consider(
                        phrase,
                        sourcePath: file.relativePath,
                        baseScore: 4,
                        normalizedQuery: normalizedQuery,
                        queryTokens: queryTokens,
                        bestByText: &bestByText
                    )
                }
            }
        }

        return bestByText.values
            .sorted(by: suggestionSort)
            .prefix(min(max(limit, 1), 20))
            .map { $0 }
    }

    private func consider(
        _ rawText: String,
        sourcePath: String,
        baseScore: Double,
        normalizedQuery: String,
        queryTokens: Set<String>,
        bestByText: inout [String: CodebaseQuerySuggestion]
    ) {
        let text = Self.normalizedPhrase(rawText)
        guard text.count >= 2 else { return }
        guard normalizedQuery.isEmpty || text != normalizedQuery else { return }
        let score = baseScore + Self.matchScore(
            candidate: text,
            normalizedQuery: normalizedQuery,
            queryTokens: queryTokens
        )
        guard normalizedQuery.isEmpty || score > baseScore else { return }

        let candidate = CodebaseQuerySuggestion(text: text, sourcePath: sourcePath, score: score)
        let key = text.lowercased()
        guard let existing = bestByText[key] else {
            bestByText[key] = candidate
            return
        }
        if suggestionSort(candidate, existing) {
            bestByText[key] = candidate
        }
    }

    private static func matchScore(
        candidate: String,
        normalizedQuery: String,
        queryTokens: Set<String>
    ) -> Double {
        guard !normalizedQuery.isEmpty else { return 1 }
        if candidate.hasPrefix(normalizedQuery) {
            return 80
        }
        let candidateTokens = Set(words(in: candidate))
        if !queryTokens.isEmpty, queryTokens.isSubset(of: candidateTokens) {
            return 60 + Double(queryTokens.count)
        }
        let overlap = queryTokens.filter { token in
            candidateTokens.contains(token) || candidate.contains(token)
        }.count
        return overlap > 0 ? Double(overlap) * 20 : 0
    }

    private static func identifiers(in text: String) -> [String] {
        var identifiers: [String] = []
        var current = ""

        func flush() {
            guard current.count >= 2 else {
                current.removeAll(keepingCapacity: true)
                return
            }
            identifiers.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return identifiers
    }

    private static func phrases(in text: String) -> [String] {
        let tokens = words(in: text)
        guard !tokens.isEmpty else { return [] }

        var phrases = [tokens.joined(separator: " ")]
        phrases.append(contentsOf: tokens.filter { $0.count >= 3 })

        var seen = Set<String>()
        return phrases.filter { phrase in
            seen.insert(phrase).inserted
        }
    }

    private static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLowercaseOrDigit = false

        func flush() {
            guard current.count >= 2 else {
                current.removeAll(keepingCapacity: true)
                return
            }
            words.append(current)
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
        return words
    }

    private static func normalizedPhrase(_ text: String) -> String {
        words(in: text).joined(separator: " ")
    }

    private func suggestionSort(_ lhs: CodebaseQuerySuggestion, _ rhs: CodebaseQuerySuggestion) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.text != rhs.text {
            return lhs.text < rhs.text
        }
        return (lhs.sourcePath ?? "") < (rhs.sourcePath ?? "")
    }
}
