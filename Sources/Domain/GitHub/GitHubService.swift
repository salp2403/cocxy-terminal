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
    /// `GitHubCheck` is keyed on the check name so the UI dedups rows
    /// across refreshes.
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
