// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BundledPluginCatalog.swift - Bundled plugin source discovery.

import Foundation

/// Discovers plugin repos shipped inside the app bundle.
struct BundledPluginCatalog {
    let pluginsDirectory: URL?
    private let fileManager: FileManager

    init(
        pluginsDirectory: URL? = Self.bundledDirectory(),
        fileManager: FileManager = .default
    ) {
        self.pluginsDirectory = pluginsDirectory
        self.fileManager = fileManager
    }

    func loadManifests() throws -> [PluginManifest] {
        guard let pluginsDirectory,
              fileManager.fileExists(atPath: pluginsDirectory.path)
        else { return [] }

        let entries = try fileManager.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return entries.compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? PluginRegistry.loadManifest(from: entry, fileManager: fileManager)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func bundledDirectory(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Plugins", isDirectory: true),
            checkoutResourceDirectory(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)),
            bundle.executableURL.flatMap { checkoutResourceDirectory(startingAt: $0) },
        ].compactMap { $0 }

        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private static func checkoutResourceDirectory(startingAt start: URL) -> URL? {
        var current = start.standardizedFileURL
        if !current.pathExtension.isEmpty {
            current.deleteLastPathComponent()
        }
        let root = URL(fileURLWithPath: "/", isDirectory: true)

        while true {
            let candidate = current
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Plugins", isDirectory: true)
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
