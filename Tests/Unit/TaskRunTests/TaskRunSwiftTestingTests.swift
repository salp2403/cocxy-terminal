// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("TaskRun")
struct TaskRunSwiftTestingTests {
    @Test("request cycles providers to the bounded candidate count")
    func requestCyclesProviders() throws {
        let request = try TaskRunRequest.make(
            prompt: "Implement and verify the change",
            agents: "claude,codex",
            count: 5,
            baseRef: "main"
        )

        #expect(request.providers == [
            .claudeCode, .codex, .claudeCode, .codex, .claudeCode,
        ])
        #expect(request.candidateCount == 5)
        #expect(request.baseRef == "main")
    }

    @Test("request rejects unsafe fan-out sizes and unsupported providers")
    func requestRejectsInvalidInputs() {
        #expect(throws: TaskRunError.invalidCandidateCount(1)) {
            try TaskRunRequest.make(prompt: "Ship", agents: "codex", count: 1)
        }
        #expect(throws: TaskRunError.candidateLimitExceeded(maximum: 8)) {
            try TaskRunRequest.make(prompt: "Ship", agents: "codex", count: 9)
        }
        #expect(throws: TaskRunError.unsupportedProvider("unknown")) {
            try TaskRunRequest.make(prompt: "Ship", agents: "codex,unknown")
        }
    }

    @Test("run tracks candidate lifecycle and one promoted winner")
    func runTracksLifecycle() throws {
        let request = try TaskRunRequest.make(
            prompt: "Ship",
            agents: "codex,claude"
        )
        var run = TaskRun(
            id: "Parallel Ship",
            request: request,
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "abc123",
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(run.id == "parallel-ship")
        #expect(run.candidates.map(\.id) == [
            "parallel-ship-candidate-1",
            "parallel-ship-candidate-2",
        ])
        try run.updateCandidate(id: "parallel-ship-candidate-1") {
            $0.status = .running
            $0.estimatedCostMicros = 42
        }
        run.markRunning()
        try run.markPromoting(candidateID: "parallel-ship-candidate-1")
        try run.markCompleted(candidateID: "parallel-ship-candidate-1")

        #expect(run.status == .completed)
        #expect(run.promotedCandidateID == "parallel-ship-candidate-1")
        #expect(run.candidates.map(\.status) == [.promoted, .discarded])
        #expect(run.candidates[0].estimatedCostMicros == 42)
    }

    @Test("comparison includes committed diff and synthetic untracked files")
    func comparisonIncludesTrackedAndUntrackedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-run-comparison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "new line\n".write(
            to: root.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = TaskRunComparisonService { _, arguments in
            if arguments.first == "diff" {
                return CodeReviewGitResult(
                    stdout: """
                    diff --git a/tracked.txt b/tracked.txt
                    index 1111111..2222222 100644
                    --- a/tracked.txt
                    +++ b/tracked.txt
                    @@ -1 +1 @@
                    -old
                    +new
                    """,
                    stderr: "",
                    terminationStatus: 0
                )
            }
            return CodeReviewGitResult(
                stdout: " M tracked.txt\n?? new.txt\n",
                stderr: "",
                terminationStatus: 0
            )
        }

        let diffs = try service.loadDiffs(
            workingDirectory: root,
            baseCommit: "abc123"
        )

        #expect(diffs.map(\.filePath) == ["tracked.txt", "new.txt"])
        #expect(diffs.first(where: { $0.filePath == "new.txt" })?.status == .untracked)
        #expect(diffs.reduce(0) { $0 + $1.additions } == 2)
        #expect(diffs.reduce(0) { $0 + $1.deletions } == 1)
    }
}

@Suite("TaskRun promotion", .serialized)
struct TaskRunPromotionSwiftTestingTests {
    @Test("promotion commits selected work and merges it into the unchanged origin")
    func promotionCommitsAndMergesWinner() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-run-promotion-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: repo)
        try runGit(["config", "user.name", "Cocxy Tests"], at: repo)
        try runGit(["config", "user.email", "tests@cocxy.dev"], at: repo)
        try "base\n".write(
            to: repo.appendingPathComponent("result.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "result.txt"], at: repo)
        try runGit(["commit", "-m", "base"], at: repo)

        let service = WorktreeService(
            gitExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/git") },
            randomIDProvider: { _ in "winner" }
        )
        let config = WorktreeConfig(
            enabled: true,
            basePath: worktreeRoot.path,
            branchTemplate: "task/{agent}/{id}",
            baseRef: "HEAD",
            onClose: .keep,
            openInNewTab: true,
            idLength: 6,
            inheritProjectConfig: true,
            showBadge: true
        )
        let store = WorktreeManifestStore.forRepo(
            basePath: config.basePath,
            originRepoPath: repo
        )
        let baseCommit = try await service.revision("HEAD", at: repo)
        let entry = try await service.add(
            originRepoPath: repo,
            agent: "codex",
            tabID: nil,
            config: config,
            store: store
        )
        try "winner\n".write(
            to: entry.path.appendingPathComponent("result.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await service.promote(
            id: entry.id,
            originRepoPath: repo,
            expectedBaseCommit: baseCommit,
            commitMessage: "Apply selected task candidate",
            store: store
        )

        #expect(result.createdCandidateCommit)
        #expect(result.candidateCommit != baseCommit)
        #expect(result.mergedCommit != baseCommit)
        #expect(try String(contentsOf: repo.appendingPathComponent("result.txt"), encoding: .utf8) == "winner\n")
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let result = try CodeReviewGit.run(
            workingDirectory: directory,
            arguments: arguments,
            gitExecutableURLOverride: URL(fileURLWithPath: "/usr/bin/git")
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
