// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueItemCodable.swift - Backward-compatible queued task decoding.

import Foundation

extension TaskQueueItem {
    private enum CodingKeys: String, CodingKey {
        case id, pipeline, project, trigger
        case maximumRetries, maximumParallelSteps, createdAt
        case status, updatedAt, nextRunAt, lastRunAt, completedAt
        case retryAttempt, totalRunCount, pendingRun, lastError, lastSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        pipeline = try container.decode(AgentPipeline.self, forKey: .pipeline)
        let rawProject = try container.decodeIfPresent(String.self, forKey: .project)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        project = rawProject?.isEmpty == false ? rawProject : nil
        trigger = try container.decode(TaskQueueTrigger.self, forKey: .trigger)
        maximumRetries = try container.decode(Int.self, forKey: .maximumRetries)
        maximumParallelSteps = try container.decode(Int.self, forKey: .maximumParallelSteps)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(TaskQueueItemStatus.self, forKey: .status)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        nextRunAt = try container.decodeIfPresent(Date.self, forKey: .nextRunAt)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        retryAttempt = try container.decode(Int.self, forKey: .retryAttempt)
        totalRunCount = try container.decode(Int.self, forKey: .totalRunCount)
        pendingRun = try container.decode(Bool.self, forKey: .pendingRun)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        lastSummary = try container.decodeIfPresent(
            AgentPipelineRunSummary.self,
            forKey: .lastSummary
        )
        try validatePersistedState()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pipeline, forKey: .pipeline)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(maximumRetries, forKey: .maximumRetries)
        try container.encode(maximumParallelSteps, forKey: .maximumParallelSteps)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(status, forKey: .status)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(nextRunAt, forKey: .nextRunAt)
        try container.encodeIfPresent(lastRunAt, forKey: .lastRunAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(retryAttempt, forKey: .retryAttempt)
        try container.encode(totalRunCount, forKey: .totalRunCount)
        try container.encode(pendingRun, forKey: .pendingRun)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(lastSummary, forKey: .lastSummary)
    }
}
