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

        for directory in directories {
            for skillDirectory in skillDirectories(in: directory.url) {
                do {
                    if let skill = try loader.loadSkill(from: skillDirectory, source: directory.source) {
                        merged[skill.id] = skill
                    }
                } catch SkillError.invalidIdentifier {
                    continue
                }
            }
        }

        return merged.values.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func skillMap() throws -> [String: Skill] {
        Dictionary(uniqueKeysWithValues: try loadSkills().map { ($0.id, $0) })
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
