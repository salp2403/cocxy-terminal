// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityModels.swift - Local-only activity and token usage values.

import Foundation

enum ActivityEventKind: String, Codable, Sendable, CaseIterable, Equatable {
    case commandExecuted = "command_executed"
    case tabOpened = "tab_opened"
    case splitCreated = "split_created"
    case agentInvoked = "agent_invoked"
    case blockFinished = "block_finished"
    case errorEncountered = "error_encountered"
    case projectSwitched = "project_switched"
}

struct ActivityProjectRef: Codable, Sendable, Equatable, Hashable {
    let id: String
    let name: String
    let legacyID: String?
    let projectIdentity: ProjectID?

    init(
        id: String,
        name: String,
        legacyID: String? = nil,
        projectIdentity: ProjectID? = nil
    ) {
        self.id = id
        self.name = name
        self.legacyID = legacyID
        self.projectIdentity = projectIdentity
    }

    static func workingDirectory(_ url: URL) -> ActivityProjectRef {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent.isEmpty
            ? standardized.path
            : standardized.lastPathComponent
        return ActivityProjectRef(
            id: "local-\(StableActivityHash.hexDigest(for: standardized.path))",
            name: name
        )
    }

    static func resolvedProject(
        _ descriptor: ProjectDescriptor,
        workingDirectory: URL
    ) -> ActivityProjectRef {
        let groupingID = descriptor.groupingID
        let legacy = ActivityProjectRef.workingDirectory(workingDirectory)
        return ActivityProjectRef(
            id: groupingID.rawValue,
            name: descriptor.parent == nil
                ? descriptor.displayName
                : descriptor.groupingAutomaticName,
            legacyID: legacy.id,
            projectIdentity: groupingID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case legacyID
        case projectIdentity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        legacyID = try container.decodeIfPresent(String.self, forKey: .legacyID)
        projectIdentity = try container.decodeIfPresent(ProjectID.self, forKey: .projectIdentity)
    }
}

struct ActivityEvent: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: ActivityEventKind
    let sessionID: String?
    let project: ActivityProjectRef?
    let summary: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: ActivityEventKind,
        sessionID: String? = nil,
        project: ActivityProjectRef? = nil,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.sessionID = sessionID
        self.project = project
        self.summary = summary
        self.metadata = metadata
    }
}

struct TokenUsageRecord: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let provider: String
    let model: String
    let sessionID: String?
    let project: ActivityProjectRef?
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostMicros: Int64

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        provider: String,
        model: String,
        sessionID: String? = nil,
        project: ActivityProjectRef? = nil,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCostMicros: Int64
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.sessionID = sessionID
        self.project = project
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.estimatedCostMicros = max(0, estimatedCostMicros)
    }
}

struct TokenCostRate: Codable, Sendable, Equatable {
    let provider: String
    let model: String
    let inputMicrosPerMillionTokens: Int64
    let outputMicrosPerMillionTokens: Int64

    init(
        provider: String,
        model: String,
        inputMicrosPerMillionTokens: Int64,
        outputMicrosPerMillionTokens: Int64
    ) {
        self.provider = provider
        self.model = model
        self.inputMicrosPerMillionTokens = max(0, inputMicrosPerMillionTokens)
        self.outputMicrosPerMillionTokens = max(0, outputMicrosPerMillionTokens)
    }
}

struct ActivityStoreQuery: Sendable, Equatable {
    let dateInterval: DateInterval?
    let projectID: String?
    let sessionID: String?

    init(
        dateInterval: DateInterval? = nil,
        projectID: String? = nil,
        sessionID: String? = nil
    ) {
        self.dateInterval = dateInterval
        self.projectID = projectID
        self.sessionID = sessionID
    }
}

struct ActivityEventCount: Sendable, Equatable {
    let kind: ActivityEventKind
    let count: Int
}

struct TokenUsageBucket: Sendable, Equatable {
    let day: Date
    let inputTokens: Int
    let outputTokens: Int
    let totalCostMicros: Int64
}

struct CostBreakdown: Sendable, Equatable {
    let provider: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalCostMicros: Int64
}

struct ProjectTimeBreakdown: Sendable, Equatable {
    let project: ActivityProjectRef
    let durationMilliseconds: Int64
}

struct ProjectActivityMetrics: Sendable, Equatable {
    let durationMilliseconds: Int64
    let totalTokens: Int
    let totalCostMicros: Int64

    static let zero = ProjectActivityMetrics(
        durationMilliseconds: 0,
        totalTokens: 0,
        totalCostMicros: 0
    )
}

struct ProjectActivitySummary: Sendable, Equatable {
    let week: ProjectActivityMetrics
    let month: ProjectActivityMetrics
}

struct ProductivityInsights: Sendable, Equatable {
    let mostUsedCommands: [String]
    let peakHour: Int?
    let projectSwitches: Int
}

private enum StableActivityHash {
    static func hexDigest(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}
