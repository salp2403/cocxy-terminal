// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Scoped worktree cleanup", .serialized)
struct WorktreeScopedCleanupSwiftTestingTests {
    @Test("cleanup removes only explicitly scoped manifest entries")
    func cleanupIsScoped() async throws {
        guard let git = CodeReviewGit.resolveGitExecutableURL() else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-scoped-cleanup-\(UUID().uuidString)", isDirectory: true)
        let origin = root.appendingPathComponent("origin", isDirectory: true)
        let worktrees = root.appendingPathComponent("worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-q", "-b", "main"], at: origin, git: git)
        try runGit(["config", "user.email", "tests@cocxy.dev"], at: origin, git: git)
        try runGit(["config", "user.name", "Cocxy Tests"], at: origin, git: git)
        try "base\n".write(
            to: origin.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], at: origin, git: git)
        try runGit(["commit", "-q", "-m", "base"], at: origin, git: git)

        let config = WorktreeConfig(
            enabled: true,
            basePath: worktrees.path,
            branchTemplate: "task/{agent}/{id}",
            baseRef: "HEAD",
            onClose: .keep,
            openInNewTab: true,
            idLength: 8,
            inheritProjectConfig: true,
            showBadge: true
        )
        let service = WorktreeService(gitExecutableURLProvider: { git })
        let store = WorktreeManifestStore.forRepo(
            basePath: config.basePath,
            originRepoPath: origin
        )
        let selected = try await service.add(
            originRepoPath: origin,
            agent: "selected",
            tabID: nil,
            config: config,
            store: store
        )
        let unrelated = try await service.add(
            originRepoPath: origin,
            agent: "unrelated",
            tabID: nil,
            config: config,
            store: store
        )

        let plan = try await service.mergedCleanupPlan(
            originRepoPath: origin,
            baseRef: "HEAD",
            restrictingToIDs: [selected.id],
            store: store
        )
        #expect(plan.removable.map(\.id) == [selected.id])
        #expect(plan.blocked.isEmpty)
        #expect(plan.skipped.isEmpty)

        let result = try await service.cleanupMergedWorktrees(
            originRepoPath: origin,
            baseRef: "HEAD",
            restrictingToIDs: [selected.id],
            store: store
        )
        #expect(result.removed.map(\.id) == [selected.id])
        #expect(try await service.list(store: store).map(\.id) == [unrelated.id])
        #expect(FileManager.default.fileExists(atPath: unrelated.path.path))
    }

    private func runGit(_ arguments: [String], at directory: URL, git: URL) throws {
        let result = try CodeReviewGit.run(
            workingDirectory: directory,
            arguments: arguments,
            gitExecutableURLOverride: git
        )
        guard result.terminationStatus == 0 else {
            throw WorktreeServiceError.gitCommandFailed(
                command: "git \(arguments.joined(separator: " "))",
                stderr: result.stderr,
                exitCode: result.terminationStatus
            )
        }
    }
}
