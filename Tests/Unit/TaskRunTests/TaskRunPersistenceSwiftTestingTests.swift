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

    @Test("coordinator persists the newest burst snapshot away from the main thread")
    func coordinatorCoalescesBurst() throws {
        let probe = TaskRunSaveProbe(blocksFirstSave: true)
        let coordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-coalescing",
            saveOperation: { probe.save($0) }
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

    @Test("publish funnel writes through the app-scoped coordinator")
    @MainActor
    func publishFunnelWritesThroughCoordinator() throws {
        let probe = TaskRunSaveProbe()
        let delegate = AppDelegate()
        delegate.taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-funnel",
            saveOperation: { probe.save($0) }
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
        #expect(report.orphanedCandidateCount == 1)

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
            id: "durable-run",
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

    private func permissionBits(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private final class TaskRunSaveProbe: @unchecked Sendable {
    let firstSaveStarted = DispatchSemaphore(value: 0)
    let releaseFirstSave = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private let blocksFirstSave: Bool
    private var storedSnapshots: [TaskRun] = []
    private var observedMainThread = false

    init(blocksFirstSave: Bool = false) {
        self.blocksFirstSave = blocksFirstSave
    }

    var snapshots: [TaskRun] {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshots
    }

    var savedOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedMainThread
    }

    func save(_ run: TaskRun) {
        lock.lock()
        storedSnapshots.append(run)
        observedMainThread = observedMainThread || Thread.isMainThread
        let isFirstSave = storedSnapshots.count == 1
        lock.unlock()
        if blocksFirstSave && isFirstSave {
            firstSaveStarted.signal()
            releaseFirstSave.wait()
        }
    }
}

private final class TaskRunGitProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func recordCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }
}
