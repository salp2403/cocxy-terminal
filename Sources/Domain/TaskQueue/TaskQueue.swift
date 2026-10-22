// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueue.swift - Persistent trigger, retry, and concurrency orchestration.

import Foundation

actor TaskQueue {
    private struct PendingPersistence: Sendable {
        let item: TaskQueueItem
        let lifecycleEvent: TaskQueueLifecycleEvent
    }

    private let store: any TaskQueueStoring
    private let maximumConcurrentRuns: Int
    private let retryBaseDelay: TimeInterval
    private let eventRetriggerMinimumInterval: TimeInterval
    private let clock: @Sendable () -> Date
    private let runHandler: TaskQueueRunHandler
    private let lifecycleHandler: TaskQueueLifecycleHandler
    private let snapshotHandler: TaskQueueSnapshotHandler

    private var itemsByID: [String: TaskQueueItem] = [:]
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private var pendingPersistenceByID: [String: PendingPersistence] = [:]
    private(set) var loadWarnings: [TaskQueueStoreRejectedFile] = []
    private(set) var lastPersistenceError: String?

    init(
        store: any TaskQueueStoring = TaskQueueStore(),
        maximumConcurrentRuns: Int = 2,
        retryBaseDelay: TimeInterval = 5,
        eventRetriggerMinimumInterval: TimeInterval = 5,
        clock: @escaping @Sendable () -> Date = { Date() },
        runHandler: @escaping TaskQueueRunHandler,
        lifecycleHandler: @escaping TaskQueueLifecycleHandler = { _ in },
        snapshotHandler: @escaping TaskQueueSnapshotHandler = { _ in }
    ) throws {
        guard (1...8).contains(maximumConcurrentRuns) else {
            throw TaskQueueError.invalidConcurrency(maximumConcurrentRuns)
        }
        self.store = store
        self.maximumConcurrentRuns = maximumConcurrentRuns
        self.retryBaseDelay = max(1, retryBaseDelay)
        self.eventRetriggerMinimumInterval = max(0, eventRetriggerMinimumInterval)
        self.clock = clock
        self.runHandler = runHandler
        self.lifecycleHandler = lifecycleHandler
        self.snapshotHandler = snapshotHandler
    }

    @discardableResult
    func start() async throws -> TaskQueueStoreLoadReport {
        let report = try store.loadAll()
        loadWarnings = report.rejectedFiles
        itemsByID = Dictionary(uniqueKeysWithValues: report.items.map { ($0.id, $0) })
        let now = clock()
        for itemID in itemsByID.keys.sorted() {
            guard var item = itemsByID[itemID], item.status == .running else { continue }
            item.updatedAt = now
            item.lastError = "The previous app session ended while this task was running"
            if item.retryAttempt <= item.maximumRetries {
                item.status = .queued
                item.nextRunAt = now
            } else if item.trigger.isRecurring {
                rescheduleRecurringItem(&item, after: now)
            } else {
                item.status = .failed
                item.completedAt = now
            }
            itemsByID[itemID] = item
            try store.save(item)
        }
        drainEligibleRuns(at: now)
        await publishSnapshot()
        return report
    }

    @discardableResult
    func enqueue(_ item: TaskQueueItem) async throws -> TaskQueueItem {
        guard itemsByID[item.id] == nil else {
            throw TaskQueueError.duplicateTask(item.id)
        }
        try store.save(item)
        itemsByID[item.id] = item
        drainEligibleRuns(at: clock())
        await publishSnapshot()
        return item
    }

    func list() -> [TaskQueueItem] {
        itemsByID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    func item(id rawID: String) -> TaskQueueItem? {
        itemsByID[AgentTeamConfig.slug(rawID)]
    }

    @discardableResult
    func cancel(id rawID: String) async throws -> TaskQueueItem {
        let taskID = AgentTeamConfig.slug(rawID)
        guard pendingPersistenceByID[taskID] == nil else {
            throw TaskQueueError.persistencePending(taskID)
        }
        guard var item = itemsByID[taskID] else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        guard !item.status.isFinished else {
            throw TaskQueueError.taskAlreadyFinished(taskID)
        }

        let wasRunning = item.status == .running
        let now = clock()
        item.status = .cancelled
        item.updatedAt = now
        item.completedAt = now
        item.nextRunAt = nil
        item.pendingRun = false
        item.lastError = "Cancelled by user"
        try store.save(item)
        itemsByID[taskID] = item
        activeRuns[taskID]?.cancel()

        if wasRunning {
            Task {
                await lifecycleHandler(TaskQueueLifecycleEvent(
                    kind: .finished,
                    taskID: item.id,
                    pipelineID: item.pipeline.id,
                    status: .cancelled,
                    attempt: item.retryAttempt,
                    occurredAt: now
                ))
            }
        }
        if !wasRunning {
            drainEligibleRuns(at: now)
        }
        await publishSnapshot()
        return item
    }

    @discardableResult
    func rerun(id rawID: String) async throws -> TaskQueueItem {
        let taskID = AgentTeamConfig.slug(rawID)
        guard pendingPersistenceByID[taskID] == nil else {
            throw TaskQueueError.persistencePending(taskID)
        }
        guard var item = itemsByID[taskID] else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        guard item.status.isFinished else {
            throw TaskQueueError.taskNotFinished(taskID)
        }

        let now = clock()
        item.status = .queued
        item.updatedAt = now
        item.nextRunAt = now
        item.completedAt = nil
        item.retryAttempt = 0
        item.pendingRun = false
        item.lastError = nil
        try store.save(item)
        itemsByID[taskID] = item
        drainEligibleRuns(at: now)
        await publishSnapshot()
        return item
    }

    @discardableResult
    func remove(id rawID: String) async throws -> TaskQueueItem {
        let taskID = AgentTeamConfig.slug(rawID)
        guard pendingPersistenceByID[taskID] == nil else {
            throw TaskQueueError.persistencePending(taskID)
        }
        guard let item = itemsByID[taskID] else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        guard item.status.isFinished else {
            throw TaskQueueError.taskNotFinished(taskID)
        }

        try store.remove(taskID: taskID)
        itemsByID.removeValue(forKey: taskID)
        await publishSnapshot()
        return item
    }

    func handlePluginEvent(_ event: PluginEvent, at date: Date? = nil) async {
        guard TaskQueueTrigger.supportedEvents.contains(event) else {
            return
        }
        let now = date ?? clock()
        for taskID in itemsByID.keys.sorted() {
            guard var item = itemsByID[taskID],
                  pendingPersistenceByID[taskID] == nil,
                  case .event(let expectedEvent) = item.trigger,
                  expectedEvent == event,
                  !item.status.isFinished else {
                continue
            }
            if item.status == .running || item.status == .retrying || item.status == .queued {
                item.pendingRun = true
            } else {
                item.retryAttempt = 0
                item.status = .queued
                item.nextRunAt = earliestEventRunDate(for: item, after: now)
            }
            item.updatedAt = now
            if persist(item) {
                itemsByID[taskID] = item
            }
        }
        drainEligibleRuns(at: now)
        await publishSnapshot()
    }

    func tick(at date: Date? = nil) async {
        let now = date ?? clock()
        await flushPendingPersistence()
        for taskID in itemsByID.keys.sorted() {
            guard var item = itemsByID[taskID], !item.status.isFinished else { continue }
            switch item.status {
            case .scheduled, .retrying:
                guard let nextRunAt = item.nextRunAt, nextRunAt <= now else { continue }
                if item.status == .scheduled {
                    item.retryAttempt = 0
                }
                item.status = .queued
                item.updatedAt = now
                if persist(item) {
                    itemsByID[taskID] = item
                }
            case .queued, .running, .succeeded, .failed, .cancelled:
                continue
            }
        }
        drainEligibleRuns(at: now)
        await publishSnapshot()
    }

    func shutdown() {
        for task in activeRuns.values {
            task.cancel()
        }
        activeRuns.removeAll()
    }

    private func drainEligibleRuns(at now: Date) {
        guard activeRuns.count < maximumConcurrentRuns else { return }
        let eligibleIDs = itemsByID.values
            .filter { item in
                pendingPersistenceByID[item.id] == nil
                    && item.status == .queued
                    && (item.nextRunAt == nil || item.nextRunAt! <= now)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.nextRunAt ?? lhs.createdAt
                let rhsDate = rhs.nextRunAt ?? rhs.createdAt
                return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate < rhsDate
            }
            .map(\.id)

        for taskID in eligibleIDs.prefix(maximumConcurrentRuns - activeRuns.count) {
            startRun(taskID: taskID, at: now)
        }
    }

    private func startRun(taskID: String, at now: Date) {
        guard var item = itemsByID[taskID], item.status == .queued else { return }
        item.status = .running
        item.updatedAt = now
        item.lastRunAt = now
        item.nextRunAt = nil
        item.retryAttempt += 1
        item.totalRunCount += 1
        item.lastError = nil
        item.completedAt = nil
        guard persist(item) else { return }
        itemsByID[taskID] = item

        let event = TaskQueueLifecycleEvent(
            kind: .started,
            taskID: item.id,
            pipelineID: item.pipeline.id,
            status: .running,
            attempt: item.retryAttempt,
            occurredAt: now
        )
        let runHandler = self.runHandler
        let lifecycleHandler = self.lifecycleHandler
        activeRuns[taskID] = Task { [weak self] in
            await lifecycleHandler(event)
            let summary = await runHandler(item)
            await self?.finishRun(taskID: taskID, summary: summary)
        }
    }

    private func finishRun(taskID: String, summary: AgentPipelineRunSummary) async {
        activeRuns.removeValue(forKey: taskID)
        guard var item = itemsByID[taskID], item.status == .running else {
            drainEligibleRuns(at: clock())
            await publishSnapshot()
            return
        }

        let now = clock()
        let completedAttempt = item.retryAttempt
        item.updatedAt = now
        item.lastSummary = summary
        let succeeded = summary.status == .succeeded
        if succeeded {
            item.lastError = nil
            item.retryAttempt = 0
            if item.pendingRun {
                item.pendingRun = false
                item.status = .queued
                item.nextRunAt = earliestEventRunDate(for: item, after: now)
            } else if item.trigger.isRecurring {
                rescheduleRecurringItem(&item, after: now)
            } else {
                item.status = .succeeded
                item.completedAt = now
            }
        } else {
            item.lastError = summary.stepResults
                .compactMap(\.error)
                .first ?? "Agent pipeline did not complete successfully"
            if item.retryAttempt <= item.maximumRetries {
                item.status = .retrying
                item.nextRunAt = now.addingTimeInterval(retryDelay(for: item.retryAttempt))
            } else if item.pendingRun {
                item.pendingRun = false
                item.retryAttempt = 0
                item.status = .queued
                item.nextRunAt = earliestEventRunDate(for: item, after: now)
            } else if item.trigger.isRecurring {
                item.retryAttempt = 0
                rescheduleRecurringItem(&item, after: now)
            } else {
                item.status = summary.status == .cancelled ? .cancelled : .failed
                item.completedAt = now
            }
        }

        itemsByID[taskID] = item
        let lifecycleEvent = TaskQueueLifecycleEvent(
            kind: .finished,
            taskID: item.id,
            pipelineID: item.pipeline.id,
            status: item.status,
            attempt: max(1, completedAttempt),
            occurredAt: now
        )
        if persist(item) {
            await lifecycleHandler(lifecycleEvent)
            drainEligibleRuns(at: now)
        } else {
            pendingPersistenceByID[taskID] = PendingPersistence(
                item: item,
                lifecycleEvent: lifecycleEvent
            )
        }
        await publishSnapshot()
    }

    private func rescheduleRecurringItem(_ item: inout TaskQueueItem, after now: Date) {
        item.status = .scheduled
        item.completedAt = nil
        switch item.trigger {
        case .manual:
            item.nextRunAt = nil
        case .cron(let schedule):
            if let nextDate = schedule.nextDate(after: now) {
                item.nextRunAt = nextDate
            } else {
                item.status = .failed
                item.completedAt = now
                item.nextRunAt = nil
                item.lastError = TaskQueueError.cronHasNoFutureDate(schedule.expression).description
            }
        case .event:
            item.nextRunAt = nil
        }
    }

    private func retryDelay(for attempt: Int) -> TimeInterval {
        min(retryBaseDelay * pow(2, Double(max(0, attempt - 1))), 300)
    }

    private func earliestEventRunDate(
        for item: TaskQueueItem,
        after now: Date
    ) -> Date {
        guard case .event = item.trigger,
              let lastRunAt = item.lastRunAt else {
            return now
        }
        return max(now, lastRunAt.addingTimeInterval(eventRetriggerMinimumInterval))
    }

    @discardableResult
    private func persist(_ item: TaskQueueItem) -> Bool {
        do {
            try store.save(item)
            if pendingPersistenceByID.isEmpty {
                lastPersistenceError = nil
            }
            return true
        } catch {
            lastPersistenceError = String(describing: error)
            return false
        }
    }

    private func flushPendingPersistence() async {
        for taskID in pendingPersistenceByID.keys.sorted() {
            guard let pending = pendingPersistenceByID[taskID], persist(pending.item) else {
                continue
            }
            pendingPersistenceByID.removeValue(forKey: taskID)
            if pendingPersistenceByID.isEmpty {
                lastPersistenceError = nil
            }
            await lifecycleHandler(pending.lifecycleEvent)
        }
    }

    private func publishSnapshot() async {
        await snapshotHandler(list())
    }
}

private extension TaskQueueTrigger {
    var isRecurring: Bool {
        switch self {
        case .manual: return false
        case .cron, .event: return true
        }
    }
}
