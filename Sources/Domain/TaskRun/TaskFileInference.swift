// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskFileInference.swift - Bounded local file catalog and prompt inference.

import Foundation

actor TaskFileCatalogService {
    private struct CacheEntry {
        let loadedAt: Date
        let paths: [String]
    }

    private var cacheByRoot: [String: CacheEntry] = [:]

    func paths(
        for projectRoot: URL,
        maximumAge: TimeInterval = 2
    ) async -> [String] {
        let root = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        let now = Date()
        if let cached = cacheByRoot[root.path],
           now.timeIntervalSince(cached.loadedAt) <= maximumAge {
            return cached.paths
        }
        let paths = await Task.detached {
            TaskFileInference.loadProjectFiles(projectRoot: root)
        }.value
        cacheByRoot[root.path] = CacheEntry(loadedAt: now, paths: paths)
        return paths
    }

    func invalidate(projectRoot: URL) {
        cacheByRoot.removeValue(
            forKey: projectRoot.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }
}

enum TaskFileInference {
    static let maximumCatalogEntries = 20_000
    static let maximumInferredPaths = 256

    static func infer(
        prompt: String,
        projectFiles: [String],
        projectRoot: URL,
        seedPaths: [String] = []
    ) -> [String] {
        let catalog = Array(Set(projectFiles.compactMap(normalizedCatalogPath))).sorted()
        let lowerPrompt = prompt.lowercased()
        let terms = promptTerms(lowerPrompt)
        let basenames = Dictionary(grouping: catalog, by: {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased()
        })
        let stems = Dictionary(grouping: catalog, by: {
            URL(fileURLWithPath: $0).deletingPathExtension()
                .lastPathComponent.lowercased()
        })
        var inferred = TaskCollisionDetector.normalize(seedPaths, projectRoot: projectRoot)

        for path in catalog {
            guard inferred.count < maximumInferredPaths else { break }
            let lowerPath = path.lowercased()
            let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            let stem = URL(fileURLWithPath: path).deletingPathExtension()
                .lastPathComponent.lowercased()
            if lowerPrompt.contains(lowerPath)
                || (basenames[basename]?.count == 1 && terms.contains(basename))
                || (stem.count >= 4 && stems[stem]?.count == 1 && terms.contains(stem)) {
                inferred.insert(path)
            }
        }

        let citedPaths = TaskCollisionDetector.normalize(
            promptPathCandidates(prompt),
            projectRoot: projectRoot
        )
        for cited in citedPaths.sorted() where inferred.count < maximumInferredPaths {
            if catalog.contains(cited) {
                inferred.insert(cited)
                continue
            }
            let descendants = catalog.filter { $0.hasPrefix(cited + "/") }
            if descendants.isEmpty {
                inferred.insert(cited)
            } else if descendants.count <= maximumInferredPaths - inferred.count {
                inferred.formUnion(descendants)
            }
        }
        return Array(inferred).sorted().prefix(maximumInferredPaths).map { $0 }
    }

    static func loadProjectFiles(projectRoot: URL) -> [String] {
        if let gitPaths = gitProjectFiles(projectRoot: projectRoot) {
            return gitPaths
        }
        return enumeratedProjectFiles(projectRoot: projectRoot)
    }

    private static func gitProjectFiles(projectRoot: URL) -> [String]? {
        let result: BoundedProcessResult
        do {
            result = try MarketplaceGitProcessRunner(
                workingDirectory: projectRoot,
                timeoutSeconds: 5,
                maximumRetainedBytesPerStream: 4 * 1_024 * 1_024
            ).run(
                arguments: [
                    "ls-files", "-z", "--cached", "--others",
                    "--exclude-standard", "--",
                ],
                workingDirectory: .path(projectRoot)
            )
        } catch {
            return nil
        }
        guard !result.timedOut,
              result.exitCode == 0,
              !result.stdoutWasTruncated else {
            return nil
        }
        return Array(Set(result.stdout.split(separator: "\0").compactMap {
            normalizedCatalogPath(String($0))
        })).sorted().prefix(maximumCatalogEntries).map { $0 }
    }

    private static func enumeratedProjectFiles(projectRoot: URL) -> [String] {
        let excludedDirectories: Set<String> = [
            ".git", ".build", "build", "DerivedData", "node_modules",
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath == "/" ? "/" : rootPath + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard paths.count < maximumCatalogEntries else { break }
            let relative = String(url.standardizedFileURL.path.dropFirst(rootPrefix.count))
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true,
                  let normalized = normalizedCatalogPath(relative) else {
                continue
            }
            paths.append(normalized)
        }
        return Array(Set(paths)).sorted()
    }

    private static func normalizedCatalogPath(_ rawPath: String) -> String? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0"),
              path.utf8.count <= 4_096 else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        return components.joined(separator: "/")
    }

    private static func promptTerms(_ prompt: String) -> Set<String> {
        Set(prompt.split { character in
            !(character.isLetter || character.isNumber || "._-".contains(character))
        }.map(String.init))
    }

    private static func promptPathCandidates(_ prompt: String) -> [String] {
        let trimSet = CharacterSet(charactersIn: "`'\"()[]{}<>,;:")
            .union(.whitespacesAndNewlines)
        var candidates = prompt.split(whereSeparator: { $0.isWhitespace }).compactMap { token in
            var value = String(token)
            while let last = value.last, ".!?".contains(last) {
                value.removeLast()
            }
            value = value.trimmingCharacters(in: trimSet)
            return value.contains("/") ? value : nil
        }
        let pattern = "[`'\"]([^`'\"]+)[`'\"]"
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(prompt.startIndex..., in: prompt)
            for match in expression.matches(in: prompt, range: range) where match.numberOfRanges > 1 {
                guard let matchRange = Range(match.range(at: 1), in: prompt) else { continue }
                let value = String(prompt[matchRange])
                if value.contains("/") { candidates.append(value) }
            }
        }
        return candidates
    }
}
