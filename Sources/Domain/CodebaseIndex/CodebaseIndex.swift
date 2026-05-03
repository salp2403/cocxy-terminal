// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodebaseIndex.swift - Local codebase search orchestration.

import Foundation

enum CodebaseSearchMode: String, Sendable, Equatable {
    case lexicalFallback = "lexical-fallback"
    case semanticOnDevice = "semantic-on-device"
}

enum CodebaseSearchMatchKind: String, Sendable, Equatable {
    case path
    case content
}

struct CodebaseSearchRequest: Sendable, Equatable {
    let query: String
    let scopePath: String?
    let limit: Int

    init(query: String, scopePath: String? = nil, limit: Int = 10) {
        self.query = query
        self.scopePath = scopePath
        self.limit = limit
    }
}

struct CodebaseSearchResult: Sendable, Equatable {
    let path: String
    let line: Int?
    let preview: String
    let score: Double
    let matchKind: CodebaseSearchMatchKind
}

struct CodebaseSearchResponse: Sendable, Equatable {
    let query: String
    let mode: CodebaseSearchMode
    let results: [CodebaseSearchResult]
}

struct CodebaseIndex {
    let workspace: AgentWorkspace
    let maxFileBytes: Int
    let semanticIndex: CodebaseSemanticIndex?

    init(
        workspace: AgentWorkspace,
        maxFileBytes: Int = 1_000_000,
        semanticIndex: CodebaseSemanticIndex? = nil
    ) {
        self.workspace = workspace
        self.maxFileBytes = maxFileBytes
        self.semanticIndex = semanticIndex
    }

    func search(_ request: CodebaseSearchRequest) throws -> CodebaseSearchResponse {
        let normalizedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return CodebaseSearchResponse(query: normalizedQuery, mode: .lexicalFallback, results: [])
        }

        let searchRoot: URL
        if let scopePath = request.scopePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !scopePath.isEmpty {
            searchRoot = try workspace.requireDirectory(scopePath)
        } else {
            searchRoot = workspace.rootURL
        }

        let limit = min(max(request.limit, 1), 50)
        let scopePrefix = workspace.relativePath(for: searchRoot)
        if let semanticIndex,
           let semanticResults = try semanticResults(
               semanticIndex: semanticIndex,
               query: normalizedQuery,
               scopePrefix: scopePrefix,
               limit: limit
           ),
           !semanticResults.isEmpty {
            return CodebaseSearchResponse(
                query: normalizedQuery,
                mode: .semanticOnDevice,
                results: semanticResults
            )
        }

        let searcher = CodebaseLexicalSearcher(
            workspace: workspace,
            maxFileBytes: maxFileBytes
        )
        return CodebaseSearchResponse(
            query: normalizedQuery,
            mode: .lexicalFallback,
            results: try searcher.search(
                query: normalizedQuery,
                startingAt: searchRoot,
                limit: limit
            )
        )
    }

    private func semanticResults(
        semanticIndex: CodebaseSemanticIndex,
        query: String,
        scopePrefix: String,
        limit: Int
    ) throws -> [CodebaseSearchResult]? {
        do {
            return try semanticIndex.search(query: query, scopePath: scopePrefix, limit: limit)
        } catch let error as CodebaseEmbeddingProviderError {
            switch error {
            case .emptyInput, .emptyEmbedding, .providerUnavailable:
                return nil
            case .nonFiniteEmbedding:
                throw error
            }
        } catch {
            throw error
        }
    }
}

private struct CodebaseLexicalSearcher {
    let workspace: AgentWorkspace
    let maxFileBytes: Int

    func search(query: String, startingAt rootURL: URL, limit: Int) throws -> [CodebaseSearchResult] {
        let tokens = CodebaseQueryTokens(query)
        guard !tokens.values.isEmpty else { return [] }

        let scanner = CodebaseIndexFileScanner(workspace: workspace, maxFileBytes: maxFileBytes)
        var bestByPath: [String: CodebaseSearchResult] = [:]

        for file in scanner.regularFiles(startingAt: rootURL) {
            guard let content = try? scanner.readTextFile(file) else {
                continue
            }
            guard let result = bestMatch(
                path: file.relativePath,
                content: content,
                tokens: tokens
            ) else {
                continue
            }
            bestByPath[file.relativePath] = result
        }

        return bestByPath.values
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.path != rhs.path {
                    return lhs.path < rhs.path
                }
                return (lhs.line ?? Int.max) < (rhs.line ?? Int.max)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func bestMatch(
        path: String,
        content: String,
        tokens: CodebaseQueryTokens
    ) -> CodebaseSearchResult? {
        var bestResult: CodebaseSearchResult?
        let pathScore = tokens.score(in: path, weight: 4)

        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let contentScore = tokens.score(in: line, weight: 2)
            let score = pathScore + contentScore
            guard score > 0 else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = CodebaseSearchResult(
                path: path,
                line: index + 1,
                preview: trimmed.isEmpty ? path : trimmed,
                score: score,
                matchKind: contentScore > 0 ? .content : .path
            )
            if bestResult == nil || candidate.score > bestResult!.score {
                bestResult = candidate
            }
        }

        if bestResult == nil, pathScore > 0 {
            bestResult = CodebaseSearchResult(
                path: path,
                line: nil,
                preview: path,
                score: pathScore,
                matchKind: .path
            )
        }
        return bestResult
    }
}

private struct CodebaseQueryTokens {
    let values: [String]

    init(_ query: String) {
        self.values = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func score(in text: String, weight: Double) -> Double {
        let lowercased = text.lowercased()
        return values.reduce(0) { partial, token in
            guard lowercased.contains(token) else { return partial }
            return partial + weight
        }
    }
}
