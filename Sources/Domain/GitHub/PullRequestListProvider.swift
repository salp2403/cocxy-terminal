// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PullRequestListProvider.swift - Filterable pull-request list provider.

import Foundation

enum PullRequestListState: String, Equatable, Sendable, CaseIterable {
    case open
    case closed
    case merged
    case all
}

struct PullRequestListQuery: Equatable, Sendable {
    let state: PullRequestListState
    let searchText: String?
    let authorLogin: String?
    let includeDrafts: Bool
    let limit: Int

    init(
        state: PullRequestListState = .open,
        searchText: String? = nil,
        authorLogin: String? = nil,
        includeDrafts: Bool = true,
        limit: Int = 30
    ) {
        self.state = state
        self.searchText = searchText
        self.authorLogin = authorLogin
        self.includeDrafts = includeDrafts
        self.limit = limit
    }
}

struct PullRequestListProvider {
    typealias Runner = @Sendable (
        URL,
        String,
        Int,
        Bool,
        TimeInterval
    ) async throws -> [GitHubPullRequest]

    private let runner: Runner

    init(runner: @escaping Runner = PullRequestListProvider.defaultRunner) {
        self.runner = runner
    }

    func listPullRequests(
        at workingDirectory: URL,
        query: PullRequestListQuery = PullRequestListQuery(),
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> [GitHubPullRequest] {
        let clampedLimit = max(1, min(query.limit, 200))
        let pullRequests = try await runner(
            workingDirectory,
            query.state.rawValue,
            clampedLimit,
            true,
            timeoutSeconds
        )
        return pullRequests
            .filter { query.includeDrafts || !$0.isDraft }
            .filtered(authorLogin: query.authorLogin)
            .filtered(searchText: query.searchText)
    }

    private static let defaultRunner: Runner = { directory, state, limit, includeDrafts, timeout in
        try await GitHubService().listPullRequests(
            at: directory,
            state: state,
            limit: limit,
            includeDrafts: includeDrafts,
            timeoutSeconds: timeout
        )
    }
}

private extension Array where Element == GitHubPullRequest {
    func filtered(authorLogin: String?) -> [GitHubPullRequest] {
        let needle = authorLogin?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !needle.isEmpty else { return self }
        return filter { $0.author.login.lowercased() == needle }
    }

    func filtered(searchText: String?) -> [GitHubPullRequest] {
        let needle = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !needle.isEmpty else { return self }
        return filter { pullRequest in
            pullRequest.title.lowercased().contains(needle) ||
                pullRequest.headRefName.lowercased().contains(needle) ||
                pullRequest.baseRefName.lowercased().contains(needle) ||
                pullRequest.labels.contains { $0.name.lowercased().contains(needle) } ||
                String(pullRequest.number).contains(needle)
        }
    }
}
