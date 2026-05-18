// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamFeed.swift - Per-agent chronological feed for local team orchestration.

import Foundation

enum AgentTeamFeedEventKind: String, CaseIterable, Codable, Sendable, Equatable {
    case userPrompt = "user-prompt"
    case permissionRequest = "permission-request"
    case error
    case completion
    case status
    case fileTouched = "file-touched"
}

enum AgentTeamFeedError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownTeammate(String)
    case emptyTeammateID

    var description: String {
        switch self {
        case .unknownTeammate(let teammateID):
            return "Unknown agent team feed teammate: \(teammateID)"
        case .emptyTeammateID:
            return "Agent team feed teammate id cannot be empty"
        }
    }
}

struct AgentTeamFeedEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let sequence: Int
    let teammateID: String
    let teammateName: String
    let kind: AgentTeamFeedEventKind
    let message: String
    let createdAt: Date
    let metadata: [String: String]
}

struct AgentTeamFeed: Codable, Sendable, Equatable {
    private var teammatesByID: [String: AgentTeammateConfig]
    private var eventsByTeammateID: [String: [AgentTeamFeedEvent]]
    private var nextSequence: Int

    init(config: AgentTeamConfig) {
        self.teammatesByID = Dictionary(uniqueKeysWithValues: config.teammates.map { ($0.id, $0) })
        self.eventsByTeammateID = Dictionary(uniqueKeysWithValues: config.teammates.map { ($0.id, []) })
        self.nextSequence = 0
    }

    var allEvents: [AgentTeamFeedEvent] {
        eventsByTeammateID.values
            .flatMap { $0 }
            .sorted(by: AgentTeamFeed.sortEvents)
    }

    mutating func linkTeammate(id: String, name: String?) throws {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw AgentTeamFeedError.emptyTeammateID
        }

        let normalizedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? teammatesByID[normalizedID]?.name ?? normalizedID
        teammatesByID[normalizedID] = AgentTeammateConfig(
            id: normalizedID,
            name: normalizedName,
            prompt: teammatesByID[normalizedID]?.prompt
        )
        eventsByTeammateID[normalizedID, default: []] = eventsByTeammateID[normalizedID, default: []]
    }

    @discardableResult
    mutating func record(
        teammateID: String,
        kind: AgentTeamFeedEventKind,
        message: String,
        createdAt: Date = Date(),
        metadata: [String: String] = [:],
        id: UUID = UUID()
    ) throws -> AgentTeamFeedEvent {
        guard let teammate = teammatesByID[teammateID] else {
            throw AgentTeamFeedError.unknownTeammate(teammateID)
        }

        let event = AgentTeamFeedEvent(
            id: id,
            sequence: nextSequence,
            teammateID: teammateID,
            teammateName: teammate.name,
            kind: kind,
            message: message,
            createdAt: createdAt,
            metadata: metadata
        )
        nextSequence += 1
        eventsByTeammateID[teammateID, default: []].append(event)
        return event
    }

    func events(
        for teammateID: String,
        kind: AgentTeamFeedEventKind? = nil,
        matching query: String? = nil
    ) -> [AgentTeamFeedEvent] {
        filtered(eventsByTeammateID[teammateID] ?? [], kind: kind, matching: query)
    }

    func events(kind: AgentTeamFeedEventKind? = nil, matching query: String? = nil) -> [AgentTeamFeedEvent] {
        filtered(allEvents, kind: kind, matching: query)
    }

    private func filtered(
        _ events: [AgentTeamFeedEvent],
        kind: AgentTeamFeedEventKind?,
        matching query: String?
    ) -> [AgentTeamFeedEvent] {
        let normalizedQuery = query?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return events
            .sorted(by: AgentTeamFeed.sortEvents)
            .filter { event in
                if let kind, event.kind != kind {
                    return false
                }
                guard let normalizedQuery, !normalizedQuery.isEmpty else {
                    return true
                }
                return event.searchText.contains(normalizedQuery)
            }
    }

    private static func sortEvents(_ lhs: AgentTeamFeedEvent, _ rhs: AgentTeamFeedEvent) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.sequence < rhs.sequence
    }
}

private extension AgentTeamFeedEvent {
    var searchText: String {
        ([message, kind.rawValue, teammateName] + metadata.flatMap { [$0.key, $0.value] })
            .joined(separator: " ")
            .lowercased()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
