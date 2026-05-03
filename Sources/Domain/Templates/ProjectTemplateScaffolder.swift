// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplateScaffolder.swift - Writes local project scaffolds without running hooks.

import Foundation

struct ProjectTemplateHookPlan: Sendable, Equatable {
    let workingDirectory: URL
    let pre: [String]
    let post: [String]
}

struct ProjectTemplateScaffoldResult: Sendable, Equatable {
    let createdFiles: [String]
    let hookPlan: ProjectTemplateHookPlan
}

struct ProjectTemplateScaffolder {
    private let fileManager: FileManager
    private let resolver: TemplateVariableResolver

    init(
        fileManager: FileManager = .default,
        resolver: TemplateVariableResolver = TemplateVariableResolver()
    ) {
        self.fileManager = fileManager
        self.resolver = resolver
    }

    func scaffold(
        template: ProjectTemplate,
        values: [String: String],
        destinationURL: URL,
        overwrite: Bool = false
    ) throws -> ProjectTemplateScaffoldResult {
        let resolvedValues = try resolver.resolvedValues(
            variables: template.variables,
            values: values
        )
        let destination = destinationURL.standardizedFileURL
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var createdFiles: [String] = []
        for file in try templateFiles(in: template.filesURL) {
            let relativePath = try relativeTemplatePath(fileURL: file, filesRoot: template.filesURL)
            let renderedPath = try resolver.render(relativePath, values: resolvedValues)
            let outputURL = try safeOutputURL(for: renderedPath, destination: destination)

            if fileManager.fileExists(atPath: outputURL.path), !overwrite {
                throw ProjectTemplateError.destinationExists(renderedPath)
            }

            guard let content = String(data: try Data(contentsOf: file), encoding: .utf8) else {
                throw ProjectTemplateError.nonUTF8TemplateFile(relativePath)
            }
            let renderedContent = try resolver.render(content, values: resolvedValues)
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try renderedContent.write(to: outputURL, atomically: true, encoding: .utf8)
            createdFiles.append(renderedPath)
        }

        return ProjectTemplateScaffoldResult(
            createdFiles: createdFiles.sorted(),
            hookPlan: ProjectTemplateHookPlan(
                workingDirectory: destination,
                pre: try template.hooks.pre.map { try resolver.render($0, values: resolvedValues) },
                post: try template.hooks.post.map { try resolver.render($0, values: resolvedValues) }
            )
        )
    }

    private func templateFiles(in root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw ProjectTemplateError.missingFilesDirectory(root)
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let resourceValues = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if resourceValues.isSymbolicLink == true {
                throw ProjectTemplateError.unsafeOutputPath(url.lastPathComponent)
            }
            if resourceValues.isRegularFile == true {
                files.append(url.standardizedFileURL)
            }
        }

        return files.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private func relativeTemplatePath(fileURL: URL, filesRoot: URL) throws -> String {
        let rootPath = filesRoot.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard filePath.hasPrefix(prefix) else {
            throw ProjectTemplateError.unsafeOutputPath(filePath)
        }
        return String(filePath.dropFirst(prefix.count))
    }

    private func safeOutputURL(for relativePath: String, destination: URL) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0") else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }

        let outputURL = destination.appendingPathComponent(relativePath).standardizedFileURL
        let destinationPath = destination.path.hasSuffix("/") ? destination.path : "\(destination.path)/"
        guard outputURL.path.hasPrefix(destinationPath) else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }

        return outputURL
    }
}
