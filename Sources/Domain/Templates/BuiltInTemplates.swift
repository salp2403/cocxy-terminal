// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BuiltInTemplates.swift - Bundled, user, and project template directory lookup.

import Foundation

enum BuiltInTemplates {
    static func defaultDirectories(
        projectRoot: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundle: Bundle = .main
    ) -> [ProjectTemplateDirectory] {
        var directories: [ProjectTemplateDirectory] = []
        if let bundled = bundledDirectory(bundle: bundle) {
            directories.append(ProjectTemplateDirectory(url: bundled, source: .builtIn))
        }
        directories.append(ProjectTemplateDirectory(
            url: homeDirectory.appendingPathComponent(".cocxy/templates", isDirectory: true),
            source: .user
        ))
        if let projectRoot {
            directories.append(ProjectTemplateDirectory(
                url: projectRoot.appendingPathComponent(".cocxy/templates", isDirectory: true),
                source: .project
            ))
        }
        return directories
    }

    static func bundledDirectory(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Templates", isDirectory: true),
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
                .appendingPathComponent("Templates", isDirectory: true)
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
