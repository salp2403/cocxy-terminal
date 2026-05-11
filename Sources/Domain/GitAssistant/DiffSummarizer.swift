// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DiffSummarizer.swift - Safe prompt preparation for changed files.

import Foundation

struct GitAssistantDiffSummary: Sendable, Equatable {
    let text: String
    let truncated: Bool
    let includedFilePaths: [String]
    let omittedFileCount: Int
    let additions: Int
    let deletions: Int
}

struct DiffSummarizer: Sendable {
    let maxLines: Int

    init(maxLines: Int = GitAssistantSettings.defaults.maxDiffLines) {
        self.maxLines = max(1, maxLines)
    }

    func summarize(rawDiff: String) -> GitAssistantDiffSummary {
        let sections = Self.sections(from: rawDiff)
        guard !sections.isEmpty else {
            let bounded = boundedLines(rawDiff)
            return GitAssistantDiffSummary(
                text: Self.redacted(bounded.text),
                truncated: bounded.truncated,
                includedFilePaths: [],
                omittedFileCount: 0,
                additions: Self.additionCount(in: rawDiff),
                deletions: Self.deletionCount(in: rawDiff)
            )
        }

        var included: [DiffSection] = []
        var usedLines = 0

        for section in sections {
            let lineCost = section.lines.count
            if !included.isEmpty, usedLines + lineCost > maxLines {
                break
            }
            if included.isEmpty, lineCost > maxLines {
                let clipped = Array(section.lines.prefix(maxLines))
                included.append(DiffSection(filePath: section.filePath, lines: clipped))
                usedLines = clipped.count
                break
            }
            included.append(section)
            usedLines += lineCost
        }

        let omitted = max(0, sections.count - included.count)
        var text = included.flatMap(\.lines).joined(separator: "\n")
        if omitted > 0 {
            let noun = omitted == 1 ? "file" : "files"
            text += "\n[\(omitted) \(noun) omitted to keep the prompt within budget.]"
        }

        return GitAssistantDiffSummary(
            text: Self.redacted(text),
            truncated: omitted > 0 || sections.contains { $0.lines.count > maxLines && included.first?.filePath == $0.filePath },
            includedFilePaths: included.map(\.filePath),
            omittedFileCount: omitted,
            additions: Self.additionCount(in: rawDiff),
            deletions: Self.deletionCount(in: rawDiff)
        )
    }

    func summarize(fileDiffs: [FileDiff]) -> GitAssistantDiffSummary {
        summarize(rawDiff: Self.rawDiff(from: fileDiffs))
    }

    private func boundedLines(_ text: String) -> (text: String, truncated: Bool) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > maxLines else { return (text, false) }
        return (lines.prefix(maxLines).joined(separator: "\n"), true)
    }

    private static func sections(from rawDiff: String) -> [DiffSection] {
        let lines = rawDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [DiffSection] = []
        var currentPath: String?
        var currentLines: [String] = []

        func flush() {
            guard let currentPath, !currentLines.isEmpty else { return }
            sections.append(DiffSection(filePath: currentPath, lines: currentLines))
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
                currentPath = filePath(fromDiffHeader: line) ?? "unknown"
            }
            if currentPath != nil {
                currentLines.append(line)
            }
        }
        flush()

        return sections
    }

    private static func filePath(fromDiffHeader line: String) -> String? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }
        let raw = parts[3].hasPrefix("b/") ? String(parts[3].dropFirst(2)) : parts[3]
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rawDiff(from fileDiffs: [FileDiff]) -> String {
        fileDiffs.flatMap { file in
            var lines: [String] = [
                "diff --git a/\(file.originalFilePath ?? file.filePath) b/\(file.filePath)",
            ]
            for hunk in file.hunks {
                lines.append(hunk.header)
                for line in hunk.lines {
                    switch line.kind {
                    case .context:
                        lines.append(" \(line.content)")
                    case .addition:
                        lines.append("+\(line.content)")
                    case .deletion:
                        lines.append("-\(line.content)")
                    }
                }
            }
            return lines
        }
        .joined(separator: "\n")
    }

    private static func additionCount(in text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
            .count
    }

    private static func deletionCount(in text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }
            .count
    }

    private static func redacted(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in redactionPatterns {
            result = replacing(pattern: pattern, in: result, with: replacement)
        }
        return result
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static let redactionPatterns: [(String, String)] = [
        (#"(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, "[redacted-email]"),
        (##"(?i)\b(?:api[_ -]?key|apikey|token|secret|authorization)\s*[:=]\s*["']?[^"'\s,;]+["']?"##, "[redacted-secret]"),
        (#"\b(?:sk|pk|rk)-(?:live|test|proj)-[A-Za-z0-9_\-]{8,}\b"#, "[redacted-secret]"),
        (#"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#, "[redacted-secret]"),
        (#"\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b"#, "[redacted-secret]"),
    ]

    private struct DiffSection: Sendable, Equatable {
        let filePath: String
        let lines: [String]
    }
}
