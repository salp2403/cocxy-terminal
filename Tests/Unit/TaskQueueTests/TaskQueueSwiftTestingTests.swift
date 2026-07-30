// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task queue")
struct TaskQueueSwiftTestingTests {
    @Test("persists valid tasks with owner-only permissions and isolates corrupt files")
    func persistenceIsOwnerOnlyAndCorruptionTolerant() throws {
        let root = temporaryQueueDirectory()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = TaskQueueStore(rootDirectory: root)
        let item = try makeQueueItem(id: "nightly")

        try store.save(item)
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent("broken.task.json"),
            options: .atomic
        )
        try Data(contentsOf: store.fileURL(taskID: item.id)).write(
            to: root.appendingPathComponent("duplicate.task.json"),
            options: .atomic
        )
        let report = try store.loadAll()

        #expect(report.items == [item])
        #expect(report.rejectedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent } == [
            "broken.task.json",
            "nightly.task.json",
        ])
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: store.fileURL(taskID: item.id).path
        )
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("rejects a symbolic queue root")
    func rejectsSymbolicQueueRoot() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-queue-link-\(UUID().uuidString)", isDirectory: true)
        let destination = parent.appendingPathComponent("real", isDirectory: true)
        let link = parent.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        defer { try? FileManager.default.removeItem(at: parent) }

        let store = TaskQueueStore(rootDirectory: link)
        #expect(throws: TaskQueueStoreError.symbolicLinkRejected(link.path)) {
            try store.save(makeQueueItem(id: "linked"))
        }
    }

    @Test("manual tasks retry after backoff and emit paired lifecycle events")
    func manualTaskRetriesAfterBackoff() async throws {
        let clock = LockedQueueClock(now: Date(timeIntervalSince1970: 10_000))
        let recorder = QueueRunRecorder(failuresBeforeSuccess: 1, clock: clock)
        let lifecycle = QueueLifecycleRecorder()
        let queue = try TaskQueue(
            store: TaskQueueStore(rootDirectory: temporaryQueueDirectory()),
            retryBaseDelay: 5,
            clock: { clock.now },
            runHandler: { item in await recorder.run(item) },
            lifecycleHandler: { event in await lifecycle.record(event) }
        )
        _ = try await queue.start()
        let item = try makeQueueItem(id: "retry", maximumRetries: 1, now: clock.now)

        _ = try await queue.enqueue(item)
        let retrying = try await waitForQueueItem(queue, id: item.id) { $0.status == .retrying }
        #expect(retrying.retryAttempt == 1)
        #expect(retrying.nextRunAt == clock.now.addingTimeInterval(5))

        clock.advance(by: 5)
        await queue.tick(at: clock.now)
        let succeeded = try await waitForQueueItem(queue, id: item.id) { $0.status == .succeeded }

        #expect(succeeded.totalRunCount == 2)
        #expect(await recorder.runCount == 2)
        #expect(await lifecycle.kinds == [.started, .finished, .started, .finished])
    }

    @Test("global run concurrency is bounded and queued work drains")
    func globalConcurrencyIsBounded() async throws {
        let gate = QueueConcurrencyGate()
        let root = temporaryQueueDirectory()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let queue = try TaskQueue(
            store: TaskQueueStore(rootDirectory: root),
            maximumConcurrentRuns: 2,
            runHandler: { item in await gate.run(item) }
        )
        _ = try await queue.start()

        for id in ["one", "two", "three"] {
            _ = try await queue.enqueue(makeQueueItem(id: id))
        }
        try await waitUntil { await gate.startedCount == 2 }
        #expect(await gate.maximumActive == 2)

        await gate.releaseAll()
        try await waitUntil { await gate.startedCount == 3 }
        await gate.releaseAll()
        try await waitUntil {
            let statuses = await queue.list().map(\.status)
            return statuses.allSatisfy { $0 == .succeeded }
        }
        #expect(await gate.maximumActive == 2)
    }

    @Test("event triggers are coalesced while a run is active")
    func eventTriggersCoalesceWhileRunning() async throws {
        let gate = QueueConcurrencyGate()
        let queue = try TaskQueue(
            store: TaskQueueStore(rootDirectory: temporaryQueueDirectory()),
            runHandler: { item in await gate.run(item) }
        )
        _ = try await queue.start()
        let trigger = try TaskQueueTrigger.eventTrigger(.commandComplete)
        let item = try makeQueueItem(id: "on-command", trigger: trigger)
        _ = try await queue.enqueue(item)

        await queue.handlePluginEvent(.tabCreated)
        #expect(await gate.startedCount == 0)
        await queue.handlePluginEvent(.commandComplete)
        try await waitUntil { await gate.startedCount == 1 }
        await queue.handlePluginEvent(.commandComplete)
        await queue.handlePluginEvent(.commandComplete)

        await gate.releaseAll()
        try await waitUntil { await gate.startedCount == 2 }
        await gate.releaseAll()
        let waiting = try await waitForQueueItem(queue, id: item.id) {
            $0.status == .scheduled && $0.totalRunCount == 2
        }
        #expect(!waiting.pendingRun)
        #expect(waiting.nextRunAt == nil)
    }

    @Test("cron tasks run only after their computed due date and remain scheduled")
    func cronTasksRunAtDueDate() async throws {
        let start = Date(timeIntervalSince1970: 1_767_261_570) // 2026-01-01 09:59:30 UTC
        let clock = LockedQueueClock(now: start)
        let recorder = QueueRunRecorder(clock: clock)
        let queue = try TaskQueue(
            store: TaskQueueStore(rootDirectory: temporaryQueueDirectory()),
            clock: { clock.now },
            runHandler: { item in await recorder.run(item) }
        )
        _ = try await queue.start()
        let schedule = try CronSchedule(expression: "0 10 * * *", timeZoneIdentifier: "UTC")
        let item = try makeQueueItem(id: "daily", trigger: .cron(schedule), now: start)
        _ = try await queue.enqueue(item)

        await queue.tick(at: start.addingTimeInterval(29))
        #expect(await recorder.runCount == 0)
        clock.advance(by: 30)
        await queue.tick(at: clock.now)
        let scheduled = try await waitForQueueItem(queue, id: item.id) {
            $0.status == .scheduled && $0.totalRunCount == 1
        }

        #expect(await recorder.runCount == 1)
        #expect(try #require(scheduled.nextRunAt) > clock.now)
    }

    @Test("cancelling an active task cancels its runner and persists terminal state")
    func cancellationStopsActiveRun() async throws {
        let gate = QueueConcurrencyGate()
        let root = temporaryQueueDirectory()
        let store = TaskQueueStore(rootDirectory: root)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let queue = try TaskQueue(store: store, runHandler: { item in await gate.run(item) })
        _ = try await queue.start()
        let item = try makeQueueItem(id: "cancel")
        _ = try await queue.enqueue(item)
        try await waitUntil { await gate.startedCount == 1 }

        let cancelled = try await queue.cancel(id: item.id)
        await gate.releaseAll()

        #expect(cancelled.status == .cancelled)
        #expect(try store.loadAll().items.first?.status == .cancelled)
    }

    private func makeQueueItem(
        id: String,
        trigger: TaskQueueTrigger = .manual,
        maximumRetries: Int = 0,
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) throws -> TaskQueueItem {
        try TaskQueueItem(
            id: id,
            pipeline: AgentPipeline(
                id: "pipeline-\(id)",
                steps: [AgentPipelineStep(id: "run", provider: .codex, prompt: "Run \(id)")]
            ),
            trigger: trigger,
            maximumRetries: maximumRetries,
            now: now
        )
    }

    private func temporaryQueueDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-queue-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("queue", isDirectory: true)
    }
}

