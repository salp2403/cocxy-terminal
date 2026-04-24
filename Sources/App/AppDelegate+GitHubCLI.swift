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
        let enabled = await MainActor.run { () -> Bool in
            self.configService?.current.github.enabled ?? true
        }
        guard enabled else {
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
            return await runGitHubPRs(params: params)
        case "issues":
            return await runGitHubIssues(params: params)
        case "open":
            return await runGitHubOpen()
        case "refresh":
            return await runGitHubRefresh()
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
        params: [String: String]
    ) async -> (Bool, [String: String]) {
        guard let directory = await MainActor.run(body: { self.currentGitHubCLIWorkingDirectory() }) else {
            return (false, ["error": "Open a git repository before listing pull requests."])
        }
        let state = params["state"] ?? "open"
        let limit = params["limit"].flatMap(Int.init) ?? 30
        let includeDrafts = await MainActor.run { () -> Bool in
            self.configService?.current.github.includeDrafts ?? true
        }
        let service = Self.sharedGitHubService
        do {
            let prs = try await service.listPullRequests(
                at: directory,
                state: state,
                limit: limit,
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
        params: [String: String]
    ) async -> (Bool, [String: String]) {
        guard let directory = await MainActor.run(body: { self.currentGitHubCLIWorkingDirectory() }) else {
            return (false, ["error": "Open a git repository before listing issues."])
        }
        let state = params["state"] ?? "open"
        let limit = params["limit"].flatMap(Int.init) ?? 30
        let service = Self.sharedGitHubService
        do {
            let issues = try await service.listIssues(
                at: directory,
                state: state,
                limit: limit
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
