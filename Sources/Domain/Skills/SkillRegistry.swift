// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillRegistry.swift - Local skill discovery and precedence.

import Foundation

struct SkillRegistry: Sendable {
    let directories: [SkillDirectory]
    private let loader: SkillLoader

    init(directories: [SkillDirectory], loader: SkillLoader = SkillLoader()) {
        self.directories = directories
        self.loader = loader
    }

    func loadSkills() throws -> [Skill] {
        var merged: [String: Skill] = [:]

        for skill in try discoverSkills() {
            merged[skill.id] = skill
        }

        return merged.values.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func skillMap() throws -> [String: Skill] {
        let grouped = Dictionary(grouping: try loadAllSkills(), by: \.id)
        if let collision = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first {
            throw SkillError.ambiguousSkill(
                id: collision.key,
                sources: Self.sortedSources(collision.value.map(\.source))
            )
        }

        return grouped.mapValues { $0[0] }
    }

    func loadAllSkills() throws -> [Skill] {
        var discovered: [SkillIdentity: Skill] = [:]

        for skill in try discoverSkills() {
            guard discovered[skill.identity] == nil else {
                throw SkillError.duplicateSkillIdentity(skill.identity)
            }
            discovered[skill.identity] = skill
        }

        return discovered.values.sorted { lhs, rhs in
            if lhs.id != rhs.id {
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
            return lhs.source.rawValue < rhs.source.rawValue
        }
    }

    func skillMapByIdentity() throws -> [SkillIdentity: Skill] {
        Dictionary(uniqueKeysWithValues: try loadAllSkills().map { ($0.identity, $0) })
    }

    func resolveSkills(ids: [String]) throws -> [Skill] {
        let discovered = try discoverSkills()
        return try ids.map { id in
            let matches = discovered.filter { $0.id == id }
            guard let first = matches.first else {
                throw SkillError.missingSkill(id)
            }
            guard matches.count == 1 else {
                let identities = Set(matches.map(\.identity))
                if identities.count == 1 {
                    throw SkillError.duplicateSkillIdentity(first.identity)
                }
                throw SkillError.ambiguousSkill(
                    id: id,
                    sources: Self.sortedSources(matches.map(\.source))
                )
            }
            return first
        }
    }

    func resolveSkills(identities: [SkillIdentity]) throws -> [Skill] {
        let discovered = try discoverSkills()
        return try identities.map { identity in
            let matches = discovered.filter { $0.identity == identity }
            guard let first = matches.first else {
                throw SkillError.missingSkill("\(identity.id) [\(identity.source.rawValue)]")
            }
            guard matches.count == 1 else {
                throw SkillError.duplicateSkillIdentity(identity)
            }
            return first
        }
    }

    private func discoverSkills() throws -> [Skill] {
        var discovered: [Skill] = []

        for directory in directories {
            for skillDirectory in skillDirectories(in: directory.url) {
                do {
                    if let skill = try loader.loadSkill(from: skillDirectory, source: directory.source) {
                        discovered.append(skill)
                    }
                } catch SkillError.invalidIdentifier {
                    continue
                }
            }
        }

        return discovered
    }

    private static func sortedSources(_ sources: [SkillSource]) -> [SkillSource] {
        Array(Set(sources)).sorted { $0.rawValue < $1.rawValue }
    }

    private func skillDirectories(in root: URL) -> [URL] {
        let standardized = root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        if FileManager.default.fileExists(
            atPath: standardized.appendingPathComponent("SKILL.md").path
        ) {
            return [standardized]
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: standardized,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    static func localDefault(projectRoot: URL? = nil) -> SkillRegistry {
        SkillRegistry(directories: BuiltInSkills.defaultDirectories(projectRoot: projectRoot))
    }
}
