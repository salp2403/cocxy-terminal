// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamRunState.swift - Runtime projection for team hooks, snapshots, and review handoff.

import Foundation

struct AgentTeamReviewBeforeShipRequest: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let teamID: String
    let sessionID: String
    let teammateID: String?
    let workingDirectory: String?
    let touchedFiles: [String]
    let sourceEvent: HookEventType
    let createdAt: Date
}

struct AgentTeamRunEventResult: Sendable, Equatable {
    let accepted: Bool
    let linkedSubagentID: String?
    let touchedFilePath: String?
    let reviewBeforeShipRequest: AgentTeamReviewBeforeShipRequest?

    static let ignored = AgentTeamRunEventResult(
        accepted: false,
        linkedSubagentID: nil,
        touchedFilePath: nil,
        reviewBeforeShipRequest: nil
    )
}

struct AgentTeamRunState: Codable, Sendable, Equatable {
    let config: AgentTeamConfig
    var coordinator: AgentTeamCoordinator
    var graph: AgentTeamGraph
    var feed: AgentTeamFeed
    let launchSpecs: [AgentTeamProviderLaunchSpec]
    private(set) var reviewBeforeShipRequests: [AgentTeamReviewBeforeShipRequest]
    let createdAt: Date
    private(set) var updatedAt: Date

    init(
        config: AgentTeamConfig,
        launchSpecs: [AgentTeamProviderLaunchSpec],
        now: Date = Date()
    ) {
        self.config = config
        self.coordinator = AgentTeamCoordinator(config: config)
        self.graph = AgentTeamGraph(config: config, now: now)
        self.feed = AgentTeamFeed(config: config)
        self.launchSpecs = launchSpecs
        self.reviewBeforeShipRequests = []
        self.createdAt = now
        self.updatedAt = now
    }

    mutating func apply(_ event: HookEvent) throws -> AgentTeamRunEventResult {
        guard accepts(event) else {
            return .ignored
        }

        updatedAt = event.timestamp

        switch event.type {
        case .sessionStart:
            try updateKnownTeammateStatus(from: event, status: .working)
            return AgentTeamRunEventResult(
                accepted: true,
                linkedSubagentID: nil,
                touchedFilePath: nil,
                reviewBeforeShipRequest: nil
            )

        case .subagentStart:
            guard case .subagent(let data) = event.data else {
                return acceptedResult()
            }
            let subagentID = data.subagentId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subagentID.isEmpty else {
                return acceptedResult()
            }
            let parentID = event.teammateID ?? config.id
            let subagentName = data.subagentType ?? event.teammateName ?? subagentID
            try graph.linkSubagent(
                parentID: parentID,
                subagentID: subagentID,
                name: subagentName,
                provider: config.provider,
                status: .working,
                now: event.timestamp
            )
            try feed.linkTeammate(id: subagentID, name: subagentName)
            _ = try feed.record(
                teammateID: subagentID,
                kind: .status,
                message: "Subagent started",
                createdAt: event.timestamp,
                metadata: [
                    "parentID": parentID,
                    "sessionID": event.sessionId,
                ]
            )
            return AgentTeamRunEventResult(
                accepted: true,
                linkedSubagentID: subagentID,
                touchedFilePath: nil,
                reviewBeforeShipRequest: nil
            )

        case .subagentStop:
            guard case .subagent(let data) = event.data else {
                return acceptedResult()
            }
            let subagentID = data.subagentId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subagentID.isEmpty else {
                return acceptedResult()
            }
            try ensureNode(id: subagentID, name: data.subagentType ?? event.teammateName, status: .finished, event: event)
            _ = try feed.record(
                teammateID: subagentID,
                kind: .completion,
                message: "Subagent finished",
                createdAt: event.timestamp,
                metadata: ["sessionID": event.sessionId]
            )
            return acceptedResult()

        case .preToolUse, .postToolUse, .postToolUseFailure:
            return try applyToolEvent(event)

        case .teammateIdle:
            try updateKnownTeammateStatus(from: event, status: .waiting)
            return acceptedResult()

        case .taskCompleted, .sessionEnd, .stop:
            if let teammateID = event.teammateID {
                try ensureNode(id: teammateID, name: event.teammateName, status: .finished, event: event)
                _ = try feed.record(
                    teammateID: teammateID,
                    kind: .completion,
                    message: completionMessage(for: event),
                    createdAt: event.timestamp,
                    metadata: ["sessionID": event.sessionId]
                )
            }
            let request = makeReviewBeforeShipRequestIfNeeded(from: event)
            return AgentTeamRunEventResult(
                accepted: true,
                linkedSubagentID: nil,
                touchedFilePath: nil,
                reviewBeforeShipRequest: request
            )

        case .notification, .userPromptSubmit, .cwdChanged, .fileChanged, .richInputDraftSubmitted:
            return acceptedResult()
        }
    }

