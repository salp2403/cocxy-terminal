// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillInvoker.swift - Builds deterministic local skill instructions.

import Foundation

struct SkillInvocation: Equatable, Sendable {
    let skillIDs: [String]
    let skillIdentities: [SkillIdentity]
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

        return makeInvocation(skills: skills)
    }

    func makeInvocation(skillIdentities: [SkillIdentity]) throws -> SkillInvocation {
        let requestedIdentities = Array(Set(skillIdentities)).sorted(by: Self.identitySort)
        let skillsByIdentity = try registry.skillMapByIdentity()
        let skills = try requestedIdentities.map { identity -> Skill in
            guard let skill = skillsByIdentity[identity] else {
                throw SkillError.missingSkill("\(identity.id) [\(identity.source.rawValue)]")
            }
            return skill
        }

        return makeInvocation(skills: skills)
    }

    private func makeInvocation(skills: [Skill]) -> SkillInvocation {
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
            skillIdentities: skills.map(\.identity),
            instructions: blocks.joined(separator: "\n\n")
        )
    }

    private static func identitySort(_ lhs: SkillIdentity, _ rhs: SkillIdentity) -> Bool {
        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }
        return lhs.source.rawValue < rhs.source.rawValue
    }
}
