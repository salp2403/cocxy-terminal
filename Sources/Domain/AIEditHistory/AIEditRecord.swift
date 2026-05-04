// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditRecord.swift - Local agent edit history models.

import Foundation

struct AIEditChange: Codable, Equatable, Sendable {
    let filePath: String
    let beforeContent: String?
    let afterContent: String?

    init(filePath: String, beforeContent: String?, afterContent: String?) {
        self.filePath = filePath
        self.beforeContent = beforeContent
        self.afterContent = afterContent
    }
}

struct AIEditRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: String
    let agentID: String
    let createdAt: Date
    let summary: String
    let changes: [AIEditChange]

    init(
        id: UUID = UUID(),
        sessionID: String,
        agentID: String,
        createdAt: Date = Date(),
        summary: String,
        changes: [AIEditChange]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agentID = agentID
        self.createdAt = createdAt
        self.summary = summary
        self.changes = changes
    }
}

struct AIEditFileSummary: Equatable, Sendable {
    let filePath: String
    let additions: Int
    let deletions: Int
}
