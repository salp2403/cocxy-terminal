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

    @Test("launch planning preflights every provider and preserves the prompt")
    func launchPlanningPreflightsEveryProvider() throws {
        let request = try TaskRunRequest.make(
            prompt: "Implement, test, and report",
            agents: "claude,codex",
            count: 3
        )
        let run = TaskRun(
            id: "preflight",
            request: request,
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "abc123"
        )

        let plans = try TaskRunAgentLaunchPlan.make(
            run: run,
            preflightWorkingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            executableResolver: { "/resolved/\($0)" }
        )

        #expect(plans.map(\.candidateID) == run.candidates.map(\.id))
        #expect(plans.map(\.config.provider) == [.claudeCode, .codex, .claudeCode])
        #expect(plans.allSatisfy { $0.config.teammates.first?.prompt == request.prompt })
        #expect(plans.allSatisfy { $0.preflightSpec.workingDirectory == "/tmp/repo" })
        #expect(plans.allSatisfy {
            $0.preflightSpec.environment["COCXY_AGENT_TEAM_ID"] == $0.config.id
        })
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
            if arguments.contains("diff") {
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

    @Test("promotion preflight rejects an origin with uncommitted work")
    func promotionRejectsDirtyOrigin() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-run-dirty-origin-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
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
            gitExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/git") }
        )
        let baseCommit = try await service.revision("HEAD", at: repo)
        try "dirty\n".write(
            to: repo.appendingPathComponent("result.txt"),
            atomically: true,
            encoding: .utf8
        )

        do {
            try await service.validatePromotionOrigin(
                originRepoPath: repo,
                expectedBaseCommit: baseCommit
            )
            Issue.record("Expected dirty-origin rejection")
        } catch let error as WorktreeServiceError {
            guard case .originHasUncommittedChanges(let path, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(path == repo.path)
        }
    }

    @Test("promotion preflight rejects a base revision that moved")
    func promotionRejectsMovedBase() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-run-moved-base-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
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
            gitExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/git") }
        )
        let baseCommit = try await service.revision("HEAD", at: repo)
        try "moved\n".write(
            to: repo.appendingPathComponent("result.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "result.txt"], at: repo)
        try runGit(["commit", "-m", "move base"], at: repo)
        let actualCommit = try await service.revision("HEAD", at: repo)

        do {
            try await service.validatePromotionOrigin(
                originRepoPath: repo,
                expectedBaseCommit: baseCommit
            )
            Issue.record("Expected moved-base rejection")
        } catch let error as WorktreeServiceError {
            #expect(error == .baseRevisionChanged(
                expected: baseCommit,
                actual: actualCommit
            ))
        }
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
