// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+WorktreeProjectActions.swift - Exact-context worktree add and focus actions.

import Foundation
import os.log

extension AppDelegate {
    nonisolated func performProjectWorktreeRequest(
        kind: String,
        projectRoot: URL,
        params: [String: String]
    ) async -> (Bool, [String: String]) {
        let snapshot = await MainActor.run { () -> (WorktreeCLIContext?, String?) in
            var isDirectory: ObjCBool = false
            let root = projectRoot.resolvingSymlinksInPath().standardizedFileURL
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return (nil, "The project folder is unavailable.")
            }
            let descriptor = projectResolver.resolveProject(for: root)
            do {
                let tabID = try activateProject(descriptor.groupingID)
                guard let controller = controllerContainingTab(tabID),
                      let tab = controller.tabManager.tab(for: tabID),
                      let globalConfig = configService?.current else {
                    return (nil, "Project worktree context is unavailable.")
                }
                let config = Self.effectiveWorktreeCLIConfig(
                    globalConfig: globalConfig,
                    projectConfig: tab.projectConfig
                )
                let detectedAgent = controller
                    .resolveSurfaceAgentState(for: tabID)
                    .detectedAgent?.name
                return (WorktreeCLIContext(
                    config: config,
                    activeTabID: tabID,
                    originRepoPath: descriptor.groupingRootURL,
                    detectedAgent: detectedAgent
                ), nil)
            } catch {
                return (nil, "Project worktree context is unavailable.")
            }
        }
        guard var context = snapshot.0 else {
            return (false, ["error": snapshot.1 ?? "Project worktree context is unavailable."])
        }
        guard context.config.worktree.enabled else {
            return (false, ["error": Self.worktreeEnablementErrorMessage])
        }
        context.originRepoPath = Self.resolveOriginRepoRoot(from: context.originRepoPath)
        let store = WorktreeManifestStore.forRepo(
            basePath: context.config.worktree.basePath,
            originRepoPath: context.originRepoPath
        )
        let service = await worktreeServiceSnapshot()

        do {
            switch kind {
            case "add":
                return try await runAdd(
                    params: params,
                    context: context,
                    store: store,
                    service: service
                )
            case "focus":
                return try await runFocus(
                    params: params,
                    context: context,
                    store: store,
                    service: service
                )
            default:
                return (false, ["error": "Unsupported project worktree action: \(kind)"])
            }
        } catch let error as WorktreeServiceError {
            return (false, ["error": Self.describe(error)])
        } catch {
            return (false, ["error": "Worktree action failed."])
        }
    }

    nonisolated func runAdd(
        params: [String: String],
        context: WorktreeCLIContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async throws -> (Bool, [String: String]) {
        let agent = params["agent"]?.nilIfEmpty ?? context.detectedAgent
        let effectiveConfig = Self.worktreeConfig(
            context.config.worktree,
            applyingAddParams: params
        )
        let initialTabID = effectiveConfig.openInNewTab ? nil : context.activeTabID
        let entry = try await service.add(
            originRepoPath: context.originRepoPath,
            agent: agent,
            tabID: initialTabID,
            config: effectiveConfig,
            store: store
        )

        let attachedTabID: TabID? = await MainActor.run {
            if effectiveConfig.openInNewTab {
                let controller = context.activeTabID.flatMap { self.controllerContainingTab($0) }
                    ?? self.focusedWindowController()
                guard let controller else { return nil }
                let newTabID = controller.createTab(workingDirectory: entry.path)
                controller.attachWorktree(
                    entry,
                    originRepo: context.originRepoPath,
                    to: newTabID
                )
                return newTabID
            }

            guard let tabID = context.activeTabID,
                  let controller = self.controllerContainingTab(tabID) else {
                return nil
            }
            controller.attachWorktree(
                entry,
                originRepo: context.originRepoPath,
                to: tabID,
                sendShellDirectoryChange: true
            )
            return tabID
        }

        var finalEntry = entry
        if let attachedTabID, finalEntry.tabID != attachedTabID {
            finalEntry.tabID = attachedTabID
            try await store.upsert(finalEntry)
            let tabStillExists = await MainActor.run {
                self.controllerContainingTab(attachedTabID)?.tabManager.tab(for: attachedTabID) != nil
            }
            if !tabStillExists {
                do {
                    try await store.clearTabBinding(id: finalEntry.id)
                } catch {
                    Self.worktreeLogger.error(
                        "Failed to clear stale worktree tab binding: \(finalEntry.id, privacy: .public)"
                    )
                }
            }
        }

        return (true, [
            "id": finalEntry.id,
            "branch": finalEntry.branch,
            "path": finalEntry.path.path,
            "origin": context.originRepoPath.path,
            "agent": finalEntry.agent ?? "",
            "tab-id": attachedTabID?.rawValue.uuidString ?? "",
        ])
    }

    nonisolated func runFocus(
        params: [String: String],
        context: WorktreeCLIContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async throws -> (Bool, [String: String]) {
        guard let id = params["id"]?.nilIfEmpty else {
            return (false, ["error": "worktree-focus requires --id <worktree-id>"])
        }
        let entries = try await service.list(store: store)
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw WorktreeServiceError.worktreeNotFound(id: id)
        }

        let attachedTabID: TabID? = await MainActor.run {
            if let tabID = entry.tabID,
               let controller = self.controllerContainingTab(tabID),
               controller.focusTab(id: tabID) {
                controller.window?.makeKeyAndOrderFront(nil)
                return tabID
            }
            let controller = context.activeTabID.flatMap { self.controllerContainingTab($0) }
                ?? self.focusedWindowController()
                ?? self.windowController
            guard let controller else { return nil }
            let newTabID = controller.createTab(workingDirectory: entry.path)
            controller.attachWorktree(entry, originRepo: context.originRepoPath, to: newTabID)
            controller.window?.makeKeyAndOrderFront(nil)
            return newTabID
        }
        guard let attachedTabID else {
            return (false, ["error": "No window is available for this worktree."])
        }

        var focusedEntry = entry
        if entry.tabID != attachedTabID {
            focusedEntry.tabID = attachedTabID
            try await store.upsert(focusedEntry)
        }
        return (true, [
            "id": focusedEntry.id,
            "branch": focusedEntry.branch,
            "path": focusedEntry.path.path,
            "origin": context.originRepoPath.path,
            "tab-id": attachedTabID.rawValue.uuidString,
            "status": "focused",
        ])
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
