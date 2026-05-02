// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// IndexIgnorePatterns.swift - Local ignore policy for codebase indexing.

import Darwin
import Foundation

struct CodebaseIndexIgnorePatterns {
    private let rules: [CodebaseIndexIgnoreRule]

    init(rootURL: URL) {
        self.rules = [".gitignore", ".cocxyindexignore"].flatMap { filename in
            let url = rootURL.appendingPathComponent(filename)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return [CodebaseIndexIgnoreRule]()
            }
            return content
                .components(separatedBy: .newlines)
                .compactMap(CodebaseIndexIgnoreRule.init(rawPattern:))
        }
    }

    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        if relativePath == ".git" || relativePath.hasPrefix(".git/") {
            return true
        }
        if AgentSensitivePathPolicy.isProtected(relativePath: relativePath, isDirectory: isDirectory) {
            return true
        }
        return rules.contains { $0.matches(relativePath: relativePath, isDirectory: isDirectory) }
    }
}

private struct CodebaseIndexIgnoreRule {
    let pattern: String
    let directoryOnly: Bool

    init?(rawPattern: String) {
        let trimmed = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!") else {
            return nil
        }

        self.directoryOnly = trimmed.hasSuffix("/")
        self.pattern = String(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    func matches(relativePath: String, isDirectory: Bool) -> Bool {
        guard !directoryOnly || isDirectory || relativePath.hasPrefix(pattern + "/") else {
            return false
        }
        if relativePath == pattern || relativePath.hasPrefix(pattern + "/") {
            return true
        }
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        return codebaseIndexGlob(pattern, matches: name) || codebaseIndexGlob(pattern, matches: relativePath)
    }
}

private func codebaseIndexGlob(_ pattern: String, matches value: String) -> Bool {
    pattern.withCString { patternPointer in
        value.withCString { valuePointer in
            fnmatch(patternPointer, valuePointer, 0) == 0
        }
    }
}
