// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+GitHubCLI.swift - Bridges the five `cocxy github-*` verbs
// to the actor-isolated `GitHubService`. Mirrors the shape of
// `AppDelegate+WorktreeCLI.swift` so both CLI surfaces share one
// audit trail and the socket handler uses a single idiom.

import AppKit
import Foundation
import os.log

extension AppDelegate {

    // MARK: - Service singleton

    nonisolated private static let githubCLILogger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "GitHubCLI"
    )

    /// Process-wide GitHub service. The actor serialises concurrent
    /// calls internally so multi-window and multi-tab usage never
    /// race past each other into the `gh` binary.
    nonisolated static let sharedGitHubService = GitHubService()

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
        params: [String: String]
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
            return await runGitHubPRMerge(params: params, config: githubConfig)
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
                if let repo = try? await service.currentRepo(at: directory) {
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
        guard let controller = focusedWindowController() else { return nil }
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let tab = controller.tabManager.tab(for: tabID) else {
            return nil
        }
        return tab.worktreeRoot ?? tab.workingDirectory
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
    ///   - `delete-branch`(Bool) — defaults to true; set false to keep
    ///                            the branch alive after merge.
    ///   - `subject` (String)   — overrides the merge commit subject.
    ///   - `body` (String)      — overrides the merge commit body.
    nonisolated private func runGitHubPRMerge(
        params: [String: String],
        config: GitHubConfig
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
        guard let directory = await MainActor.run(body: { self.currentGitHubCLIWorkingDirectory() }) else {
            return (false, [
                "error": "Open a git repository before merging a pull request.",
            ])
        }

        // PR number resolution: explicit --pr wins; otherwise gh's
        // own "current branch" default takes over via
        // pullRequestNumber(forBranch:). When no PR matches the
        // current branch, surface a friendly error rather than letting
        // gh fail with a less-actionable stderr.
        let resolvedNumber: Int
        if let raw = params["pr"], let number = Int(raw), number > 0 {
            resolvedNumber = number
        } else {
            // Resolve the branch via git so we can query gh by branch.
            // We piggy-back on `gh pr view` (no branch arg = current
            // branch) by falling through to `gh pr merge` directly,
            // but that path returns less actionable errors. Better to
            // surface the resolution failure here.
            do {
                let branch = (try? await currentBranchForCLIMerge(directory: directory)) ?? ""
                guard !branch.isEmpty else {
                    return (false, [
                        "error": "Could not determine the current branch. Pass --pr <number> explicitly.",
                    ])
                }
                guard let number = try await Self.sharedGitHubService.pullRequestNumber(
                    forBranch: branch,
                    at: directory
                ) else {
                    return (false, [
                        "error": "No open pull request found for branch \(branch). Pass --pr <number> explicitly.",
                    ])
                }
                resolvedNumber = number
            } catch let error as GitHubCLIError {
                return (false, ["error": GitHubPaneViewModel.banner(for: error)])
            } catch {
                return (false, ["error": error.localizedDescription])
            }
        }

        let deleteBranch: Bool
        if let raw = params["delete-branch"]?.lowercased(),
           raw == "false" || raw == "0" || raw == "no" {
            deleteBranch = false
        } else {
            deleteBranch = true
        }

        let request = GitHubMergeRequest(
            pullRequestNumber: resolvedNumber,
            method: method,
            deleteBranch: deleteBranch,
            subject: params["subject"],
            body: params["body"]
        )

        do {
            let merged = try await Self.sharedGitHubService.mergePullRequest(
                request: request,
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
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    /// Returns the current branch of `directory` by shelling out to
    /// `git rev-parse --abbrev-ref HEAD`. Used by the CLI merge verb
    /// when the caller did not pass `--pr`.
    nonisolated private func currentBranchForCLIMerge(
        directory: URL
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "rev-parse", "--abbrev-ref", "HEAD"]
                process.currentDirectoryURL = directory
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
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
}
