// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomeContextLoader.swift - Local git and worktree context loading.

import Foundation

struct ProjectHomeContextLoader: Sendable {
    var gitMetadata: @Sendable (
        _ projectRoot: URL,
        _ fallbackRemote: String?
    ) async -> Result<ProjectHomeGitMetadata, ProjectHomeContextError>
    var worktrees: @Sendable (
        _ projectRoot: URL,
        _ config: WorktreeConfig
    ) async -> Result<[WorktreeManifest.WorktreeEntry], ProjectHomeContextError>

    static let live = ProjectHomeContextLoader(
        gitMetadata: { projectRoot, fallbackRemote in
            await Task.detached(priority: .utility) {
                do {
                    let status = try CodeReviewGitWorkflowService().status(
                        workingDirectory: projectRoot
                    )
                    let remote = liveRemote(projectRoot) ?? fallbackRemote
                    return .success(ProjectHomeGitMetadata(
                        remoteOrigin: remote,
                        statusSummary: status.summary
                    ))
                } catch {
                    return .failure(.gitStatusUnavailable)
                }
            }.value
        },
        worktrees: { projectRoot, config in
            guard config.enabled else { return .success([]) }
            let store = WorktreeManifestStore.forRepo(
                basePath: config.basePath,
                originRepoPath: projectRoot
            )
            do {
                let manifest = try await store.load()
                return .success(manifest.entries.sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.id < rhs.id
                })
            } catch {
                return .failure(.worktreeManifestUnavailable)
            }
        }
    )

    private static func liveRemote(_ projectRoot: URL) -> String? {
        guard let result = try? CodeReviewGit.run(
            workingDirectory: projectRoot,
            arguments: ["config", "--get", "remote.origin.url"]
        ), result.terminationStatus == 0 else {
            return nil
        }
        let remote = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return remote.isEmpty ? nil : remote
    }
}
