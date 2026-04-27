// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubService.swift - Actor that drives `gh` CLI operations for the
// GitHub pane, CLI verbs, and the Create PR integration in Code Review.
//
// The shape mirrors `WorktreeService` so both subprocess orchestrators can
// be audited with the same mental model:
//   - dependencies arrive as `@Sendable` closures so tests can swap the
//     subprocess runner without mutating PATH or spawning real `gh`
//   - every public method is `async` so the caller never blocks the main
//     thread on a subprocess that can take seconds under slow network
//   - the actor boundary serialises concurrent requests inside a single
//     process; rate-limit prevention and state consistency come for free
//   - typed `GitHubCLIError` surfaces flow up verbatim so the UI can
//     render the right banner without re-classifying

import Foundation

// MARK: - GitHubService

/// Actor wrapping every `gh` subprocess invocation.
///
/// The service never caches results — the Pane view model owns cache
/// semantics and invalidation. Keeping the actor stateless also means
/// tests can reuse a single instance across scenarios without reset.
actor GitHubService {

    // MARK: Dependencies (injectable for tests)

    /// Signature of the injected subprocess runner.
    ///
    /// Splitting the runner out of `GitHubCLI.run` keeps the actor
    /// synchronous at the call site while preserving the ability to stub
    /// out the subprocess layer entirely in unit tests. The closure is
    /// sync on purpose: async wrappers around `GitHubCLI.run` would fork
    /// a background task for every call and add yield points we cannot
    /// observe from tests.
    typealias Runner = @Sendable (URL, [String], TimeInterval) throws -> GitHubCLIResult

    private let runner: Runner

    init(runner: @escaping Runner = GitHubService.defaultRunner) {
        self.runner = runner
    }

    /// Production default: route through `GitHubCLI.run` with its built-in
    /// binary resolution, pipe drain, and deadline timeout.
    static let defaultRunner: Runner = { directory, args, timeout in
        try GitHubCLI.run(
            workingDirectory: directory,
            arguments: args,
            timeoutSeconds: timeout
        )
    }

    // MARK: - Auth

    /// Parses `gh auth status` into a typed summary.
    ///
    /// `gh auth status` is the one command that does not expose `--json`,
    /// so we fall back to the combined stdout/stderr text. The exit code
    /// is intentionally ignored: when the user is logged out the command
    /// exits non-zero, but the parser still needs the full output to
    /// classify it as `.loggedOut`.
    func authStatus(timeoutSeconds: TimeInterval = 10.0) async throws -> GitHubAuthStatus {
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let result = try runner(workingDirectory, ["auth", "status"], timeoutSeconds)
        let combined = result.stdout + "\n" + result.stderr
        return GitHubAuthStatusParser.parse(combined)
    }

    // MARK: - Repo discovery

    /// Returns the repository attached to the remote of `directory`, or
    /// throws a typed error the UI can render as a banner.
    func currentRepo(
        at directory: URL,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> GitHubRepo {
        let args = [
            "repo", "view",
            "--json", "owner,name,defaultBranchRef,url,hasIssuesEnabled,isPrivate,isEmpty,description",
        ]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh repo view",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        return try GitHubJSONDecoder.decode(GitHubRepo.self, from: result.stdout)
    }

    // MARK: - Pull requests

    /// Lists open (or closed/merged) pull requests for the repo resolved
    /// at `directory`. The `limit` argument is clamped to `[1, 200]` so
    /// a runaway caller never asks `gh` for the entire history of the
    /// repository.
    ///
    /// `includeDrafts = false` filters the decoded list post-hoc — `gh`
    /// does not expose a "hide drafts" flag.
    func listPullRequests(
        at directory: URL,
        state: String = "open",
        limit: Int = 30,
        includeDrafts: Bool = true,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> [GitHubPullRequest] {
        let clampedLimit = max(1, min(limit, 200))
        let normalizedState = Self.normalizeState(state, allowed: ["open", "closed", "merged", "all"], fallback: "open")
        let args = [
            "pr", "list",
            "--json", "number,title,state,author,headRefName,baseRefName,labels,isDraft,reviewDecision,url,updatedAt",
            "--state", normalizedState,
            "--limit", "\(clampedLimit)",
        ]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh pr list",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        let payload = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try GitHubJSONDecoder.decode(
            [GitHubPullRequest].self,
            from: payload.isEmpty ? "[]" : payload
        )
        return includeDrafts ? decoded : decoded.filter { !$0.isDraft }
    }

    /// Fetches the full metadata for a single PR. Used by
    /// `createPullRequest` so callers receive the fully hydrated model
    /// immediately after creation, and by the UI when it needs the
    /// up-to-date state of the row the user double-clicked.
    func viewPullRequest(
        number: Int,
        at directory: URL,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> GitHubPullRequest {
        let args = [
            "pr", "view", "\(number)",
            "--json", "number,title,state,author,headRefName,baseRefName,labels,isDraft,reviewDecision,url,updatedAt",
        ]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh pr view \(number)",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        return try GitHubJSONDecoder.decode(GitHubPullRequest.self, from: result.stdout)
    }

    // MARK: - Issues

    func listIssues(
        at directory: URL,
        state: String = "open",
        limit: Int = 30,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> [GitHubIssue] {
        let clampedLimit = max(1, min(limit, 200))
        let normalizedState = Self.normalizeState(state, allowed: ["open", "closed", "all"], fallback: "open")
        let args = [
            "issue", "list",
            "--json", "number,title,state,author,labels,comments,url,updatedAt",
            "--state", normalizedState,
            "--limit", "\(clampedLimit)",
        ]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh issue list",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        let payload = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return try GitHubJSONDecoder.decode(
            [GitHubIssue].self,
            from: payload.isEmpty ? "[]" : payload
        )
    }

    // MARK: - Checks

    /// Lists the check runs attached to a pull request. `gh pr checks`
    /// returns one row per check; the `Identifiable` contract on
    /// `GitHubCheck` includes the check link or start timestamp so
    /// duplicate job names from re-runs stay distinct across refreshes.
    func checksForPullRequest(
        number: Int,
        at directory: URL,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> [GitHubCheck] {
        let args = [
            "pr", "checks", "\(number)",
            "--json", "name,state,bucket,link,startedAt,completedAt",
        ]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            // `gh pr checks` exits 8 when there are no checks at all; the
            // stderr for that case is a plain "no checks reported" which
            // we fold to an empty array. Every other non-zero exit maps
            // to the classifier.
            let lower = result.stderr.lowercased()
            if result.terminationStatus == 8 || lower.contains("no checks reported") {
                return []
            }
            throw GitHubCLI.classifyError(
                command: "gh pr checks \(number)",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        let payload = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return try GitHubJSONDecoder.decode(
            [GitHubCheck].self,
            from: payload.isEmpty ? "[]" : payload
        )
    }

    // MARK: - Create PR

    /// Creates a pull request from the current branch against
    /// `baseBranch` (or the repo default when `nil`). The follow-up
    /// `viewPullRequest` guarantees the returned model is the one
    /// actually visible on GitHub — `gh pr create` only prints the URL.
    ///
    /// Timeout is longer than the read-only operations because
    /// `gh pr create` performs a network round trip plus a follow-up
    /// fetch; 30s matches the timeout used by `gh` itself internally.
    @discardableResult
    func createPullRequest(
        title: String,
        body: String? = nil,
        baseBranch: String? = nil,
        draft: Bool = false,
        at directory: URL,
        timeoutSeconds: TimeInterval = 30.0
    ) async throws -> GitHubPullRequest {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw GitHubCLIError.commandFailed(
                command: "gh pr create",
                stderr: "Pull request title cannot be empty.",
                exitCode: -1
            )
        }

        var args: [String] = ["pr", "create", "--title", trimmedTitle, "--body", body ?? ""]
        if let baseBranch, !baseBranch.isEmpty {
            args.append(contentsOf: ["--base", baseBranch])
        }
        if draft {
            args.append("--draft")
        }

        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh pr create",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Self.extractPullRequestNumber(from: raw) else {
            throw GitHubCLIError.invalidJSON(
                reason: "Could not parse PR number from `gh pr create` output: \(raw.prefix(120))"
            )
        }

        return try await viewPullRequest(
            number: number,
            at: directory,
            timeoutSeconds: timeoutSeconds
        )
    }

    // MARK: - PR detection by branch

    /// Looks up the open pull request whose head branch matches
    /// `branch` and returns its number, or `nil` when no PR exists for
    /// that branch. Used by the Code Review panel so opening a worktree
    /// that already has a PR upstream surfaces the merge button without
    /// the user having to create the PR through Cocxy first.
    ///
    /// `gh pr view <branch>` resolves the PR for the given head ref.
    /// When the branch has no PR, `gh` exits non-zero with a stderr
    /// containing "no pull requests found" — we map that path to `nil`
    /// instead of throwing so the caller can treat "no PR" as a
    /// neutral state rather than an error.
    func pullRequestNumber(
        forBranch branch: String,
        at directory: URL,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> Int? {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let args = ["pr", "view", trimmed, "--json", "number"]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            // "no pull requests found for branch foo" is the canonical
            // stderr when nothing matches. Treat anything containing
            // "no pull request" as the absence of a PR.
            let lower = result.stderr.lowercased()
            if lower.contains("no pull request") || lower.contains("not found") {
                return nil
            }
            throw GitHubCLI.classifyError(
                command: "gh pr view \(trimmed)",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }

        struct NumberResponse: Decodable { let number: Int }
        let payload = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }
        let response = try GitHubJSONDecoder.decode(NumberResponse.self, from: payload)
        return response.number
    }

    // MARK: - Mergeability

    /// Fetches a typed snapshot describing whether a pull request can
    /// be merged right now. The view layer uses the snapshot to enable
    /// or disable the merge button and to render an explanatory chip
    /// before the user clicks. Network round-trip is one `gh pr view`
    /// invocation; cost is comparable to `viewPullRequest` and we use
    /// the same default timeout.
    ///
    /// The decoder is tolerant of missing fields — older `gh` releases
    /// occasionally drop `mergeStateStatus` or `statusCheckRollup`,
    /// and the missing values collapse to `.unknown` / "no checks
    /// configured" which keeps the UI useful instead of failing the
    /// whole query.
    func pullRequestMergeability(
        number: Int,
        at directory: URL,
        timeoutSeconds: TimeInterval = 10.0
    ) async throws -> GitHubMergeability {
        let args = [
            "pr", "view", "\(number)",
            "--json", "number,state,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup",
        ]
        let result = try runner(directory, args, timeoutSeconds)
        if result.terminationStatus != 0 {
            throw GitHubCLI.classifyError(
                command: "gh pr view \(number) --json mergeable,mergeStateStatus",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
        return try GitHubJSONDecoder.decode(GitHubMergeability.self, from: result.stdout)
    }

    // MARK: - Merge

    /// Merges a pull request using one of the three documented
    /// strategies. The follow-up `viewPullRequest` returns the fully
    /// hydrated model so the caller can refresh its UI without an
    /// extra round trip — `gh pr merge` itself only prints a short
    /// status line.
    ///
    /// Failure modes are classified into `GitHubMergeError` cases via
    /// `GitHubMergeError.classify` so the view layer can render a
    /// banner with concrete guidance (resolve conflicts, wait for
    /// checks, request review) instead of dumping raw stderr.
    ///
    /// Timeout defaults to 60s — `gh pr merge` can block for tens of
    /// seconds when the upstream is rerunning required checks during
    /// the merge attempt. The timeout is generous on purpose so the
    /// user does not get a "timeout" banner on a flow that would have
    /// succeeded a heartbeat later.
    @discardableResult
    func mergePullRequest(
        request: GitHubMergeRequest,
        at directory: URL,
        timeoutSeconds: TimeInterval = 60.0
    ) async throws -> GitHubPullRequest {
        var args: [String] = [
            "pr", "merge", "\(request.pullRequestNumber)",
            request.method.ghFlag,
        ]
        if request.deleteBranch {
            args.append("--delete-branch")
        }
        if let subject = request.subject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            args.append(contentsOf: ["--subject", subject])
        }
        if let body = request.body, !body.isEmpty {
            args.append(contentsOf: ["--body", body])
        }

        let result = try runner(directory, args, timeoutSeconds)

        // `gh pr merge` sometimes exits 0 while printing "will be
        // automatically merged" when the queue requires it. Treat that
        // as a typed outcome so the UI can banner it correctly instead
        // of pretending the merge already happened.
        let combined = result.stderr + "\n" + result.stdout
        let lower = combined.lowercased()
        if result.terminationStatus == 0 {
            if lower.contains("will be automatically merged") ||
               lower.contains("auto-merge has been enabled") {
                throw GitHubMergeError.autoMergeEnabled
            }
        } else {
            if let merged = try? await viewPullRequest(
                number: request.pullRequestNumber,
                at: directory,
                timeoutSeconds: timeoutSeconds
            ), merged.state == .merged {
                if request.deleteBranch {
                    try deleteHeadBranchIfStillPresent(
                        for: merged,
                        at: directory,
                        timeoutSeconds: timeoutSeconds
                    )
                }
                return merged
            }

            throw GitHubMergeError.classify(
                stderr: combined,
                exitCode: result.terminationStatus,
                pullRequestNumber: request.pullRequestNumber
            )
        }

        // Hydrate the post-merge state so the caller can refresh UI
        // without a second user-visible spinner.
        let merged = try await viewPullRequest(
            number: request.pullRequestNumber,
            at: directory,
            timeoutSeconds: timeoutSeconds
        )

        if request.deleteBranch {
            try deleteHeadBranchIfStillPresent(
                for: merged,
                at: directory,
                timeoutSeconds: timeoutSeconds
            )
        }

        return merged
    }

    // MARK: - Helpers

    /// Pulls the numeric PR id out of the URL `gh pr create` prints.
    ///
    /// Expected shape: `https://github.com/<owner>/<repo>/pull/42`. Any
    /// trailing query or anchor is ignored. The helper is exposed as
    /// `internal static` so the test suite can exercise the edge cases
    /// directly without instantiating the actor.
    static func extractPullRequestNumber(from url: String) -> Int? {
        // Strip any trailing whitespace/newlines first; `gh` occasionally
        // appends extra lines about GitHub App status.
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = trimmed.split(whereSeparator: { $0.isWhitespace })
        for candidate in candidates.reversed() {
            guard let components = URL(string: String(candidate))?.pathComponents,
                  let pullIndex = components.firstIndex(of: "pull"),
                  pullIndex + 1 < components.count,
                  let number = Int(components[pullIndex + 1]) else {
                continue
            }
            return number
        }
        return nil
    }

    /// Explicitly deletes a same-repository PR head branch after a
    /// successful merge when the user requested "Delete branch after
    /// merge".
    ///
    /// `gh pr merge --delete-branch` does not reliably delete the
    /// remote branch when Cocxy runs the merge from a checked-out
    /// linked worktree. The merge itself succeeds, but the remote head
    /// can remain. This helper closes that gap by asking GitHub's git
    /// refs API to delete `heads/<headRefName>` after the PR is already
    /// merged. Missing refs are treated as success so the path stays
    /// idempotent when `gh` did delete the branch on its own.
    private func deleteHeadBranchIfStillPresent(
        for merged: GitHubPullRequest,
        at directory: URL,
        timeoutSeconds: TimeInterval
    ) throws {
        let headRef = merged.headRefName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseRef = merged.baseRefName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard merged.state == .merged,
              !headRef.isEmpty,
              headRef != baseRef else {
            return
        }

        struct RepoIdentity: Decodable {
            struct Owner: Decodable { let login: String }
            let owner: Owner
            let name: String
        }

        let repoResult = try runner(
            directory,
            ["repo", "view", "--json", "owner,name"],
            timeoutSeconds
        )
        guard repoResult.terminationStatus == 0 else {
            return
        }
        let repo = try GitHubJSONDecoder.decode(RepoIdentity.self, from: repoResult.stdout)

        let encodedRef = headRef.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? headRef
        let endpoint = "repos/\(repo.owner.login)/\(repo.name)/git/refs/heads/\(encodedRef)"
        let deleteResult = try runner(
            directory,
            ["api", "-X", "DELETE", endpoint],
            timeoutSeconds
        )
        if deleteResult.terminationStatus == 0 {
            return
        }

        let lower = (deleteResult.stderr + "\n" + deleteResult.stdout).lowercased()
        if lower.contains("reference does not exist") ||
           lower.contains("not found") ||
           lower.contains("no ref found") {
            return
        }
    }

    /// Normalises a user-supplied state string to a value the `gh`
    /// subcommand accepts. Unknown values fall back to `fallback` so a
    /// typo in config never crashes the helper.
    private static func normalizeState(
        _ state: String,
        allowed: [String],
        fallback: String
    ) -> String {
        let lower = state.lowercased()
        return allowed.contains(lower) ? lower : fallback
    }
}
