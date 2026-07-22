// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Skill.swift - Local skill model for agent guidance.

import Foundation

enum SkillSource: String, Codable, Hashable, Sendable {
    case builtIn = "built-in"
    case user
    case project
}

struct SkillIdentity: Codable, Hashable, Sendable {
    let id: String
    let source: SkillSource
}

struct Skill: Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let body: String
    let source: SkillSource
    let fileURL: URL

    var identity: SkillIdentity {
        SkillIdentity(id: id, source: source)
    }
}

struct SkillDirectory: Equatable, Sendable {
    let url: URL
    let source: SkillSource

    init(url: URL, source: SkillSource) {
        self.url = url.standardizedFileURL
        self.source = source
    }
}

struct SkillListEntry: Encodable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String
    let source: String

    init(skill: Skill) {
        self.id = skill.id
        self.name = skill.name
        self.description = skill.summary
        self.source = skill.source.rawValue
    }
}

struct SkillListSnapshot: Encodable, Equatable, Sendable {
    let count: Int
    let skills: [SkillListEntry]

    init(skills: [Skill]) {
        self.count = skills.count
        self.skills = skills.map(SkillListEntry.init(skill:))
    }
}

enum SkillError: Error, Equatable, LocalizedError, Sendable {
    case invalidFrontMatter(URL)
    case invalidIdentifier(String)
    case invalidSource(String)
    case missingSkill(String)
    case ambiguousSkill(id: String, sources: [SkillSource])
    case duplicateSkillIdentity(SkillIdentity)

    var errorDescription: String? {
        switch self {
        case .invalidFrontMatter(let url):
            return "Invalid skill metadata: \(url.lastPathComponent)"
        case .invalidIdentifier(let id):
            return "Invalid skill id: \(id)"
        case .invalidSource(let source):
            return "Invalid skill source: \(source)"
        case .missingSkill(let id):
            return "Skill not found: \(id)"
        case .ambiguousSkill(let id, let sources):
            let sourceList = sources.map(\.rawValue).joined(separator: ", ")
            return "Skill id '\(id)' is ambiguous across sources: \(sourceList). Select a source."
        case .duplicateSkillIdentity(let identity):
            return "Skill identity '\(identity.id)' is duplicated in source \(identity.source.rawValue)."
        }
    }
}
