// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueue.swift - Persistent trigger, retry, and concurrency orchestration.

import Foundation

enum TaskQueueError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyTaskID
    case taskIDTooLong(maximumBytes: Int)
    case duplicateTask(String)
    case taskNotFound(String)
    case taskAlreadyFinished(String)
    case invalidMaximumRetries(Int)
    case invalidConcurrency(Int)
    case unsupportedEventTrigger(String)
    case cronHasNoFutureDate(String)
    case invalidPersistedState(String)

    var description: String {
        switch self {
        case .emptyTaskID:
            return "Queued task id cannot be empty"
        case .taskIDTooLong(let maximumBytes):
            return "Queued task id cannot exceed \(maximumBytes) UTF-8 bytes"
        case .duplicateTask(let taskID):
            return "Queued task already exists: \(taskID)"
        case .taskNotFound(let taskID):
            return "Queued task not found: \(taskID)"
        case .taskAlreadyFinished(let taskID):
            return "Queued task is already finished: \(taskID)"
        case .invalidMaximumRetries(let value):
            return "Queued task retries must be between 0 and 5, got \(value)"
        case .invalidConcurrency(let value):
            return "Task queue concurrency must be between 1 and 8, got \(value)"
        case .unsupportedEventTrigger(let event):
            return "Plugin event cannot trigger queued tasks: \(event)"
        case .cronHasNoFutureDate(let expression):
            return "Cron expression has no future date in the supported search window: \(expression)"
        case .invalidPersistedState(let reason):
            return "Queued task persistence is invalid: \(reason)"
        }
    }
}

enum TaskQueueTrigger: Codable, Sendable, Equatable {
    case manual
    case cron(CronSchedule)
    case event(PluginEvent)

    enum Kind: String, Codable, Sendable, Equatable {
        case manual
        case cron
        case event
    }

    var kind: Kind {
        switch self {
        case .manual: return .manual
        case .cron: return .cron
        case .event: return .event
        }
    }

    static func eventTrigger(_ event: PluginEvent) throws -> TaskQueueTrigger {
        guard event.rawValue != "task-run-started",
              event.rawValue != "task-run-finished" else {
            throw TaskQueueError.unsupportedEventTrigger(event.rawValue)
        }
        return .event(event)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case schedule
        case event
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .manual:
            self = .manual
        case .cron:
            self = .cron(try container.decode(CronSchedule.self, forKey: .schedule))
        case .event:
            let event = try container.decode(PluginEvent.self, forKey: .event)
            self = try Self.eventTrigger(event)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .manual:
            break
        case .cron(let schedule):
            try container.encode(schedule, forKey: .schedule)
        case .event(let event):
            try container.encode(event, forKey: .event)
        }
    }
}

enum TaskQueueItemStatus: String, Codable, Sendable, Equatable {
    case scheduled
    case queued
    case running
    case retrying
    case succeeded
    case failed
    case cancelled

    var isFinished: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }
}

struct TaskQueueItem: Identifiable, Codable, Sendable, Equatable {
    static let maximumIDBytes = 128

    let id: String
    let pipeline: AgentPipeline
    let trigger: TaskQueueTrigger
    let maximumRetries: Int
    let maximumParallelSteps: Int
    let createdAt: Date

    var status: TaskQueueItemStatus
    var updatedAt: Date
    var nextRunAt: Date?
    var lastRunAt: Date?
    var completedAt: Date?
    var retryAttempt: Int
    var totalRunCount: Int
    var pendingRun: Bool
    var lastError: String?
    var lastSummary: AgentPipelineRunSummary?

    init(
        id: String,
        pipeline: AgentPipeline,
        trigger: TaskQueueTrigger,
        maximumRetries: Int = 0,
        maximumParallelSteps: Int = 2,
        now: Date = Date()
    ) throws {
        let normalizedID = AgentPipelineStep.normalizedID(id)
        guard !normalizedID.isEmpty else { throw TaskQueueError.emptyTaskID }
        guard normalizedID.utf8.count <= Self.maximumIDBytes else {
            throw TaskQueueError.taskIDTooLong(maximumBytes: Self.maximumIDBytes)
        }
        guard (0...5).contains(maximumRetries) else {
            throw TaskQueueError.invalidMaximumRetries(maximumRetries)
        }
        guard (1...8).contains(maximumParallelSteps) else {
            throw TaskQueueError.invalidConcurrency(maximumParallelSteps)
        }

        self.id = normalizedID
        self.pipeline = pipeline
        self.trigger = trigger
        try Self.validateTrigger(trigger)
        self.maximumRetries = maximumRetries
        self.maximumParallelSteps = maximumParallelSteps
        createdAt = now
        updatedAt = now
        lastRunAt = nil
        completedAt = nil
        retryAttempt = 0
        totalRunCount = 0
        pendingRun = false
        lastError = nil
        lastSummary = nil

        switch trigger {
        case .manual:
            status = .queued
            nextRunAt = now
        case .cron(let schedule):
            guard let nextDate = schedule.nextDate(after: now) else {
                throw TaskQueueError.cronHasNoFutureDate(schedule.expression)
            }
            status = .scheduled
            nextRunAt = nextDate
        case .event:
            status = .scheduled
            nextRunAt = nil
        }
    }

    var displayName: String {
        pipeline.name ?? pipeline.id
    }

