// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueItem.swift - Persistent queued task state.

import Foundation

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
    let project: String?
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
        project: String? = nil,
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
        let normalizedProject = project?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.project = normalizedProject?.isEmpty == false ? normalizedProject : nil
        try Self.validateProject(self.project)
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
        try Self.validateProject(project)
        try Self.validateTrigger(trigger)
    }

    private static func validateProject(_ project: String?) throws {
        guard let project else { return }
        guard NSString(string: project).isAbsolutePath,
              !project.contains("\0"),
              project.utf8.count <= AgentPipelineStep.maximumWorktreePathBytes else {
            throw TaskQueueError.invalidPersistedState("invalid project path")
        }
    }

    private static func validateTrigger(_ trigger: TaskQueueTrigger) throws {
        if case .event(let event) = trigger {
            _ = try TaskQueueTrigger.eventTrigger(event)
        }
    }
}
