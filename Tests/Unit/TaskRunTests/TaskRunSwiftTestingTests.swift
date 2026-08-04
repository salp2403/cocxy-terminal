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

    @Test("candidate no-op updates preserve the run revision")
    func candidateNoOpPreservesRevision() throws {
        var run = TaskRun(
            id: "stable-revision",
            request: try TaskRunRequest.make(prompt: "Ship", agents: "codex,claude"),
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "abc123",
            now: Date(timeIntervalSince1970: 10)
        )
        let candidateID = try #require(run.candidates.first?.id)

        let changed = try run.updateCandidate(
            id: candidateID,
            now: Date(timeIntervalSince1970: 20)
        ) { $0.status = .running }
        #expect(changed)
        #expect(run.updatedAt == Date(timeIntervalSince1970: 20))

        let unchanged = try run.updateCandidate(
            id: candidateID,
            now: Date(timeIntervalSince1970: 30)
        ) { $0.status = .running }
        #expect(!unchanged)
        #expect(run.updatedAt == Date(timeIntervalSince1970: 20))
    }

    @Test("failed promotion detaches only the selected candidate and keeps an alternative runnable")
    func failedPromotionKeepsAlternativeRunnable() throws {
        let request = try TaskRunRequest.make(
            prompt: "Ship",
            agents: "codex,claude"
        )
        var run = TaskRun(
            id: "promotion-recovery",
            request: request,
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "abc123"
        )
        let selectedID = try #require(run.candidates.first?.id)
        let alternativeID = try #require(run.candidates.last?.id)
        let selectedTabID = TabID()
        let alternativeTabID = TabID()
        try run.updateCandidate(id: selectedID) {
            $0.status = .running
            $0.worktree = WorktreeManifest.WorktreeEntry(
                id: "selected-worktree",
                branch: "task/selected",
                path: URL(fileURLWithPath: "/tmp/selected-worktree"),
                createdAt: Date(timeIntervalSince1970: 1),
                agent: "codex",
                tabID: selectedTabID
            )
        }
        try run.updateCandidate(id: alternativeID) {
            $0.status = .running
            $0.worktree = WorktreeManifest.WorktreeEntry(
                id: "alternative-worktree",
                branch: "task/alternative",
                path: URL(fileURLWithPath: "/tmp/alternative-worktree"),
                createdAt: Date(timeIntervalSince1970: 1),
                agent: "claude-code",
                tabID: alternativeTabID
            )
        }
        run.markRunning()
        try run.markPromoting(candidateID: selectedID)

        run.markPromotionFailed(
            candidateID: selectedID,
            message: "commit failed"
        )

        #expect(run.status == .running)
        #expect(run.promotedCandidateID == nil)
        #expect(run.failureMessage == "commit failed")
        #expect(run.candidates.first(where: { $0.id == selectedID })?.status == .failed)
        #expect(run.candidates.first(where: { $0.id == selectedID })?.worktree?.tabID == nil)
        #expect(run.candidates.first(where: { $0.id == alternativeID })?.status == .running)
        #expect(run.candidates.first(where: { $0.id == alternativeID })?.worktree?.tabID == alternativeTabID)
    }

    @Test("task run authority identifies every filesystem mutation boundary")
    func taskRunAuthorityIdentifiesMutationBoundaries() throws {
        let worktreeConfig = WorktreeConfig(
            enabled: true,
            basePath: "~/.cocxy/worktrees",
            branchTemplate: "cocxy/{agent}/{id}",
            baseRef: "HEAD",
            onClose: .keep,
            openInNewTab: true,
            idLength: 6,
            inheritProjectConfig: true,
            showBadge: true
        )
        let launchContext = TaskRunLaunchContext(
            worktreeConfig: worktreeConfig,
            originRepoPath: URL(fileURLWithPath: "/tmp/task-run-authority"),
            windowID: WindowID(),
            sourceTabID: TabID(),
            approvedWorkingDirectory: "/tmp/task-run-authority"
        )
        let launchDetails = AppDelegate.taskRunLaunchAuthorityDetails(
            for: launchContext
        )
        #expect(launchDetails["origin-repository"] == URL(
            fileURLWithPath: "/tmp/task-run-authority"
        ).resolvingSymlinksInPath().standardizedFileURL.path)
        #expect(launchDetails["worktree-root"] == URL(
            fileURLWithPath: (worktreeConfig.basePath as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL.path)

        let request = try TaskRunRequest.make(
            prompt: "Compare",
            agents: "codex,claude"
        )
        var run = TaskRun(
            id: "authority",
            request: request,
            originRepoPath: URL(fileURLWithPath: "/tmp/task-run-origin"),
            baseCommit: "abc123"
        )
        let candidateID = try #require(run.candidates.first?.id)
        let entry = WorktreeManifest.WorktreeEntry(
            id: "candidate-worktree",
            branch: "task/candidate",
            path: URL(fileURLWithPath: "/tmp/candidate-worktree"),
            createdAt: Date(timeIntervalSince1970: 1),
            agent: "codex",
            tabID: TabID()
        )
        try run.updateCandidate(id: candidateID) { $0.worktree = entry }
        let candidate = try #require(run.candidates.first)
        let promotionDetails = AppDelegate.taskRunPromotionAuthorityDetails(
            run: run,
            candidate: candidate,
            entry: entry
        )

        #expect(promotionDetails["run-id"] == run.id)
        #expect(promotionDetails["candidate-id"] == candidate.id)
        #expect(promotionDetails["branch"] == entry.branch)
        #expect(promotionDetails["origin-repository"] == run.originRepoPath.path)
        #expect(promotionDetails["base-commit"] == run.baseCommit)
        #expect(promotionDetails["discarded-candidates"] == "1")
    }

    @Test("launch planning preflights every provider and preserves the prompt")
    func launchPlanningPreflightsEveryProvider() async throws {
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

        let plans = try await TaskRunAgentLaunchPlan.make(
            run: run,
            preflightWorkingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            executableResolver: { "/resolved/\($0)" },
            launchExecutableResolver: { "/resolved/\($0)" }
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
