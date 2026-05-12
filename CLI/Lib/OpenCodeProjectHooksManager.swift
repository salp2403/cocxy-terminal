// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OpenCodeProjectHooksManager.swift - Project-local OpenCode plugin bridge.

import Foundation

struct OpenCodeProjectHooksManager {
    static let relativePluginsDirectoryPath = ".opencode/plugins"

    let projectDirectory: URL
    let fileManager: FileManager

    init(
        projectDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) {
        self.projectDirectory = projectDirectory
        self.fileManager = fileManager
    }

    var pluginsDirectoryURL: URL {
        projectDirectory.appendingPathComponent(Self.relativePluginsDirectoryPath)
    }

    private var manager: OpenCodeHooksSettingsManager {
        OpenCodeHooksSettingsManager(
            pluginsDirectoryURL: pluginsDirectoryURL,
            scopeDescription: "project",
            fileManager: fileManager
        )
    }

    func install() throws -> String {
        let result = try manager.installHooks()
        if result.alreadyInstalled {
            return "OpenCode: project plugins already installed at \(pluginsDirectoryURL.path)."
        }
        return "OpenCode: project plugins installed at \(pluginsDirectoryURL.path)."
    }

    func remove() throws -> String {
        let result = try manager.uninstallHooks()
        if result.nothingToRemove {
            return "OpenCode: no Cocxy project plugins found at \(pluginsDirectoryURL.path)."
        }
        return "OpenCode: project plugins removed from \(pluginsDirectoryURL.path)."
    }

    func dryRun(remove: Bool) -> String {
        manager.dryRun(remove: remove)
    }

    func check() throws -> (line: String, failed: Bool) {
        try manager.check()
    }
}
