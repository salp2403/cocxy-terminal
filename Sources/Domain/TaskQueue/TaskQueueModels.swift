// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueModels.swift - Task queue triggers, lifecycle events, and errors.

import Foundation

enum TaskQueueError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyTaskID
    case taskIDTooLong(maximumBytes: Int)
    case duplicateTask(String)
    case taskNotFound(String)
    case taskAlreadyFinished(String)
    case taskNotFinished(String)
    case persistencePending(String)
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
        case .taskNotFinished(let taskID):
            return "Queued task must be finished before this operation: \(taskID)"
        case .persistencePending(let taskID):
            return "Queued task is waiting for durable persistence: \(taskID)"
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

    static let supportedEvents: [PluginEvent] = [
        .sessionStart,
        .sessionEnd,
        .richInputSubmit,
        .tabCreated,
        .tabClosed,
    ]

    static func eventTrigger(_ event: PluginEvent) throws -> TaskQueueTrigger {
        guard supportedEvents.contains(event) else {
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

typealias TaskQueueSnapshotHandler = @Sendable (
    _ items: [TaskQueueItem]
) async -> Void
