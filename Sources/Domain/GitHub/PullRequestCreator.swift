// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PullRequestCreator.swift - Dedicated gh pr create wrapper for Source Control UI.

import Foundation

struct PullRequestCreateRequest: Equatable, Sendable {
    let title: String
    let body: String?
    let baseBranch: String?
    let reviewers: [String]
    let draft: Bool

    init(
        title: String,
        body: String? = nil,
        baseBranch: String? = nil,
        reviewers: [String] = [],
        draft: Bool = false
    ) {
        self.title = title
        self.body = body
        self.baseBranch = baseBranch
        self.reviewers = reviewers
        self.draft = draft
    }
}

struct PullRequestCreatePlan: Equatable, Sendable {
    let arguments: [String]
}

struct PullRequestCreator {
    private let runner: GitHubService.Runner

    init(runner: @escaping GitHubService.Runner = PullRequestCreator.defaultRunner) {
        self.runner = runner
    }

    static func plan(for request: PullRequestCreateRequest) throws -> PullRequestCreatePlan {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw GitHubCLIError.commandFailed(
                command: "gh pr create",
                stderr: "Pull request title cannot be empty.",
                exitCode: -1
            )
        }

        var args = [
            "pr", "create",
            "--title", title,
            "--body", request.body ?? "",
        ]

        if let baseBranch = request.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !baseBranch.isEmpty {
            args.append(contentsOf: ["--base", baseBranch])
        }
        if request.draft {
            args.append("--draft")
        }

        var seenReviewers = Set<String>()
        for reviewer in request.reviewers {
            let normalized = reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  seenReviewers.insert(normalized.lowercased()).inserted else {
                continue
            }
            args.append(contentsOf: ["--reviewer", normalized])
        }

        return PullRequestCreatePlan(arguments: args)
    }

    func create(
        _ request: PullRequestCreateRequest,
        at workingDirectory: URL,
        timeoutSeconds: TimeInterval = 30.0
    ) async throws -> GitHubPullRequest {
        let plan = try Self.plan(for: request)
        let createResult = try runner(workingDirectory, plan.arguments, timeoutSeconds)
        if createResult.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh pr create",
                stderr: createResult.stderr,
                exitCode: createResult.terminationStatus
            )
        }

        let raw = createResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = GitHubService.extractPullRequestNumber(from: raw) else {
            throw GitHubCLIError.invalidJSON(
                reason: "Could not parse PR number from `gh pr create` output: \(raw.prefix(120))"
            )
        }

        let viewArgs = [
            "pr", "view", "\(number)",
            "--json", "number,title,state,author,headRefName,baseRefName,labels,isDraft,reviewDecision,url,updatedAt",
        ]
        let viewResult = try runner(workingDirectory, viewArgs, timeoutSeconds)
        if viewResult.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh pr view \(number)",
                stderr: viewResult.stderr,
                exitCode: viewResult.terminationStatus
            )
        }
        return try GitHubJSONDecoder.decode(GitHubPullRequest.self, from: viewResult.stdout)
    }

    private static let defaultRunner: GitHubService.Runner = { directory, args, timeout in
        try GitHubCLI.run(workingDirectory: directory, arguments: args, timeoutSeconds: timeout)
    }
}
