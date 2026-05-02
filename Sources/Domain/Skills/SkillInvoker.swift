// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillInvoker.swift - Builds deterministic local skill instructions.

import Foundation

struct SkillInvocation: Equatable, Sendable {
    let skillIDs: [String]
    let instructions: String
}

struct SkillInvoker: Sendable {
    let registry: SkillRegistry

    func makeInvocation(skillIDs: [String]) throws -> SkillInvocation {
        let requestedIDs = Array(Set(skillIDs.map { $0.lowercased() })).sorted()
        let skillsByID = try registry.skillMap()
        let skills = try requestedIDs.map { id -> Skill in
            guard let skill = skillsByID[id] else {
                throw SkillError.missingSkill(id)
            }
            return skill
        }

        let blocks = skills.map { skill in
            """
            ## \(skill.name)

            ID: \(skill.id)
            Source: \(skill.source.rawValue)
            Summary: \(skill.summary)

            \(skill.body)
            """
        }

        return SkillInvocation(
            skillIDs: skills.map(\.id),
            instructions: blocks.joined(separator: "\n\n")
        )
    }
}