    func validatePersistedState() throws {
        guard !id.isEmpty, id == AgentPipelineStep.normalizedID(id) else {
            throw TaskQueueError.invalidPersistedState("invalid task id")
        }
        guard id.utf8.count <= Self.maximumIDBytes else {
            throw TaskQueueError.taskIDTooLong(maximumBytes: Self.maximumIDBytes)
        }
        guard (0...5).contains(maximumRetries) else {
            throw TaskQueueError.invalidMaximumRetries(maximumRetries)
        }
        guard (1...8).contains(maximumParallelSteps) else {
            throw TaskQueueError.invalidConcurrency(maximumParallelSteps)
        }
        guard retryAttempt >= 0, totalRunCount >= 0 else {
            throw TaskQueueError.invalidPersistedState("negative run counter")
        }
        try Self.validateTrigger(trigger)
    }

    private static func validateTrigger(_ trigger: TaskQueueTrigger) throws {
        if case .event(let event) = trigger {
            _ = try TaskQueueTrigger.eventTrigger(event)
        }
    }
}

enum TaskQueueLifecycleKind: String, Sendable, Equatable {
    case started
    case finished
}

struct TaskQueueLifecycleEvent: Sendable, Equatable {
    let kind: TaskQueueLifecycleKind
    let taskID: String
    let pipelineID: String
    let status: TaskQueueItemStatus
    let attempt: Int
    let occurredAt: Date
}

typealias TaskQueueRunHandler = @Sendable (
    _ item: TaskQueueItem
) async -> AgentPipelineRunSummary

typealias TaskQueueLifecycleHandler = @Sendable (
    _ event: TaskQueueLifecycleEvent
) async -> Void

actor TaskQueue {
    private let store: TaskQueueStore
    private let maximumConcurrentRuns: Int
    private let retryBaseDelay: TimeInterval
    private let clock: @Sendable () -> Date
    private let runHandler: TaskQueueRunHandler
    private let lifecycleHandler: TaskQueueLifecycleHandler

    private var itemsByID: [String: TaskQueueItem] = [:]
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private(set) var loadWarnings: [TaskQueueStoreRejectedFile] = []
    private(set) var lastPersistenceError: String?

    init(
        store: TaskQueueStore = TaskQueueStore(),
        maximumConcurrentRuns: Int = 2,
        retryBaseDelay: TimeInterval = 5,
        clock: @escaping @Sendable () -> Date = { Date() },
        runHandler: @escaping TaskQueueRunHandler,
        lifecycleHandler: @escaping TaskQueueLifecycleHandler = { _ in }
    ) throws {
        guard (1...8).contains(maximumConcurrentRuns) else {
            throw TaskQueueError.invalidConcurrency(maximumConcurrentRuns)
        }
        self.store = store
        self.maximumConcurrentRuns = maximumConcurrentRuns
        self.retryBaseDelay = max(1, retryBaseDelay)
        self.clock = clock
        self.runHandler = runHandler
        self.lifecycleHandler = lifecycleHandler
    }

    @discardableResult
    func start() throws -> TaskQueueStoreLoadReport {
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
        return report
    }

    @discardableResult
    func enqueue(_ item: TaskQueueItem) throws -> TaskQueueItem {
        guard itemsByID[item.id] == nil else {
            throw TaskQueueError.duplicateTask(item.id)
        }
        try store.save(item)
        itemsByID[item.id] = item
        drainEligibleRuns(at: clock())
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
    func cancel(id rawID: String) throws -> TaskQueueItem {
        let taskID = AgentTeamConfig.slug(rawID)
        guard var item = itemsByID[taskID] else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        guard !item.status.isFinished else {
            throw TaskQueueError.taskAlreadyFinished(taskID)
        }

        let wasRunning = item.status == .running
        activeRuns[taskID]?.cancel()
        let now = clock()
        item.status = .cancelled
        item.updatedAt = now
        item.completedAt = now
        item.nextRunAt = nil
        item.pendingRun = false
        item.lastError = "Cancelled by user"
        try store.save(item)
        itemsByID[taskID] = item

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
        return item
    }

    func handlePluginEvent(_ event: PluginEvent, at date: Date? = nil) {
        guard event.rawValue != "task-run-started",
              event.rawValue != "task-run-finished" else {
            return
        }
        let now = date ?? clock()
        for taskID in itemsByID.keys.sorted() {
            guard var item = itemsByID[taskID],
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
                item.nextRunAt = now
            }
            item.updatedAt = now
            persistBestEffort(item)
            itemsByID[taskID] = item
        }
        drainEligibleRuns(at: now)
    }

    func tick(at date: Date? = nil) {
        let now = date ?? clock()
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
                persistBestEffort(item)
                itemsByID[taskID] = item
            case .queued, .running, .succeeded, .failed, .cancelled:
                continue
            }
        }
        drainEligibleRuns(at: now)
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
                item.status == .queued && (item.nextRunAt == nil || item.nextRunAt! <= now)
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
        persistBestEffort(item)
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
                item.nextRunAt = now
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
                item.nextRunAt = now
            } else if item.trigger.isRecurring {
                item.retryAttempt = 0
                rescheduleRecurringItem(&item, after: now)
            } else {
                item.status = summary.status == .cancelled ? .cancelled : .failed
                item.completedAt = now
            }
        }

        persistBestEffort(item)
        itemsByID[taskID] = item
        await lifecycleHandler(TaskQueueLifecycleEvent(
            kind: .finished,
            taskID: item.id,
            pipelineID: item.pipeline.id,
            status: item.status,
            attempt: max(1, completedAttempt),
            occurredAt: now
        ))
        drainEligibleRuns(at: now)
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

    private func persistBestEffort(_ item: TaskQueueItem) {
        do {
            try store.save(item)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = String(describing: error)
        }
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
