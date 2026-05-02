// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BuiltInSkills.swift - Local bundled and user skill directory lookup.

import Foundation

enum BuiltInSkills {
    static func defaultDirectories(
        projectRoot: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundle: Bundle = .main
    ) -> [SkillDirectory] {
        var directories: [SkillDirectory] = []
        if let bundled = bundledDirectory(bundle: bundle) {
            directories.append(SkillDirectory(url: bundled, source: .builtIn))
        }
        directories.append(SkillDirectory(
            url: homeDirectory.appendingPathComponent(".cocxy/skills", isDirectory: true),
            source: .user
        ))
        if let projectRoot {
            directories.append(SkillDirectory(
                url: projectRoot.appendingPathComponent(".cocxy/skills", isDirectory: true),
                source: .project
            ))
        }
        return directories
    }

    static func bundledDirectory(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Skills", isDirectory: true),
            checkoutResourceDirectory(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)),
            Bundle.main.executableURL.flatMap { checkoutResourceDirectory(startingAt: $0) },
        ].compactMap { $0 }

        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private static func checkoutResourceDirectory(startingAt start: URL) -> URL? {
        var current = start.standardizedFileURL
        if current.pathExtension != "" {
            current.deleteLastPathComponent()
        }
        let root = URL(fileURLWithPath: "/", isDirectory: true)

        while true {
            let candidate = current
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Skills", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
            if current == root {
                return nil
            }
            current.deleteLastPathComponent()
        }
    }
}
