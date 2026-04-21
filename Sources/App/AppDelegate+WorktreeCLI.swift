// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+WorktreeCLI.swift - Bridges the four `cocxy worktree-*`
// verbs to the actor-isolated WorktreeService.

import AppKit
import Foundation

extension AppDelegate {

    // MARK: - Service singleton

    /// Process-wide worktree service. A single actor is enough —
    /// concurrent CLI calls serialise at the actor boundary and the
    /// per-repo state lives inside the manifest store, not here.
    static let sharedWorktreeService = WorktreeService()

    // MARK: - CLI entry point (called from the socket queue)

    /// Synchronous bridge the socket handler installs as its
    /// `worktreeCLIProvider`. The socket queue is a background queue,
    /// so blocking it with a semaphore while the async service runs is
    /// safe and matches how other provider closures in this file work.
    nonisolated func handleWorktreeCLIRequest(
        kind: String,
        params: [String: String]
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Worktree dispatch did not complete"]
        ))

        Task.detached { [self] in
            let result = await performWorktreeCLIRequest(kind: kind, params: params)
            box.withValue { $0 = result }
            semaphore.signal()
        }

        semaphore.wait()
        return box.withValue { $0 }
    }

    // MARK: - Async implementation

    /// Async implementation sitting behind the sync bridge above.
    ///
    /// Gathers the tab + config context on the main actor, hands the
    /// work to `WorktreeService`, and applies any resulting Tab
    /// mutations back on the main actor. Returns a `(success, data)`
    /// tuple the handler maps to a `SocketResponse`.
    private func performWorktreeCLIRequest(
        kind: String,
        params: [String: String]
    ) async -> (Bool, [String: String]) {
        let context = await MainActor.run { () -> WorktreeCLIContext? in
            self.buildWorktreeCLIContext()
        }
        guard let context else {
            return (
                false,
                ["error": "No active tab; open a tab before using `cocxy worktree-*`."]
            )
        }

        guard context.config.worktree.enabled else {
            return (
                false,
                ["error": "[worktree].enabled = true must be set in ~/.config/cocxy/config.toml"]
            )
        }

        let store = WorktreeManifestStore.forRepo(
            basePath: context.config.worktree.basePath,
            originRepoPath: context.originRepoPath
        )
        let service = Self.sharedWorktreeService

        do {
            switch kind {
            case "add":
                return try await runAdd(
                    params: params,
                    context: context,
                    store: store,
                    service: service
                )
            case "list":
                return try await runList(
                    context: context,
                    store: store,
                    service: service
                )
            case "remove":
                return try await runRemove(
                    params: params,
                    context: context,
                    store: store,
                    service: service
                )
            case "prune":
                return try await runPrune(
                    context: context,
                    store: store,
                    service: service
                )
            default:
                return (false, ["error": "Unknown worktree subcommand: \(kind)"])
            }
        } catch let error as WorktreeServiceError {
            return (false, ["error": Self.describe(error)])
        } catch {
            return (false, ["error": "Worktree error: \(error.localizedDescription)"])
        }
    }

    // MARK: - Per-verb handlers

    private func runAdd(
        params: [String: String],
        context: WorktreeCLIContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async throws -> (Bool, [String: String]) {
        let agent = params["agent"]?.nilIfEmpty ?? context.detectedAgent
        let entry = try await service.add(
            originRepoPath: context.originRepoPath,
            agent: agent,
            tabID: context.activeTabID,
            config: context.config.worktree,
            store: store
        )

        // Attach the worktree to the active tab so the badge, the
        // project-config fallback, and session restore all see the
        // relationship immediately.
        if let tabID = context.activeTabID {
            await MainActor.run {
                if let controller = self.controllerContainingTab(tabID) {
                    controller.tabManager.updateTab(id: tabID) { tab in
                        tab.worktreeID = entry.id
                        tab.worktreeRoot = entry.path
                        tab.worktreeOriginRepo = context.originRepoPath
                        tab.worktreeBranch = entry.branch
                    }
                    controller.tabBarViewModel?.syncWithManager()
                }
            }
        }

        return (true, [
            "id": entry.id,
            "branch": entry.branch,
            "path": entry.path.path,
            "origin": context.originRepoPath.path,
            "agent": entry.agent ?? ""
        ])
    }

    private func runList(
        context: WorktreeCLIContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async throws -> (Bool, [String: String]) {
        let entries = try await service.list(store: store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(entries)
        let json = String(data: payload, encoding: .utf8) ?? "[]"
        return (true, [
            "entries": json,
            "count": String(entries.count)
        ])
    }

    private func runRemove(
        params: [String: String],
        context: WorktreeCLIContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async throws -> (Bool, [String: String]) {
        guard let id = params["id"]?.nilIfEmpty else {
            return (false, ["error": "worktree-remove requires --id <worktree-id>"])
        }
        let force = Self.parseBool(params["force"]) ?? false

        let removed = try await service.remove(
            id: id,
            force: force,
            originRepoPath: context.originRepoPath,
            store: store
        )

        // Clear any tab still attached to this worktree so the badge
        // disappears and the project-config fallback stops pointing at
        // a deleted tree.
        await MainActor.run {
            for controller in self.allWindowControllers {
                for tab in controller.tabManager.tabs where tab.worktreeID == id {
                    controller.tabManager.updateTab(id: tab.id) { mutated in
                        mutated.worktreeID = nil
                        mutated.worktreeRoot = nil
                        mutated.worktreeOriginRepo = nil
                        mutated.worktreeBranch = nil
                    }
                }
                controller.tabBarViewModel?.syncWithManager()
            }
        }

        return (true, [
            "id": removed.id,
            "branch": removed.branch,
            "status": "removed"
        ])
    }

    private func runPrune(
        context: WorktreeCLIContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async throws -> (Bool, [String: String]) {
        let pruned = try await service.prune(
            originRepoPath: context.originRepoPath,
            store: store
        )
        let prunedIDs = pruned.map(\.id).joined(separator: ",")
        return (true, [
            "pruned": prunedIDs,
            "count": String(pruned.count)
        ])
    }

    // MARK: - Context builder

    /// Snapshot of every piece of state the CLI dispatch needs. Built
    /// on the main actor and then passed into the async side.
    private struct WorktreeCLIContext: Sendable {
        let config: CocxyConfig
        let activeTabID: TabID?
        /// The origin repository the CLI operates against. When the
        /// active tab is already inside a cocxy-managed worktree, this
        /// stays pointed at the original repo so commands like `list`
        /// and `prune` operate on the repo-wide manifest.
        let originRepoPath: URL
        /// Agent name inferred from the active tab's surface state,
        /// used as the `--agent` fallback when the caller does not
        /// supply one.
        let detectedAgent: String?
    }

    @MainActor
    private func buildWorktreeCLIContext() -> WorktreeCLIContext? {
        guard let config = configService?.current else { return nil }

        // Prefer the focused window's active tab so multi-window setups
        // target the tab the user is looking at.
        let controller = focusedWindowController()
        let tab = controller?.tabManager.activeTab

        let origin: URL
        if let worktreeOrigin = tab?.worktreeOriginRepo {
            origin = worktreeOrigin
        } else if let workingDir = tab?.workingDirectory {
            origin = workingDir
        } else {
            origin = FileManager.default.homeDirectoryForCurrentUser
        }

        let detectedAgent: String? = {
            guard let tabID = tab?.id, let controller else { return nil }
            let resolved = controller.resolveSurfaceAgentState(for: tabID)
            return resolved.detectedAgent?.name
        }()

        return WorktreeCLIContext(
            config: config,
            activeTabID: tab?.id,
            originRepoPath: origin,
            detectedAgent: detectedAgent
        )
    }

    // MARK: - Error rendering

    private static func describe(_ error: WorktreeServiceError) -> String {
        switch error {
        case .featureDisabled:
            return "[worktree].enabled = true must be set to use worktrees."
        case .gitUnavailable:
            return "git binary not found on PATH or in the known fallbacks."
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .collisionAfterRetries(let attempts):
            return "Could not allocate a unique worktree id after \(attempts) attempts."
        case .gitCommandFailed(let command, let stderr, let exitCode):
            let cleanStderr = stderr
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "git exited \(exitCode) — \(command)\n\(cleanStderr)"
        case .worktreeNotFound(let id):
            return "Worktree not found: \(id)"
        case .uncommittedChanges(let path, _):
            return "Worktree has uncommitted changes at \(path). Commit or pass --force to override."
        case .manifestError(let underlying):
            return "Manifest error: \(underlying)"
        }
    }

    // MARK: - Param parsing helpers

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let value = raw?.lowercased() else { return nil }
        switch value {
        case "1", "true", "yes", "y": return true
        case "0", "false", "no", "n": return false
        default: return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
