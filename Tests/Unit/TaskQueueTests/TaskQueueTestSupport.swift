// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

final class LockedQueueClock: @unchecked Sendable {
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

final class ControlledTaskQueueStore: TaskQueueStoring, @unchecked Sendable {
    private let base: TaskQueueStore
    private let lock = NSLock()
    private var saveAttempt = 0
    private var failingSaveAttempts: Set<Int>

    init(base: TaskQueueStore, failingSaveAttempts: Set<Int>) {
        self.base = base
        self.failingSaveAttempts = failingSaveAttempts
    }

    func save(_ item: TaskQueueItem) throws {
        let shouldFail = lock.withLock {
            saveAttempt += 1
            return failingSaveAttempts.remove(saveAttempt) != nil
        }
        if shouldFail {
            throw TaskQueueStoreError.persistenceFailed("controlled test failure")
        }
        try base.save(item)
    }

    func loadAll() throws -> TaskQueueStoreLoadReport {
        try base.loadAll()
    }

    func remove(taskID: String) throws {
        try base.remove(taskID: taskID)
    }
}

actor QueueRunRecorder {
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

actor QueueLifecycleRecorder {
    private var events: [TaskQueueLifecycleEvent] = []

    var kinds: [TaskQueueLifecycleKind] { events.map(\.kind) }

    func record(_ event: TaskQueueLifecycleEvent) {
        events.append(event)
    }
}

actor QueueSnapshotRecorder {
    private(set) var snapshots: [[TaskQueueItem]] = []

    func record(_ items: [TaskQueueItem]) {
        snapshots.append(items)
    }
}

actor QueueConcurrencyGate {
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

func waitForQueueItem(
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

func waitUntil(
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
