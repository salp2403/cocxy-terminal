// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplateRegistry.swift - Local scaffold template discovery and precedence.

import Foundation

struct ProjectTemplateRegistry {
    let directories: [ProjectTemplateDirectory]
    private let loader: ProjectTemplateLoader

    init(
        directories: [ProjectTemplateDirectory],
        loader: ProjectTemplateLoader = ProjectTemplateLoader()
    ) {
        self.directories = directories
        self.loader = loader
    }

    func loadTemplates() throws -> [ProjectTemplate] {
        var merged: [String: ProjectTemplate] = [:]

        for directory in directories {
            for templateDirectory in templateDirectories(in: directory.url) {
                do {
                    if let template = try loader.loadTemplate(
                        from: templateDirectory,
                        source: directory.source
                    ) {
                        merged[template.id] = template
                    }
                } catch ProjectTemplateError.invalidIdentifier {
                    continue
                }
            }
        }

        return merged.values.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func templateMap() throws -> [String: ProjectTemplate] {
        Dictionary(uniqueKeysWithValues: try loadTemplates().map { ($0.id, $0) })
    }

    private func templateDirectories(in root: URL) -> [URL] {
        let standardized = root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        if FileManager.default.fileExists(
            atPath: standardized.appendingPathComponent("template.json").path
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

    static func localDefault(projectRoot: URL? = nil) -> ProjectTemplateRegistry {
        ProjectTemplateRegistry(
            directories: BuiltInTemplates.defaultDirectories(projectRoot: projectRoot)
        )
    }
}
