// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroModels.swift - Shared models for local macros, snippets, aliases, and clipboard history.

import Foundation
import CocxyCommandSignatures

enum MacroEvent: Codable, Equatable, Sendable {
    case text(String)
    case key(String)
    case command(String)
    case delay(milliseconds: Int)
}

struct TerminalMacro: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let events: [MacroEvent]
    let createdAt: Date
    let updatedAt: Date
    let signature: SignedArtifact?

    init(
        id: String = UUID().uuidString,
        name: String,
        events: [MacroEvent],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        signature: SignedArtifact? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.events = events
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.signature = signature
    }
}

struct Snippet: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var trigger: String
    var body: String
    var scope: String?
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        trigger: String,
        body: String,
        scope: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.body = body
        self.scope = scope
        self.updatedAt = updatedAt
    }
}

struct ShellAlias: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var value: String
    var detail: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        value: String,
        detail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.detail = detail
    }
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let text: String
    let copiedAt: Date

    init(id: String = UUID().uuidString, text: String, copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }
}
