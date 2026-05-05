// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodebaseCrossRepositoryIndex.swift - Optional local cross-repository search.

import Foundation

struct CodebaseIndexedWorkspace {
    let id: String
    let displayName: String
    let index: CodebaseIndex

    init(id: String, displayName: String, index: CodebaseIndex) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.index = index
    }
}

struct CodebaseCrossRepositorySearchResult: Sendable, Equatable {
    let workspaceID: String
    let workspaceDisplayName: String
    let mode: CodebaseSearchMode
    let result: CodebaseSearchResult
}

struct CodebaseCrossRepositoryIndex {
    let workspaces: [CodebaseIndexedWorkspace]

    init(workspaces: [CodebaseIndexedWorkspace]) {
        self.workspaces = workspaces
    }

    func search(_ request: CodebaseSearchRequest) throws -> [CodebaseCrossRepositorySearchResult] {
        let limit = min(max(request.limit, 1), 50)
        var merged: [CodebaseCrossRepositorySearchResult] = []

        for workspace in workspaces {
            let response = try workspace.index.search(CodebaseSearchRequest(
                query: request.query,
                scopePath: request.scopePath,
                limit: limit
            ))
            merged.append(contentsOf: response.results.map { result in
                CodebaseCrossRepositorySearchResult(
                    workspaceID: workspace.id,
                    workspaceDisplayName: workspace.displayName,
                    mode: response.mode,
                    result: result
                )
            })
        }

        return merged
            .sorted(by: resultSort)
            .prefix(limit)
            .map { $0 }
    }

    private func resultSort(
        _ lhs: CodebaseCrossRepositorySearchResult,
        _ rhs: CodebaseCrossRepositorySearchResult
    ) -> Bool {
        if lhs.result.score != rhs.result.score {
            return lhs.result.score > rhs.result.score
        }
        if lhs.workspaceID != rhs.workspaceID {
            return lhs.workspaceID < rhs.workspaceID
        }
        if lhs.result.path != rhs.result.path {
            return lhs.result.path < rhs.result.path
        }
        return (lhs.result.line ?? Int.max) < (rhs.result.line ?? Int.max)
    }
}
