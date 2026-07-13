// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+GitHubCLI.swift - Bridges the five `cocxy github-*` verbs
// to the actor-isolated `GitHubService`. Mirrors the shape of
// `AppDelegate+WorktreeCLI.swift` so both CLI surfaces share one
// audit trail and the socket handler uses a single idiom.

import AppKit
import Darwin
import Foundation
import os.log

extension AppDelegate {
    nonisolated private static let githubStatusRepoTimeoutSeconds: TimeInterval = 2.0

    private struct GitHubCLITabSnapshot: Equatable, Sendable {
        let windowControllerIdentifier: ObjectIdentifier
        let tabID: TabID
        let directory: URL

        func authorizationContext(
            repository: GitHubRepositoryAuthority
        ) -> GitHubSocketMutationContext {
            GitHubSocketMutationContext(
                windowControllerIdentifier: windowControllerIdentifier,
                tabID: tabID,
                workingDirectory: directory,
                repository: repository
            )
        }
    }

    // MARK: - Service singleton

    nonisolated private static let githubCLILogger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "GitHubCLI"
    )

    /// Process-wide GitHub service. The actor serialises concurrent
    /// calls internally so multi-window and multi-tab usage never
    /// race past each other into the `gh` binary.
    nonisolated static let sharedGitHubService = GitHubService()

    /// Process-wide post-merge aftermath service (v0.1.87). Drives the
    /// optional `git fetch` + `git pull --ff-only` sync after a
    /// successful in-panel PR merge. Shared with both surfaces (Code
    /// Review panel + GitHub pane) so concurrent merges never run two
    /// `git pull` invocations against the same checkout.
    nonisolated static let sharedGitMergeAftermathService = GitMergeAftermathService()

    // MARK: - Sync bridge called from the socket queue

    /// Entry point the socket handler uses for every `github-*` verb.
    /// The socket queue is already a background queue so blocking it
    /// on a semaphore while the async service runs is safe.
    nonisolated func handleGitHubCLIRequest(
        kind: String,
        params: [String: String]
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "GitHub dispatch did not complete"]
        ))

        Task.detached { [self] in
            let result = await performGitHubCLIRequest(kind: kind, params: params)
            box.withValue { $0 = result }
            semaphore.signal()
        }

        semaphore.wait()
        return box.withValue { $0 }
    }

    // MARK: - Async implementation

    /// Async side of the sync bridge. Resolves the working directory
    /// on the main actor, hands the work to the shared service, and
    /// marshals typed `GitHubCLIError` cases back into the `(Bool,
    /// [String: String])` tuple the socket expects.
    nonisolated func performGitHubCLIRequest(
        kind: String,
        params: [String: String],
        serviceOverride: GitHubService? = nil
    ) async -> (Bool, [String: String]) {
        // Gate: honour the master toggle so `cocxy github-*` never
        // invokes `gh` when the user disabled the pane.
        let githubConfig = await MainActor.run { () -> GitHubConfig in
            self.currentGitHubCLIConfig()
        }
        guard githubConfig.enabled else {
            return (
                false,
                [
                    "error": "GitHub pane is disabled. Enable [github].enabled in config.toml or open Preferences > GitHub.",
                ]
            )
        }

        let mutationService = serviceOverride ?? Self.sharedGitHubService
        switch kind {
        case "status":
            return await runGitHubStatus()
        case "prs":
            return await runGitHubPRs(params: params, config: githubConfig)
        case "issues":
            return await runGitHubIssues(params: params, config: githubConfig)
        case "open":
            return await runGitHubOpen()
        case "refresh":
            return await runGitHubRefresh()
        case "pr-merge":
            return await runGitHubPRMerge(
                params: params,
                config: githubConfig,
                service: mutationService
            )
        case "review-approve":
            return await runGitHubPRReview(
                params: params,
                action: .approve,
                service: mutationService
            )
        case "review-request-changes":
            return await runGitHubPRReview(
                params: params,
                action: .requestChanges,
                service: mutationService
            )
        default:
            return (false, ["error": "Unknown github subcommand: \(kind)"])
        }
    }

    // MARK: - Verbs

    /// `cocxy github-status` — combined auth + repo summary. Returns
    /// a minimal JSON payload under `data["status"]` so the CLI can
    /// pretty-print it or pipe it into `jq`.
    nonisolated private func runGitHubStatus() async -> (Bool, [String: String]) {
        let service = Self.sharedGitHubService
        do {
            let auth = try await service.authStatus()
            var result: [String: String] = [
                "authenticated": auth.isAuthenticated ? "true" : "false",
                "host": auth.host,
            ]
            if let login = auth.login { result["login"] = login }
            if !auth.scopes.isEmpty {
                result["scopes"] = auth.scopes.joined(separator: ",")
            }

            if let directory = await MainActor.run(body: { self.currentGitHubCLIWorkingDirectory() }) {
                if let repo = try? await service.currentRepo(
                    at: directory,
                    timeoutSeconds: Self.githubStatusRepoTimeoutSeconds
                ) {
                    result["repo"] = repo.fullName
                    result["default_branch"] = repo.defaultBranch
                    result["url"] = repo.url.absoluteString
                }
            }

            return (true, result)
        } catch let error as GitHubCLIError {
            return (false, ["error": GitHubPaneViewModel.banner(for: error)])
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    /// `cocxy github-prs` — array of pull requests. Accepts optional
    /// `--state` and `--limit`. Returns JSON under `data["prs"]`.
    nonisolated private func runGitHubPRs(
        params: [String: String],
        config: GitHubConfig
    ) async -> (Bool, [String: String]) {
        guard let directory = await MainActor.run(body: { self.currentGitHubCLIWorkingDirectory() }) else {
            return (false, ["error": "Open a git repository before listing pull requests."])
        }
        let options = Self.githubListOptions(
            params: params,
            config: config,
            allowedStates: ["open", "closed", "merged", "all"]
        )
        let includeDrafts = config.includeDrafts
        let service = Self.sharedGitHubService
        do {
            let prs = try await service.listPullRequests(
                at: directory,
                state: options.state,
                limit: options.limit,
                includeDrafts: includeDrafts
            )
            return (true, ["prs": encodeJSONArray(prs)])
        } catch let error as GitHubCLIError {
            return (false, ["error": GitHubPaneViewModel.banner(for: error)])
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    /// `cocxy github-issues` — array of issues. Returns JSON under
    /// `data["issues"]`.
    nonisolated private func runGitHubIssues(
        params: [String: String],
        config: GitHubConfig
    ) async -> (Bool, [String: String]) {
        guard let directory = await MainActor.run(body: { self.currentGitHubCLIWorkingDirectory() }) else {
            return (false, ["error": "Open a git repository before listing issues."])
        }
        let options = Self.githubListOptions(
            params: params,
            config: config,
            allowedStates: ["open", "closed", "all"]
        )
        let service = Self.sharedGitHubService
        do {
            let issues = try await service.listIssues(
                at: directory,
                state: options.state,
                limit: options.limit
            )
            return (true, ["issues": encodeJSONArray(issues)])
        } catch let error as GitHubCLIError {
            return (false, ["error": GitHubPaneViewModel.banner(for: error)])
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    /// `cocxy github-open` — toggle the pane overlay on the focused
    /// window. No-op with a helpful message if no window is active.
    nonisolated private func runGitHubOpen() async -> (Bool, [String: String]) {
        let stateAfter: String = await MainActor.run {
            guard let controller = self.focusedWindowController() else { return "" }
            controller.toggleGitHubPane()
            return controller.isGitHubPaneVisible ? "opened" : "closed"
        }
        if stateAfter.isEmpty {
            return (false, ["error": "No active Cocxy window."])
        }
        return (true, ["state": "GitHub pane \(stateAfter)."])
    }

    /// `cocxy github-refresh` — forces a refresh of the pane data on
    /// the focused window. Silent no-op if the pane view model has
    /// not been constructed yet (i.e. the pane was never opened).
    nonisolated private func runGitHubRefresh() async -> (Bool, [String: String]) {
        let refreshed: Bool = await MainActor.run {
            guard let viewModel = self.focusedWindowController()?.gitHubPaneViewModel else {
                return false
            }
            viewModel.refresh()
            return true
        }
        if !refreshed {
            return (false, ["error": "GitHub pane has not been opened in the active window yet."])
        }
        return (true, ["state": "GitHub pane refreshed."])
    }

    // MARK: - Main-actor helpers

    /// Resolves the working directory the CLI request should use.
    /// Prefers the active tab's worktree root so `gh` resolves the
    /// origin repo correctly when the user is inside a
    /// cocxy-managed worktree.
    @MainActor
    func currentGitHubCLIWorkingDirectory() -> URL? {
        currentGitHubCLITabSnapshot()?.directory
    }

    @MainActor
    private func currentGitHubCLITabSnapshot() -> GitHubCLITabSnapshot? {
        guard let controller = focusedWindowController() else { return nil }
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let tab = controller.tabManager.tab(for: tabID) else {
            return nil
        }
        return GitHubCLITabSnapshot(
            windowControllerIdentifier: ObjectIdentifier(controller),
            tabID: tabID,
            directory: (tab.worktreeRoot ?? tab.workingDirectory).standardizedFileURL
        )
    }

    @MainActor
    private func authorizeGitHubSocketMutation(
        _ request: GitHubSocketMutationAuthorizationRequest
    ) -> GitHubSocketMutationAuthorizationGrant? {
        guard let controller = focusedWindowController(),
              ObjectIdentifier(controller) == request.context.windowControllerIdentifier else {
            return nil
        }
        return controller.authorizeGitHubSocketMutation(request)
    }

    /// Resolves the effective GitHub config for the focused tab.
    /// Project-level `.cocxy.toml` overrides should affect the CLI
    /// exactly the same way they affect the side pane, while global-only
    /// controls such as refresh interval and max rows remain global.
    @MainActor
    func currentGitHubCLIConfig() -> GitHubConfig {
        let globalConfig = configService?.current ?? .defaults
        guard let controller = focusedWindowController(),
              let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let projectConfig = controller.tabManager.tab(for: tabID)?.projectConfig else {
            return globalConfig.github
        }
        return Self.effectiveGitHubCLIConfig(
            globalConfig: globalConfig,
            projectConfig: projectConfig
        ).github
    }

    nonisolated static func effectiveGitHubCLIConfig(
        globalConfig: CocxyConfig,
        projectConfig: ProjectConfig?
    ) -> CocxyConfig {
        guard let projectConfig else { return globalConfig }
        return globalConfig.applying(projectOverrides: projectConfig)
    }

    nonisolated static func githubListOptions(
        params: [String: String],
        config: GitHubConfig,
        allowedStates: [String]
    ) -> (state: String, limit: Int) {
        let rawState = params["state"] ?? config.defaultState
        let state = GitHubPaneViewModel.clampedState(rawState, allowed: allowedStates)
        let limit = params["limit"].flatMap(Int.init) ?? config.maxItems
        return (state, limit)
    }

    // MARK: - PR Merge (v0.1.86)

    /// `cocxy github-pr-merge` — merges a pull request via gh. Honours
    /// the `[github].merge-enabled` master flag so a single config
    /// toggle disables every surface (pane row, review panel, CLI).
    ///
    /// Required parameter: `method` ∈ {squash, merge, rebase}.
    /// Optional parameters:
    ///   - `pr` (Int)           — PR number; without it gh resolves the
    ///                            PR for the current branch.
    ///   - `delete-branch`(Bool) — defaults to false; opt in explicitly.
    ///   - `subject` (String)   — overrides the merge commit subject.
    ///   - `body` (String)      — overrides the merge commit body.
    nonisolated private func runGitHubPRMerge(
        params: [String: String],
        config: GitHubConfig,
        service: GitHubService
    ) async -> (Bool, [String: String]) {
        guard config.mergeEnabled else {
            return (false, [
                "error": "Pull request merge is disabled. Set [github].merge-enabled = true in config.toml.",
            ])
        }
        guard let methodRaw = params["method"]?.lowercased(),
              let method = GitHubMergeMethod(rawValue: methodRaw) else {
            return (false, [
                "error": "Pass exactly one strategy: --squash, --merge, or --rebase.",
            ])
        }
        guard let tabSnapshot = await MainActor.run(body: { self.currentGitHubCLITabSnapshot() }) else {
            return (false, [
                "error": "Open a git repository before merging a pull request.",
            ])
        }
        let directory = tabSnapshot.directory

        let deleteBranch: Bool
        if let raw = params["delete-branch"] {
            guard let parsed = Self.parseGitHubSocketBoolean(raw) else {
                return (false, ["error": "Invalid --delete-branch value."])
            }
            deleteBranch = parsed
        } else {
            deleteBranch = false
        }

        do {
            let repository = try await service.currentRepo(at: directory)
            guard let repositoryAuthority = GitHubRepositoryAuthority(repository: repository) else {
                return (false, ["error": "Could not bind the active GitHub repository."])
            }

            let resolvedNumber: Int
            if let raw = params["pr"] {
                guard let number = Int(raw), number > 0 else {
                    return (false, ["error": "--pr expects a positive integer."])
                }
                resolvedNumber = number
            } else {
                let branch = (try? await Self.currentBranchForCLIMerge(directory: directory)) ?? ""
                guard !branch.isEmpty else {
                    return (false, [
                        "error": "Could not determine the current branch. Pass --pr <number> explicitly.",
                    ])
                }
                guard let number = try await service.pullRequestNumber(
                    forBranch: branch,
                    at: directory,
                    repository: repositoryAuthority
                ) else {
                    return (false, [
                        "error": "No open pull request found for branch \(branch). Pass --pr <number> explicitly.",
                    ])
                }
                resolvedNumber = number
            }

            let mergeRequest = GitHubMergeRequest(
                pullRequestNumber: resolvedNumber,
                method: method,
                deleteBranch: deleteBranch,
                subject: GitHubSocketMutationSecurity.normalizedText(params["subject"]),
                body: GitHubSocketMutationSecurity.normalizedText(params["body"])
            )
            let authorizationRequest = GitHubSocketMutationAuthorizationRequest(
                intent: .merge(mergeRequest),
                context: tabSnapshot.authorizationContext(
                    repository: repositoryAuthority
                )
            )
            guard let grant = await MainActor.run(body: {
                self.authorizeGitHubSocketMutation(authorizationRequest)
            }) else {
                return (false, ["error": "GitHub merge was not approved."])
            }
            guard await MainActor.run(body: { self.currentGitHubCLITabSnapshot() }) == tabSnapshot else {
                return (false, ["error": "The active tab changed after approval; no merge was performed."])
            }

            let merged = try await service.mergePullRequest(
                authorizedBy: grant,
                at: directory
            )
            return (true, [
                "merged": encodeJSON(merged),
                "summary": "Merged PR #\(merged.number) via \(method.displayName).",
            ])
        } catch let error as GitHubMergeError {
            return (false, ["error": error.errorDescription ?? "Pull request could not be merged."])
        } catch let error as GitHubCLIError {
            return (false, ["error": GitHubPaneViewModel.banner(for: error)])
        } catch let error as GitHubSocketMutationAuthorizationError {
            return (false, ["error": error.localizedDescription])
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    /// Returns the current branch of `directory` by shelling out to
    /// `git rev-parse --abbrev-ref HEAD`. Used by the CLI merge verb
    /// when the caller did not pass `--pr`.
    nonisolated static func currentBranchForCLIMerge(
        directory: URL,
        timeoutSeconds: TimeInterval = 5,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String] = ["git", "rev-parse", "--abbrev-ref", "HEAD"]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
                    continuation.resume(
                        throwing: GitHubCLIError.timeout(seconds: timeoutSeconds)
                    )
                    return
                }
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.currentDirectoryURL = directory
                let stdout = Pipe()
                process.standardOutput = stdout
                // `git rev-parse` emits one bounded line on stdout. Discard
                // stderr so an unexpected child cannot fill an unread pipe
                // and prevent the deadline from terminating the process.
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let completed = DispatchSemaphore(value: 0)
                    DispatchQueue.global(qos: .userInitiated).async {
                        process.waitUntilExit()
                        completed.signal()
                    }
                    let timeout = DispatchTimeInterval.milliseconds(
                        max(1, Int(timeoutSeconds * 1_000))
                    )
                    if completed.wait(timeout: .now() + timeout) == .timedOut {
                        process.terminate()
                        _ = completed.wait(timeout: .now() + .milliseconds(500))
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                            _ = completed.wait(timeout: .now() + .milliseconds(200))
                        }
                        continuation.resume(
                            throwing: GitHubCLIError.timeout(seconds: timeoutSeconds)
                        )
                        return
                    }
                    guard process.terminationStatus == 0 else {
                        continuation.resume(returning: "")
                        return
                    }
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let branch = String(decoding: data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: branch)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - PR Review (P5 CLI)

    /// `cocxy review approve/request-changes` — submits a GitHub PR
    /// review from the active tab's repository. This intentionally
    /// lives beside the GitHub CLI bridge because the operation is a
    /// `gh pr review` call even though the public command is grouped
    /// under `review` for user ergonomics.
    nonisolated private func runGitHubPRReview(
        params: [String: String],
        action: GitHubPullRequestReviewAction,
        service: GitHubService
    ) async -> (Bool, [String: String]) {
        guard let tabSnapshot = await MainActor.run(body: { self.currentGitHubCLITabSnapshot() }) else {
            return (false, [
                "error": "Open a git repository before submitting a pull request review.",
            ])
        }
        let directory = tabSnapshot.directory

        do {
            let repository = try await service.currentRepo(at: directory)
            guard let repositoryAuthority = GitHubRepositoryAuthority(repository: repository) else {
                return (false, ["error": "Could not bind the active GitHub repository."])
            }

            let prNumber: Int
            if let raw = params["pr"] {
                guard let number = Int(raw), number > 0 else {
                    return (false, ["error": "--pr expects a positive integer."])
                }
                prNumber = number
            } else {
                let branch = (try? await Self.currentBranchForCLIMerge(directory: directory)) ?? ""
                guard !branch.isEmpty else {
                    return (false, [
                        "error": "Could not determine the current branch. Pass --pr <number> explicitly.",
                    ])
                }
                guard let number = try await service.pullRequestNumber(
                    forBranch: branch,
                    at: directory,
                    repository: repositoryAuthority
                ) else {
                    return (false, [
                        "error": "No open pull request found for branch \(branch). Pass --pr <number> explicitly.",
                    ])
                }
                prNumber = number
            }

            let authorizationRequest = GitHubSocketMutationAuthorizationRequest(
                intent: .review(
                    pullRequestNumber: prNumber,
                    action: action,
                    body: GitHubSocketMutationSecurity.normalizedText(params["body"])
                ),
                context: tabSnapshot.authorizationContext(
                    repository: repositoryAuthority
                )
            )
            guard let grant = await MainActor.run(body: {
                self.authorizeGitHubSocketMutation(authorizationRequest)
            }) else {
                return (false, ["error": "GitHub review was not approved."])
            }
            guard await MainActor.run(body: { self.currentGitHubCLITabSnapshot() }) == tabSnapshot else {
                return (false, ["error": "The active tab changed after approval; no review was submitted."])
            }

            try await service.reviewPullRequest(
                authorizedBy: grant,
                at: directory
            )
            return (true, [
                "summary": "Review \(action.displayName) for PR #\(prNumber).",
            ])
        } catch let error as GitHubCLIError {
            return (false, ["error": GitHubPaneViewModel.banner(for: error)])
        } catch let error as GitHubSocketMutationAuthorizationError {
            return (false, ["error": error.localizedDescription])
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    /// Encodes a single `Encodable` value into a UTF-8 JSON string.
    /// Returns `"{}"` on any encoder failure so the socket response
    /// stays valid JSON.
    nonisolated private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        } catch {
            Self.githubCLILogger.error(
                "Failed to encode merged PR payload: \(String(describing: error), privacy: .private)"
            )
            return "{}"
        }
    }

    // MARK: - JSON encoding helper

    /// Encodes an array of `Encodable` values into a UTF-8 JSON
    /// string the CLI can pass through unchanged. Returns `"[]"` on
    /// any encoder failure so the socket response stays valid JSON.
    nonisolated private func encodeJSONArray<T: Encodable>(_ values: [T]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(values)
            return String(decoding: data, as: UTF8.self)
        } catch {
            Self.githubCLILogger.error(
                "Failed to encode GitHub CLI payload: \(String(describing: error), privacy: .private)"
            )
            return "[]"
        }
    }

    nonisolated private static func parseGitHubSocketBoolean(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y": return true
        case "0", "false", "no", "n": return false
        default: return nil
        }
    }
}