private final class LockedQueueClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(now: Date) {
        storedNow = now
    }

    var now: Date {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { storedNow = storedNow.addingTimeInterval(interval) }
    }
}

private actor QueueRunRecorder {
    private let failuresBeforeSuccess: Int
    private let clock: LockedQueueClock
    private(set) var runCount = 0

    init(failuresBeforeSuccess: Int = 0, clock: LockedQueueClock) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.clock = clock
    }

    func run(_ item: TaskQueueItem) -> AgentPipelineRunSummary {
        runCount += 1
        let succeeds = runCount > failuresBeforeSuccess
        let now = clock.now
        return AgentPipelineRunSummary(
            pipelineID: item.pipeline.id,
            status: succeeds ? .succeeded : .failed,
            stepResults: [AgentPipelineStepResult(
                stepID: item.pipeline.steps[0].id,
                status: succeeds ? .succeeded : .failed,
                output: succeeds ? "done" : nil,
                error: succeeds ? nil : "planned failure",
                startedAt: now,
                finishedAt: now
            )],
            startedAt: now,
            finishedAt: now
        )
    }
}

private actor QueueLifecycleRecorder {
    private var events: [TaskQueueLifecycleEvent] = []

    var kinds: [TaskQueueLifecycleKind] { events.map(\.kind) }

    func record(_ event: TaskQueueLifecycleEvent) {
        events.append(event)
    }
}

private actor QueueConcurrencyGate {
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var startedCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func run(_ item: TaskQueueItem) async -> AgentPipelineRunSummary {
        active += 1
        startedCount += 1
        maximumActive = max(maximumActive, active)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        active -= 1
        let now = Date()
        return AgentPipelineRunSummary(
            pipelineID: item.pipeline.id,
            status: Task.isCancelled ? .cancelled : .succeeded,
            stepResults: [AgentPipelineStepResult(
                stepID: item.pipeline.steps[0].id,
                status: Task.isCancelled ? .cancelled : .succeeded,
                output: nil,
                error: nil,
                startedAt: now,
                finishedAt: now
            )],
            startedAt: now,
            finishedAt: now
        )
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private func waitForQueueItem(
    _ queue: TaskQueue,
    id: String,
    condition: @escaping (TaskQueueItem) -> Bool
) async throws -> TaskQueueItem {
    var matched: TaskQueueItem?
    try await waitUntil {
        guard let item = await queue.item(id: id), condition(item) else { return false }
        matched = item
        return true
    }
    return try #require(matched)
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for task queue state")
}
