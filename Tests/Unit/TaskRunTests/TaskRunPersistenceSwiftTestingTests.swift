// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("TaskRun persistence", .serialized)
struct TaskRunPersistenceSwiftTestingTests {
    @Test("store scopes runs by canonical project and applies owner-only permissions")
    func storeScopesRunsByProject() throws {
        let root = temporaryDirectory("store")
        defer { try? FileManager.default.removeItem(at: root) }
        let run = try makeRun(origin: root.appendingPathComponent("repo"), count: 2)
        let store = TaskRunStore(rootDirectory: root.appendingPathComponent("snapshots"))

        try store.save(run)

        let fileURL = store.fileURL(for: run)
        #expect(fileURL.deletingLastPathComponent().lastPathComponent == run.projectID.storageKey)
        #expect(fileURL.lastPathComponent == run.id + TaskRunStore.fileSuffix)
        #expect(permissionBits(at: store.rootDirectory) == 0o700)
        #expect(permissionBits(at: fileURL.deletingLastPathComponent()) == 0o700)
        #expect(permissionBits(at: fileURL) == 0o600)
        let report = try store.loadAll()
        #expect(report.rejectedFiles.isEmpty)
        #expect(report.runs == [run])
    }

    @Test("store rejects a project directory symbolic link")
    func storeRejectsProjectDirectorySymlink() throws {
        let root = temporaryDirectory("symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let run = try makeRun(origin: root.appendingPathComponent("repo"), count: 2)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let projectDirectory = snapshots.appendingPathComponent(
            run.projectID.storageKey,
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: projectDirectory,
            withDestinationURL: outside
        )
        let store = TaskRunStore(rootDirectory: snapshots)

        #expect(throws: TaskRunStoreError.symbolicLinkRejected(projectDirectory.path)) {
            try store.save(run)
        }
    }

    @Test("snapshot removal rejects a symbolic link without deleting its target")
    func removalRejectsSnapshotSymlink() throws {
        let root = temporaryDirectory("remove-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let run = try makeRun(origin: root.appendingPathComponent("repo"), count: 2)
        let store = TaskRunStore(rootDirectory: root.appendingPathComponent("snapshots"))
        try store.save(run)
        let snapshot = store.fileURL(for: run)
        let outside = root.appendingPathComponent("outside.json")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: snapshot)
        try FileManager.default.createSymbolicLink(at: snapshot, withDestinationURL: outside)

        #expect(throws: TaskRunStoreError.symbolicLinkRejected(snapshot.path)) {
            try store.remove(run)
        }
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    @Test("coordinator persists the newest burst snapshot away from the main thread")
    func coordinatorCoalescesBurst() throws {
        let probe = TaskRunSaveProbe(blocksFirstSave: true)
        let coordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-coalescing",
            saveOperation: { try probe.save($0) }
        )
        var run = try makeRun(
            origin: URL(fileURLWithPath: "/tmp/task-run-coalescing"),
            count: 2
        )

        coordinator.enqueue(run)
        #expect(probe.firstSaveStarted.wait(timeout: .now() + 2) == .success)
        for index in 1...8 {
            run.updatedAt = Date(timeIntervalSince1970: TimeInterval(index))
            run.failureMessage = "snapshot-\(index)"
            coordinator.enqueue(run)
        }
        probe.releaseFirstSave.signal()
        coordinator.flush()

        let snapshots = probe.snapshots
        #expect(snapshots.count == 2)
        #expect(snapshots.last?.failureMessage == "snapshot-8")
        #expect(probe.savedOnMainThread == false)
    }

    @Test("coordinator retries a transient save and survives a fresh store load")
    func coordinatorRetriesTransientFailureBeforeRestart() throws {
        let root = temporaryDirectory("retry")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        let store = TaskRunStore(rootDirectory: snapshots)
        let probe = TaskRunTransientSaveProbe(store: store, failuresBeforeSuccess: 1)
        let coordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-retry",
            maximumRetryAttempts: 3,
            retryDelay: 0,
            saveOperation: { try probe.save($0) }
        )
        let run = try makeRun(
            id: "retry-survives-restart",
            origin: root.appendingPathComponent("repo"),
            count: 2
        )

        coordinator.enqueue(run)
        coordinator.flush()

        #expect(probe.attemptCount == 2)
        let restartedStore = TaskRunStore(rootDirectory: snapshots)
        let report = try restartedStore.loadAll()
        #expect(report.rejectedFiles.isEmpty)
        #expect(report.runs == [run])
    }

    @Test("a failed stale snapshot never replaces a newer pending snapshot")
    func coordinatorRetainsNewestSnapshotAcrossFailure() throws {
        let probe = TaskRunSaveProbe(blocksFirstSave: true, failsFirstSave: true)
        let coordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-newest-retry",
            maximumRetryAttempts: 1,
            retryDelay: 0,
            saveOperation: { try probe.save($0) }
        )
        var run = try makeRun(
            origin: URL(fileURLWithPath: "/tmp/task-run-newest-retry"),
            count: 2
        )

        coordinator.enqueue(run)
        #expect(probe.firstSaveStarted.wait(timeout: .now() + 2) == .success)
        run.updatedAt = Date(timeIntervalSince1970: 200)
        run.failureMessage = "newest-snapshot"
        coordinator.enqueue(run)
        probe.releaseFirstSave.signal()
        coordinator.flush()

        #expect(probe.snapshots.count == 2)
        #expect(probe.successfulSnapshots == [run])
    }

    @Test("nested persistence barriers replay the newest deferred snapshot")
    func coordinatorReplaysNestedSuppression() throws {
        let probe = TaskRunSaveProbe()
        let coordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-nested-barrier",
            saveOperation: { try probe.save($0) }
        )
        var run = try makeRun(
            origin: URL(fileURLWithPath: "/tmp/task-run-nested-barrier"),
            count: 2
        )

        coordinator.suppress(runID: run.id)
        coordinator.suppress(runID: run.id)
        run.failureMessage = "newest-deferred-snapshot"
        coordinator.enqueue(run)
        coordinator.resume(runID: run.id)
        coordinator.flush()
        #expect(probe.snapshots.isEmpty)

        coordinator.resume(runID: run.id)
        coordinator.flush()
        #expect(probe.snapshots == [run])
    }

    @Test("immediate persistence replays state published while the disk is busy")
    @MainActor
    func immediatePersistenceReplaysConcurrentPublication() async throws {
        let probe = TaskRunSaveProbe(blocksFirstSave: true)
        let delegate = AppDelegate()
        delegate.taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-immediate-replay",
            saveOperation: { try probe.save($0) }
        )
        let run = try makeRun(
            origin: URL(fileURLWithPath: "/tmp/task-run-immediate-replay"),
            count: 2
        )
        delegate.publishTaskRun(run, fallbackTabID: UUID(), persist: false)

        let saveTask = Task.detached(priority: .utility) {
            try await delegate.persistTaskRunImmediately(run)
        }
        let startResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: probe.firstSaveStarted.wait(timeout: .now() + 2)
                )
            }
        }
        #expect(startResult == .success)
        var latest = run
        latest.failureMessage = "published-during-save"
        latest.updatedAt = Date(timeIntervalSince1970: 500)
        delegate.publishTaskRun(latest, fallbackTabID: UUID())
        probe.releaseFirstSave.signal()
        try await saveTask.value
        delegate.taskRunPersistenceCoordinator?.flush()

        #expect(probe.snapshots == [run, latest])
    }

    @Test("a stale launch precheck cannot execute after cancellation")
    @MainActor
    func staleLaunchPrecheckCannotExecuteAfterCancellation() throws {
        let delegate = AppDelegate()
        var run = try makeRun(
            id: "cancelled-before-launch-effect",
            origin: URL(fileURLWithPath: "/tmp/cancelled-before-launch-effect"),
            count: 2
        )
        delegate.publishTaskRun(run, fallbackTabID: UUID(), persist: false)
        let stalePrecheck = run
        #expect(stalePrecheck.status == .launching)
        try run.markCancelled()
        delegate.publishTaskRun(run, fallbackTabID: UUID(), persist: false)
        var effectCount = 0

        #expect(throws: TaskRunExecutionError.cancelled(run.id)) {
            try delegate.performTaskRunLaunchEffect(runID: stalePrecheck.id) { _ in
                effectCount += 1
            }
        }
        #expect(effectCount == 0)
    }

    @Test("publish funnel writes through the app-scoped coordinator")
    @MainActor
    func publishFunnelWritesThroughCoordinator() throws {
        let probe = TaskRunSaveProbe()
        let delegate = AppDelegate()
        delegate.taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-funnel",
            saveOperation: { try probe.save($0) }
        )
        let run = try makeRun(
            origin: URL(fileURLWithPath: "/tmp/task-run-funnel"),
            count: 2
        )

        delegate.publishTaskRun(run, fallbackTabID: UUID())
        delegate.taskRunPersistenceCoordinator?.flush()

        #expect(delegate.activeTaskRuns[run.id] == run)
        #expect(probe.snapshots == [run])
    }

    @Test("app startup restores persisted runs through the app-scoped store")
    @MainActor
    func appStartupRestoresPersistedRuns() async throws {
        let root = temporaryDirectory("app-restore")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskRunStore(rootDirectory: root.appendingPathComponent("snapshots"))
        let run = try makeRun(
            id: "restored-at-startup",
            origin: root.appendingPathComponent("project"),
            count: 2
        )
        try store.save(run)
        let delegate = AppDelegate()
        delegate.taskRunStore = store

        delegate.setupTaskRunDurability()
        await delegate.taskRunRestorationTask?.value
        delegate.taskRunPersistenceCoordinator?.flush()

        let restored = try #require(delegate.activeTaskRuns[run.id])
        #expect(restored.status == .failed)
        #expect(restored.candidates.allSatisfy { $0.status == .orphaned })
        #expect(delegate.taskRunPersistenceCoordinator != nil)
        delegate.shutdownTaskRuntimesForTermination()
    }

    @Test("restore marks candidates without worktrees orphaned and fails an empty launch")
    func restoreMarksMissingWorktreesOrphaned() async throws {
        let run = try makeRun(
            id: "interrupted-before-worktrees",
            origin: URL(fileURLWithPath: "/tmp/interrupted-before-worktrees"),
            count: 3
        )

        let result = await TaskRunRestorer(
            now: { Date(timeIntervalSince1970: 200) }
        ).reconcile(run)

        #expect(result.run.status == .failed)
        #expect(result.run.candidates.allSatisfy { $0.status == .orphaned })
        #expect(result.run.candidates.allSatisfy {
            $0.failureMessage?.contains("was not created") == true
        })
        #expect(result.orphanedCandidateCount == 3)
        #expect(result.interruptedRunCount == 1)
    }

    @Test("restore turns an interrupted promotion into an explicit failure")
    func restoreFailsInterruptedPromotion() async throws {
        var run = try makeRun(
            id: "interrupted-promotion",
            origin: URL(fileURLWithPath: "/tmp/interrupted-promotion"),
            count: 2
        )
        run.markRunning(now: Date(timeIntervalSince1970: 150))
        try run.markPromoting(
            candidateID: run.candidates[0].id,
            now: Date(timeIntervalSince1970: 160)
        )

        let result = await TaskRunRestorer(
            now: { Date(timeIntervalSince1970: 200) }
        ).reconcile(run)

        #expect(result.run.status == .failed)
        #expect(result.run.promotedCandidateID == nil)
        #expect(result.run.failureMessage?.contains("promotion was interrupted") == true)
        #expect(result.run.recoveredFromInterruption)
    }

    @Test("store caps finished history without pruning an active run")
    func storeCapsFinishedHistory() throws {
        let root = temporaryDirectory("retention")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        let origin = root.appendingPathComponent("repo", isDirectory: true)
        let writer = TaskRunStore(
            rootDirectory: snapshots,
            retentionPolicy: TaskRunRetentionPolicy(maximumFinishedRunsPerProject: 10)
        )
        for index in 0..<5 {
            var run = try makeRun(id: "finished-\(index)", origin: origin, count: 2)
            try run.markCompleted(
                candidateID: run.candidates[0].id,
                now: Date(timeIntervalSince1970: TimeInterval(300 + index))
            )
            try writer.save(run)
        }
        let active = try makeRun(id: "active", origin: origin, count: 2)
        try writer.save(active)

        let capped = TaskRunStore(
            rootDirectory: snapshots,
            retentionPolicy: TaskRunRetentionPolicy(maximumFinishedRunsPerProject: 2)
        )
        let report = try capped.loadAll()

        #expect(report.prunedSnapshotCount == 3)
        #expect(Set(report.runs.map(\.id)) == ["active", "finished-3", "finished-4"])
        #expect(report.runs.contains(where: { !$0.status.isFinished }))
        let projectFiles = try FileManager.default.contentsOfDirectory(
            at: capped.fileURL(for: active).deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(TaskRunStore.fileSuffix) }
        #expect(projectFiles.count == 3)
    }

    @Test("final persistence failure becomes visible task state")
    @MainActor
    func persistenceFailureIsVisible() throws {
        let probe = TaskRunPersistenceEventProbe()
        let delegate = AppDelegate()
        delegate.taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-visible-failure",
            maximumRetryAttempts: 2,
            retryDelay: 0,
            saveOperation: { _ in
                throw TaskRunStoreError.persistenceFailed("controlled disk failure")
            },
            eventHandler: { probe.record($0) }
        )
        let run = try makeRun(
            id: "visible-failure",
            origin: URL(fileURLWithPath: "/tmp/visible-failure"),
            count: 2
        )

        delegate.publishTaskRun(run, fallbackTabID: UUID())
        delegate.taskRunPersistenceCoordinator?.flush()
        let event = try #require(probe.events.last)
        delegate.handleTaskRunPersistenceEvent(event)

        #expect(delegate.taskRunPersistenceIssue(for: run.id)?.contains(
            "controlled disk failure"
        ) == true)
        guard case .partial(let issues) = delegate.taskInboxStore.snapshot.availability else {
            Issue.record("Expected degraded task inbox state")
            return
        }
        #expect(issues.contains { $0.message.contains("Changes remain in memory") })
    }

    @Test("restored active run cancellation is durable")
    @MainActor
    func restoredRunCancellationPersists() async throws {
        let root = temporaryDirectory("cancel")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskRunStore(rootDirectory: root.appendingPathComponent("snapshots"))
        var run = try makeRun(id: "restored-active", origin: root.appendingPathComponent("repo"), count: 2)
        run.markRunning(now: Date(timeIntervalSince1970: 200))
        run.recoveredFromInterruption = true
        let delegate = AppDelegate()
        delegate.taskRunStore = store
        delegate.taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(store: store)
        delegate.publishTaskRun(run, fallbackTabID: UUID(), persist: false)
        for candidate in run.candidates {
            delegate.taskRunIDByTeamID[candidate.teamID] = run.id
        }
        _ = try delegate.taskOrchestrationSessionManager.issue(
            runID: run.id,
            tabIDs: [UUID()]
        )

        let cancelled = try await delegate.cancelTaskRun(runID: run.id)

        #expect(cancelled.status == .cancelled)
        #expect(delegate.activeTaskRuns[run.id]?.status == .cancelled)
        #expect(run.candidates.allSatisfy { delegate.taskRunIDByTeamID[$0.teamID] == nil })
        #expect(delegate.taskOrchestrationSessionManager.credential(forRunID: run.id) == nil)
        #expect(try store.loadAll().runs.first?.status == .cancelled)
    }

    @Test("forget removes a finished run from memory and disk")
    @MainActor
    func forgetFinishedRunRemovesSnapshot() async throws {
        let root = temporaryDirectory("forget")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskRunStore(rootDirectory: root.appendingPathComponent("snapshots"))
        var run = try makeRun(id: "finished-forget", origin: root.appendingPathComponent("repo"), count: 2)
        let retainedWorktree = root.appendingPathComponent("retained-worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: retainedWorktree, withIntermediateDirectories: true)
        try run.updateCandidate(id: run.candidates[0].id) {
            $0.worktree = WorktreeManifest.WorktreeEntry(
                id: "retained-worktree",
                branch: "task/retained",
                path: retainedWorktree,
                createdAt: Date(timeIntervalSince1970: 1),
                agent: $0.provider.rawValue,
                tabID: nil
            )
        }
        try run.markCompleted(candidateID: run.candidates[0].id)
        try store.save(run)
        let delegate = AppDelegate()
        delegate.taskRunStore = store
        delegate.taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(store: store)
        delegate.publishTaskRun(run, fallbackTabID: UUID(), persist: false)

        try await delegate.forgetTaskRun(runID: run.id)

        #expect(delegate.activeTaskRuns[run.id] == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: run).path))
        #expect(FileManager.default.fileExists(atPath: retainedWorktree.path))
        #expect(try store.loadAll().runs.isEmpty)
    }

    @Test("task run list filters by canonical project")
    @MainActor
    func taskRunListFiltersByProject() throws {
        let root = temporaryDirectory("project-filter")
        defer { try? FileManager.default.removeItem(at: root) }
        let projectA = root.appendingPathComponent("project-a", isDirectory: true)
        let projectB = root.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: projectA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectB, withIntermediateDirectories: true)
        let runA = try makeRun(id: "run-a", origin: projectA, count: 2)
        let runB = try makeRun(id: "run-b", origin: projectB, count: 2)
        let delegate = AppDelegate()
        delegate.publishTaskRun(runA, fallbackTabID: UUID())
        delegate.publishTaskRun(runB, fallbackTabID: UUID())

        let result = delegate.handleTaskRunCLIRequest(
            kind: "list",
            params: ["project": projectA.path]
        )
        let data = try #require(result.data["runs"]?.data(using: .utf8))
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        #expect(result.success)
        #expect(result.data["count"] == "1")
        #expect(payload.map { $0["id"] as? String } == ["run-a"])
        #expect(payload.first?["project"] as? String == projectA.path)
    }

    @Test("restore keeps five candidates and marks a deleted worktree orphaned")
    func restoreReconcilesManifestAndDisk() async throws {
        let root = temporaryDirectory("restore")
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appendingPathComponent("repo", isDirectory: true)
        let worktreeBase = root.appendingPathComponent("worktrees", isDirectory: true)
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)

        var run = try makeRun(
            origin: origin,
            count: 5,
            worktreeBasePath: worktreeBase.path
        )
        var entries: [WorktreeManifest.WorktreeEntry] = []
        for index in run.candidates.indices {
            let path = root.appendingPathComponent("candidate-\(index + 1)", isDirectory: true)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try Data().write(to: path.appendingPathComponent(".git"))
            let entry = WorktreeManifest.WorktreeEntry(
                id: "worktree-\(index + 1)",
                branch: "task/candidate-\(index + 1)",
                path: path,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                agent: run.candidates[index].provider.rawValue,
                tabID: nil
            )
            entries.append(entry)
            try run.updateCandidate(id: run.candidates[index].id) {
                $0.worktree = entry
                $0.status = .running
            }
        }
        run.markRunning()
        let manifest = WorktreeManifest(
            repoHash: WorktreeManifest.hashForRepoPath(origin),
            originRepoPath: origin,
            entries: entries
        )
        try await WorktreeManifestStore.forRepo(
            basePath: worktreeBase.path,
            originRepoPath: origin
        ).save(manifest)
        let store = TaskRunStore(rootDirectory: snapshots)
        try store.save(run)
        try FileManager.default.removeItem(at: entries[2].path)

        let report = try await TaskRunRestorer().restore(from: store)
        let restored = try #require(report.runs.first)

        #expect(restored.candidates.count == 5)
        #expect(restored.baseCommit == "base-commit")
        #expect(restored.candidates.map(\.worktree?.branch) == entries.map(\.branch))
        #expect(restored.candidates[2].status == .orphaned)
        #expect(restored.candidates[2].worktree?.tabID == nil)
        #expect(restored.recoveredFromInterruption)
        #expect(report.orphanedCandidateCount == 1)

        let secondRestore = await TaskRunRestorer(
            now: { Date(timeIntervalSince1970: 9_999) }
        ).reconcile(restored)
        #expect(secondRestore.run == restored)
        #expect(secondRestore.interruptedRunCount == 0)

        let gitProbe = TaskRunGitProbe()
        let comparisons = try TaskRunComparisonService { _, _ in
            gitProbe.recordCall()
            return CodeReviewGitResult(stdout: "", stderr: "", terminationStatus: 0)
        }.load(run: restored)
        #expect(comparisons.count == 4)
        #expect(comparisons.contains(where: { $0.id == restored.candidates[2].id }) == false)
        #expect(gitProbe.callCount == 8)
    }

    private func makeRun(
        id: String = "durable-run",
        origin: URL,
        count: Int,
        worktreeBasePath: String = "/tmp/cocxy-task-run-worktrees"
    ) throws -> TaskRun {
        let request = try TaskRunRequest.make(
            prompt: "Implement and verify",
            agents: "codex,claude",
            count: count,
            baseRef: "main"
        )
        return TaskRun(
            id: id,
            request: request,
            originRepoPath: origin,
            baseCommit: "base-commit",
            worktreeBasePath: worktreeBasePath,
            now: Date(timeIntervalSince1970: 100)
        )
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-task-run-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
