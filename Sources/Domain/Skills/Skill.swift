// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Skill.swift - Local skill model for agent guidance.

import Foundation

enum SkillSource: String, Codable, Sendable {
    case builtIn = "built-in"
    case user
    case project
}

struct Skill: Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let body: String
    let source: SkillSource
    let fileURL: URL
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

enum SkillError: Error, Equatable, LocalizedError {
    case invalidFrontMatter(URL)
    case invalidIdentifier(String)
    case missingSkill(String)

    var errorDescription: String? {
        switch self {
        case .invalidFrontMatter(let url):
            return "Invalid skill metadata: \(url.lastPathComponent)"
        case .invalidIdentifier(let id):
            return "Invalid skill id: \(id)"
        case .missingSkill(let id):
            return "Skill not found: \(id)"
        }
    }
}
