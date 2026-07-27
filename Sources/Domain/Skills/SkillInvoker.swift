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
        let requestedIDs = Array(Set(skillIDs.map(Self.normalizedID))).sorted()
        let skills = try registry.resolveSkills(ids: requestedIDs)

        return makeInvocation(skills: skills)
    }

    func makeInvocation(skillIdentities: [SkillIdentity]) throws -> SkillInvocation {
        let normalizedIdentities = skillIdentities.map {
            SkillIdentity(id: Self.normalizedID($0.id), source: $0.source)
        }
        let requestedIdentities = Array(Set(normalizedIdentities)).sorted(by: Self.identitySort)
        let skills = try registry.resolveSkills(identities: requestedIdentities)

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

    private static func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