    func snapshot() -> AgentTeamSessionSnapshot {
        AgentTeamSessionSnapshot(
            config: config,
            graph: graph,
            feed: feed,
            launchSpecs: launchSpecs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func accepts(_ event: HookEvent) -> Bool {
        if let eventTeamID = event.teamID.map(AgentTeamConfig.slug) {
            return eventTeamID == config.id
        }
        return event.sessionId == config.id
    }

    private mutating func applyToolEvent(_ event: HookEvent) throws -> AgentTeamRunEventResult {
        guard let teammateID = event.teammateID else {
            return acceptedResult()
        }
        try ensureNode(id: teammateID, name: event.teammateName, status: .working, event: event)

        guard case .toolUse(let toolData) = event.data else {
            return acceptedResult()
        }

        if event.type == .postToolUseFailure {
            _ = try feed.record(
                teammateID: teammateID,
                kind: .error,
                message: toolData.error ?? "\(toolData.toolName) failed",
                createdAt: event.timestamp,
                metadata: ["tool": toolData.toolName, "sessionID": event.sessionId]
            )
            return acceptedResult()
        }

        let touchedPath = normalizedFilePath(from: toolData)
        if let touchedPath {
            try graph.recordTouchedFile(nodeID: teammateID, path: touchedPath, now: event.timestamp)
            _ = try feed.record(
                teammateID: teammateID,
                kind: .fileTouched,
                message: touchedPath,
                createdAt: event.timestamp,
                metadata: ["tool": toolData.toolName, "sessionID": event.sessionId]
            )
        } else {
            _ = try feed.record(
                teammateID: teammateID,
                kind: .status,
                message: toolData.toolName,
                createdAt: event.timestamp,
                metadata: ["sessionID": event.sessionId]
            )
        }

        return AgentTeamRunEventResult(
            accepted: true,
            linkedSubagentID: nil,
            touchedFilePath: touchedPath,
            reviewBeforeShipRequest: nil
        )
    }

    private mutating func updateKnownTeammateStatus(from event: HookEvent, status: AgentTeamStatus) throws {
        guard let teammateID = event.teammateID else { return }
        try ensureNode(id: teammateID, name: event.teammateName, status: status, event: event)
        _ = try feed.record(
            teammateID: teammateID,
            kind: .status,
            message: status.rawValue,
            createdAt: event.timestamp,
            metadata: ["sessionID": event.sessionId]
        )
        if config.teammates.contains(where: { $0.id == teammateID }) {
            try coordinator.updateStatus(teammateID: teammateID, status: status, now: event.timestamp)
        }
    }

    private mutating func ensureNode(
        id rawID: String,
        name: String?,
        status: AgentTeamStatus,
        event: HookEvent
    ) throws {
        let nodeID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else {
            throw AgentTeamGraphError.emptyNodeID
        }

        if graph.node(id: nodeID) == nil {
            let parentID = event.teammateID == nodeID ? config.id : event.teammateID ?? config.id
            try graph.linkSubagent(
                parentID: parentID,
                subagentID: nodeID,
                name: name,
                provider: config.provider,
                status: status,
                now: event.timestamp
            )
        } else {
            try graph.updateStatus(nodeID: nodeID, status: status, now: event.timestamp)
        }
        try feed.linkTeammate(id: nodeID, name: name)
    }

    private mutating func makeReviewBeforeShipRequestIfNeeded(
        from event: HookEvent
    ) -> AgentTeamReviewBeforeShipRequest? {
        let touchedFiles = Array(Set(graph.nodes.flatMap(\.touchedFiles))).sorted()
        guard !touchedFiles.isEmpty else { return nil }

        let id = "\(config.id):\(event.sessionId):review-before-ship"
        if let existing = reviewBeforeShipRequests.first(where: { $0.id == id }) {
            return existing
        }

        let request = AgentTeamReviewBeforeShipRequest(
            id: id,
            teamID: config.id,
            sessionID: event.sessionId,
            teammateID: event.teammateID,
            workingDirectory: event.cwd,
            touchedFiles: touchedFiles,
            sourceEvent: event.type,
            createdAt: event.timestamp
        )
        reviewBeforeShipRequests.append(request)
        return request
    }

    private func normalizedFilePath(from toolData: ToolUseData) -> String? {
        let rawPath = toolData.toolInput?["file_path"] ?? toolData.toolInput?["path"]
        guard let path = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private func completionMessage(for event: HookEvent) -> String {
        guard case .taskCompleted(let data) = event.data,
              let description = data.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else {
            return "Team run finished"
        }
        return description
    }

    private func acceptedResult() -> AgentTeamRunEventResult {
        AgentTeamRunEventResult(
            accepted: true,
            linkedSubagentID: nil,
            touchedFilePath: nil,
            reviewBeforeShipRequest: nil
        )
    }
}
