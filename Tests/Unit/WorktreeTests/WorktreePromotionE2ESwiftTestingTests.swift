// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Worktree promotion E2E", .serialized)
struct WorktreePromotionE2ESwiftTestingTests {
    @Test("promotion commits, merges, and cleans only the confirmed winner")
    func promotionAndScopedCleanup() async throws {
        guard let git = CodeReviewGit.resolveGitExecutableURL() else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-promotion-e2e-\(UUID().uuidString)", isDirectory: true)
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
        let winner = try await service.add(
            originRepoPath: origin,
            agent: "winner",
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
        try "selected\n".write(
            to: winner.path.appendingPathComponent("Feature.txt"),
            atomically: true,
            encoding: .utf8
        )
        let baseCommit = try await service.revision("HEAD", at: origin)

        try await service.validatePromotionOrigin(
            originRepoPath: origin,
            expectedBaseCommit: baseCommit
        )
        let promotion = try await service.promote(
            id: winner.id,
            originRepoPath: origin,
            expectedBaseCommit: baseCommit,
            commitMessage: "Apply selected task candidate",
            store: store
        )

        #expect(promotion.createdCandidateCommit)
        #expect(promotion.candidateCommit != baseCommit)
        #expect(promotion.mergedCommit != baseCommit)
        #expect(try String(
            contentsOf: origin.appendingPathComponent("Feature.txt"),
            encoding: .utf8
        ) == "selected\n")

        let cleanup = try await service.cleanupMergedWorktrees(
            originRepoPath: origin,
            baseRef: "HEAD",
            restrictingToIDs: [winner.id],
            store: store
        )
        #expect(cleanup.removed.map(\.id) == [winner.id])
        #expect(try await service.list(store: store).map(\.id) == [unrelated.id])
        #expect(FileManager.default.fileExists(atPath: unrelated.path.path))
    }

    @Test("a loser changed after preview invalidates confirmation and is retained")
    func staleLoserIsRetained() async throws {
        guard let git = CodeReviewGit.resolveGitExecutableURL() else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-promotion-stale-loser-\(UUID().uuidString)", isDirectory: true)
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
        let identifiers = LockedBox(["winner", "loser"])
        let service = WorktreeService(
            gitExecutableURLProvider: { git },
            randomIDProvider: { _ in identifiers.withValue { $0.removeFirst() } }
        )
        let store = WorktreeManifestStore.forRepo(
            basePath: config.basePath,
            originRepoPath: origin
        )
        let winner = try await service.add(
            originRepoPath: origin,
            agent: "winner",
            tabID: nil,
            config: config,
            store: store
        )
        let loser = try await service.add(
            originRepoPath: origin,
            agent: "loser",
            tabID: nil,
            config: config,
            store: store
        )
        let comparisonService = TaskRunComparisonService()
        let previewCandidate = TaskRunCandidate(
            id: "loser-candidate",
            provider: .codex,
            teamID: "loser-team",
            worktree: loser,
            status: .finished
        )
        let previewComparison = TaskRunCandidateComparison(
            candidate: previewCandidate,
            diffs: try comparisonService.loadDiffs(
                workingDirectory: loser.path,
                baseCommit: "HEAD"
            )
        )
        let preview = TaskRunPromotionPreview(
            run: try makeRun(origin: origin, winner: winner, loser: loser),
            comparisons: [previewComparison],
            selectedComparison: previewComparison,
            collisionReport: .empty,
            mergedCleanupPlan: WorktreeBatchCleanupPlan(removable: [], blocked: [], skipped: []),
            cleanupEntries: []
        )

        try "late work\n".write(
            to: loser.path.appendingPathComponent("late.txt"),
            atomically: true,
            encoding: .utf8
        )
        let freshComparison = TaskRunCandidateComparison(
            candidate: previewCandidate,
            diffs: try comparisonService.loadDiffs(
                workingDirectory: loser.path,
                baseCommit: "HEAD"
            )
        )

        #expect(!preview.matches(currentComparisons: [freshComparison]))
        do {
            _ = try await service.remove(
                id: loser.id,
                force: false,
                originRepoPath: origin,
                store: store
            )
            Issue.record("Expected dirty loser retention")
        } catch let error as WorktreeServiceError {
            guard case .uncommittedChanges = error else {
                Issue.record("Unexpected cleanup error: \(error)")
                return
            }
        }
        #expect(FileManager.default.fileExists(atPath: loser.path.path))
        #expect(try await service.list(store: store).contains { $0.id == loser.id })
    }

    private func makeRun(
        origin: URL,
        winner: WorktreeManifest.WorktreeEntry,
        loser: WorktreeManifest.WorktreeEntry
    ) throws -> TaskRun {
        let request = try TaskRunRequest.make(prompt: "Ship", agents: "codex,codex")
        var run = TaskRun(
            id: "stale-loser",
            request: request,
            originRepoPath: origin,
            baseCommit: "HEAD"
        )
        try run.updateCandidate(id: run.candidates[0].id) { $0.worktree = winner }
        try run.updateCandidate(id: run.candidates[1].id) { $0.worktree = loser }
        run.markRunning()
        return run
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
