// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Task run promotion flow", .serialized)
struct TaskRunPromotionFlowSwiftTestingTests {
    @Test("prepare and execute accept a confirmed collision after the rival finishes")
    func prepareThenExecuteAcceptsRemovedRisk() async throws {
        let fixture = try await makeFixture(suffix: "prepare-execute")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let dashboard = AgentDashboardViewModel()
        var rival = MutableSessionData(
            id: "live-rival",
            projectName: fixture.repo.lastPathComponent,
            projectIdentity: fixture.run.projectID,
            tabId: UUID(),
            state: .working,
            agentName: "Review session",
            lastActivity: "Editing result.txt",
            lastActivityTime: Date()
        )
        rival.fileImpacts[fixture.resultFile.path] = FileImpact(
            path: fixture.resultFile.path,
            operations: [.edit]
        )
        dashboard.sessionDataStore[rival.id] = rival
        dashboard.rebuildSessions()
        fixture.delegate.agentDashboardViewModel = dashboard

        let preview = try await fixture.delegate.prepareTaskRunPromotion(
            runID: fixture.run.id,
            candidateID: fixture.selectedCandidateID
        )
        #expect(preview.collisionReport.paths == ["result.txt"])

        rival.agentName = "Renamed review session"
        rival.state = .finished
        dashboard.sessionDataStore[rival.id] = rival
        dashboard.rebuildSessions()

        let outcome = try await fixture.delegate.executeTaskRunPromotion(preview)

        #expect(outcome.run.status == .completed)
        #expect(outcome.run.promotedCandidateID == fixture.selectedCandidateID)
        #expect(try String(contentsOf: fixture.resultFile, encoding: .utf8) == "winner\n")
    }

    @Test("promoteTaskRun prepares and executes the selected candidate end to end")
    func promoteTaskRunExecutesFullFlow() async throws {
        let fixture = try await makeFixture(suffix: "wrapper")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let outcome = try await fixture.delegate.promoteTaskRun(
            runID: fixture.run.id,
            candidateID: fixture.selectedCandidateID
        )

        #expect(outcome.run.status == .completed)
        #expect(fixture.delegate.activeTaskRuns[fixture.run.id]?.status == .completed)
        #expect(try String(contentsOf: fixture.resultFile, encoding: .utf8) == "winner\n")
    }

    private func makeFixture(suffix: String) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "cocxy-task-promotion-flow-\(suffix)-\(UUID().uuidString)",
                isDirectory: true
            )
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        do {
            try runGit(["init", "-b", "main"], at: repo)
            try runGit(["config", "user.name", "Cocxy Tests"], at: repo)
            try runGit(["config", "user.email", "tests@cocxy.dev"], at: repo)
            let resultFile = repo.appendingPathComponent("result.txt")
            try "base\n".write(to: resultFile, atomically: true, encoding: .utf8)
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
            let candidateResultFile = entry.path.appendingPathComponent("result.txt")
            try "winner\n".write(
                to: candidateResultFile,
                atomically: true,
                encoding: .utf8
            )

            let request = try TaskRunRequest.make(
                prompt: "Update result.txt",
                agents: "codex,claude"
            )
            var run = TaskRun(
                id: "promotion-\(suffix)",
                request: request,
                originRepoPath: repo,
                baseCommit: baseCommit,
                worktreeBasePath: worktreeRoot.path
            )
            let selectedCandidateID = run.candidates[0].id
            try run.updateCandidate(id: selectedCandidateID) {
                $0.worktree = entry
                $0.status = .finished
            }
            try run.updateCandidate(id: run.candidates[1].id) {
                $0.status = .finished
            }
            run.markRunning()

            let delegate = AppDelegate()
            delegate.sharedWorktreeService = service
            delegate.taskInboxStore = TaskInboxStore(projectResolver: delegate.projectResolver)
            delegate.activeTaskRuns[run.id] = run
            return Fixture(
                root: root,
                repo: repo,
                resultFile: resultFile,
                delegate: delegate,
                run: run,
                selectedCandidateID: selectedCandidateID
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
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

    private struct Fixture {
        let root: URL
        let repo: URL
        let resultFile: URL
        let delegate: AppDelegate
        let run: TaskRun
        let selectedCandidateID: String
    }
}
