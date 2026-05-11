// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputDraft.swift - Persistent local terminal rich input draft.

import Foundation

struct RichInputDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let tabID: String
    var text: String
    var attachments: [AgentImageAttachment]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        tabID: String,
        text: String,
        attachments: [AgentImageAttachment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tabID = tabID
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}

