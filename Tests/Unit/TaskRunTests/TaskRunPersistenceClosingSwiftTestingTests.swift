// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("TaskRun persistence closing coverage", .serialized)
struct TaskRunPersistenceClosingSwiftTestingTests {
    @Test("retention failure is maintenance after a durable save")
    @MainActor
    func retentionFailureDoesNotFailSave() throws {
        let root = temporaryDirectory("maintenance")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = TaskRunFileManagerProbe()
        let store = TaskRunStore(
            rootDirectory: root.appendingPathComponent("snapshots"),
            fileManager: manager,
            retentionPolicy: TaskRunRetentionPolicy(maximumFinishedRunsPerProject: 1)
        )
        var first = try makeRun(id: "first", root: root, now: 100)
        try first.markCompleted(candidateID: first.candidates[0].id, now: Date(timeIntervalSince1970: 110))
        try store.save(first)
        manager.deniedRemovalPath = store.fileURL(for: first).path

        var second = try makeRun(id: "second", root: root, now: 200)
        try second.markCompleted(candidateID: second.candidates[0].id, now: Date(timeIntervalSince1970: 210))
        let report = try store.save(second)

        #expect(report.maintenanceFailures.count == 1)
        #expect(report.maintenanceFailures.first?.path == store.fileURL(for: first).path)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: second).path))

        var third = try makeRun(id: "third", root: root, now: 300)
        try third.markCompleted(candidateID: third.candidates[0].id, now: Date(timeIntervalSince1970: 310))
        let eventProbe = TaskRunPersistenceEventProbe()
        let coordinator = TaskRunPersistenceCoordinator(
            store: store,
            label: "dev.cocxy.tests.task-run-maintenance",
            retryDelay: 0,
            coalescingDelay: 0,
            eventHandler: { eventProbe.record($0) }
        )
        coordinator.enqueue(third)
        coordinator.flush()

        let event = try #require(eventProbe.events.last)
        guard case .maintenanceFailed(let runID, let failures) = event else {
            Issue.record("Expected a maintenance event after the durable save")
            return
        }
        #expect(runID == third.id)
        #expect(failures.count == 1)
        let delegate = AppDelegate()
        delegate.handleTaskRunPersistenceEvent(event)
        let issue = try #require(delegate.taskRunPersistenceIssue(for: third.id))
        #expect(issue == "Could not prune 1 older task run snapshot(s).")
        #expect(!issue.contains(root.path))
    }

    @Test("active snapshot saves do not scan project history")
    func activeSavesAvoidRetentionScans() throws {
        let root = temporaryDirectory("scan")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = TaskRunFileManagerProbe()
        let store = TaskRunStore(
            rootDirectory: root.appendingPathComponent("snapshots"),
            fileManager: manager,
            retentionPolicy: TaskRunRetentionPolicy(maximumFinishedRunsPerProject: 1)
        )
        var run = try makeRun(id: "active", root: root, now: 100)

        try store.save(run)
        run.markRunning(now: Date(timeIntervalSince1970: 110))
        try store.save(run)
        #expect(manager.projectDirectoryReadCount == 0)

        run.markFailed("finished", now: Date(timeIntervalSince1970: 120))
        try store.save(run)
        #expect(manager.projectDirectoryReadCount == 1)
    }

    @Test("stale interrupted snapshots expire during restoration")
    func staleInterruptedSnapshotsExpire() throws {
        let root = temporaryDirectory("expiry")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskRunStore(
            rootDirectory: root.appendingPathComponent("snapshots"),
            retentionPolicy: TaskRunRetentionPolicy(
                maximumFinishedRunsPerProject: 32,
                maximumInterruptedRunAge: 100
            ),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        var stale = try makeRun(id: "stale", root: root, now: 100)
        stale.markRunning(now: Date(timeIntervalSince1970: 100))
        stale.recoveredFromInterruption = true
        var recent = try makeRun(id: "recent", root: root, now: 950)
        recent.markRunning(now: Date(timeIntervalSince1970: 950))
        recent.recoveredFromInterruption = true
        try store.save(stale)
        try store.save(recent)

        let report = try store.loadAll()

        #expect(report.runs.map(\.id) == [recent.id])
        #expect(report.prunedSnapshotCount == 1)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: stale).path))
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: recent).path))
    }

    @Test("production coalescing window persists only the newest publication")
    func productionCoalescingWindowPersistsNewestSnapshot() throws {
        let probe = TaskRunSaveProbe()
        let coordinator = TaskRunPersistenceCoordinator(
            label: "dev.cocxy.tests.task-run-production-coalescing",
            saveOperation: { try probe.save($0) }
        )
        var run = try makeRun(
            id: "coalesced",
            root: URL(fileURLWithPath: "/tmp/task-run-production-coalescing"),
            now: 100
        )
        coordinator.enqueue(run)
        Thread.sleep(forTimeInterval: 0.005)
        run.failureMessage = "newest"
        run.updatedAt = Date(timeIntervalSince1970: 200)
        coordinator.enqueue(run)

        #expect(probe.firstSaveStarted.wait(timeout: .now() + 2) == .success)
        coordinator.flush()
        #expect(probe.snapshots == [run])
    }

    @Test("restoring multiple runs rebuilds the dashboard once")
    @MainActor
    func restorationBatchesDashboardRebuild() async throws {
        let root = temporaryDirectory("dashboard-batch")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskRunStore(rootDirectory: root.appendingPathComponent("snapshots"))
        for index in 1...3 {
            try store.save(makeRun(
                id: "restored-\(index)",
                root: root.appendingPathComponent("project-\(index)"),
                now: TimeInterval(index * 100)
            ))
        }
        let dashboard = AgentDashboardViewModel()
        var emissions = 0
        let cancellable = dashboard.sessionsPublisher.dropFirst().sink { _ in
            emissions += 1
        }
        let delegate = AppDelegate()
        delegate.taskRunStore = store
        delegate.agentDashboardViewModel = dashboard

        delegate.setupTaskRunDurability()
        await delegate.taskRunRestorationTask?.value
        delegate.taskRunPersistenceCoordinator?.flush()

        #expect(delegate.activeTaskRuns.count == 3)
        #expect(dashboard.sessions.filter { $0.id.hasPrefix("restored-") }.count == 3)
        #expect(emissions == 1)
        withExtendedLifetime(cancellable) {}
        delegate.shutdownTaskRuntimesForTermination()
    }

    private func makeRun(
        id: String,
        root: URL,
        now: TimeInterval
    ) throws -> TaskRun {
        TaskRun(
            id: id,
            request: try TaskRunRequest.make(
                prompt: "Implement and verify",
                agents: "codex,claude",
                count: 2,
                baseRef: "main"
            ),
            originRepoPath: root,
            baseCommit: "base-commit",
            now: Date(timeIntervalSince1970: now)
        )
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-task-run-closing-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private final class TaskRunFileManagerProbe: FileManager, @unchecked Sendable {
    private let state = State()

    var deniedRemovalPath: String? {
        get { state.lock.withLock { state.deniedRemovalPath } }
        set { state.lock.withLock { state.deniedRemovalPath = newValue } }
    }

    var projectDirectoryReadCount: Int {
        state.lock.withLock { state.directoryReads }
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        state.lock.withLock { state.directoryReads += 1 }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }

    override func removeItem(at URL: URL) throws {
        if URL.path == deniedRemovalPath {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var directoryReads = 0
        var deniedRemovalPath: String?
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
