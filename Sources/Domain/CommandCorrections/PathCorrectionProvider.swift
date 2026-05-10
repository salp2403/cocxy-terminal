// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct PathCorrectionProvider: CommandCorrectionProvider {
    public init() {}

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        guard let split = CommandCorrectionCommandLine.splitFirstToken(context.command),
              split.firstToken == "cd",
              let rawPath = firstArgument(in: split.suffix)
        else {
            return []
        }

        let resolved = resolve(rawPath, workingDirectory: context.workingDirectory)
        guard !FileManager.default.fileExists(atPath: resolved.path),
              let candidate = nearestExistingSiblingPath(to: resolved)
        else {
            return []
        }

        return [
            CommandCorrection(
                original: context.normalizedCommand,
                suggestion: "cd \(CommandCorrectionCommandLine.shellEscapedPath(candidate.path))",
                reason: "Nearest existing directory path",
                confidence: 0.91,
                source: .pathHeuristic
            )
        ]
    }

    private func firstArgument(in suffix: String) -> String? {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("'") || trimmed.hasPrefix("\"") {
            let quote = trimmed[trimmed.startIndex]
            var index = trimmed.index(after: trimmed.startIndex)
            var value = ""
            while index < trimmed.endIndex {
                let character = trimmed[index]
                if character == quote { return value }
                value.append(character)
                index = trimmed.index(after: index)
            }
            return value.isEmpty ? nil : value
        }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    private func resolve(_ rawPath: String, workingDirectory: URL?) -> URL {
        let expanded: String
        if rawPath == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if rawPath.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(rawPath.dropFirst(2)))
                .path
        } else {
            expanded = rawPath
        }

        let url = URL(fileURLWithPath: expanded, relativeTo: expanded.hasPrefix("/") ? nil : workingDirectory)
        return url.standardizedFileURL
    }

    private func nearestExistingSiblingPath(to missingPath: URL) -> URL? {
        let components = missingPath.pathComponents
        guard components.count > 1 else { return nil }

        for index in stride(from: components.count - 1, through: 1, by: -1) {
            let parentComponents = Array(components.prefix(index))
            let missingComponent = components[index]
            let suffix = Array(components.dropFirst(index + 1))
            let parent = URL(fileURLWithPath: NSString.path(withComponents: parentComponents))

            guard let siblings = try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let match = siblings
                .map { url in
                    (url, CommandCorrectionCommandLine.editDistance(url.lastPathComponent, missingComponent))
                }
                .filter { _, distance in distance > 0 && distance <= 2 }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                    return lhs.0.lastPathComponent < rhs.0.lastPathComponent
                }
                .first?
                .0
            guard let match else { continue }

            let candidate = suffix.reduce(match) { url, component in
                url.appendingPathComponent(component)
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate.standardizedFileURL
            }
        }

        return nil
    }
}
