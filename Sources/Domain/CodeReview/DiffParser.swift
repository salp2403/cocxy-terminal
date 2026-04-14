// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DiffParser.swift - Unified diff parsing for the review panel.

import Foundation

enum DiffParser {

    static func parse(_ raw: String) -> [FileDiff] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var results: [FileDiff] = []
        var current: FileBlock?
        var currentHunk: HunkBuilder?

        func finalizeHunk() {
            guard let hunk = currentHunk?.build() else { return }
            current?.hunks.append(hunk)
            currentHunk = nil
        }

        func finalizeFile() {
            finalizeHunk()
            guard let block = current else { return }
            let path = block.resolvedPath
            guard !path.isEmpty else {
                current = nil
                return
            }
            results.append(
                FileDiff(
                    filePath: path,
                    originalFilePath: block.originalPath,
                    status: block.resolvedStatus,
                    hunks: block.hunks,
                    reviewNote: block.reviewNote
                )
            )
            current = nil
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                finalizeFile()
                current = FileBlock(diffHeader: line)
                continue
            }

            guard current != nil else { continue }

            if line.hasPrefix("new file mode ") {
                current?.status = .added
                continue
            }

            if line.hasPrefix("deleted file mode ") {
                current?.status = .deleted
                continue
            }

            if line.hasPrefix("rename from ") {
                current?.status = .renamed
                continue
            }

            if line.hasPrefix("rename to ") {
                current?.status = .renamed
                current?.plusPath = String(line.dropFirst("rename to ".count))
                continue
            }

            if line.hasPrefix("Binary files ") {
                current?.markBinary(from: line)
                continue
            }

            if line.hasPrefix("--- ") {
                current?.minusPath = parsePathLine(line, prefix: "--- ")
                if current?.minusPath == "/dev/null" {
                    current?.status = .added
                }
                continue
            }

            if line.hasPrefix("+++ ") {
                current?.plusPath = parsePathLine(line, prefix: "+++ ")
                if current?.plusPath == "/dev/null" {
                    current?.status = .deleted
                }
                continue
            }

            if line.hasPrefix("@@ ") || line.hasPrefix("@@-") || line.hasPrefix("@@ -") {
                finalizeHunk()
                if let builder = HunkBuilder(header: line) {
                    currentHunk = builder
                } else {
                    current?.markMalformedHunk(header: line)
                    currentHunk = nil
                }
                continue
            }

            guard currentHunk != nil else { continue }

            if line == "\\ No newline at end of file" {
                continue
            }

            currentHunk?.append(line)
        }

        finalizeFile()

        return results.sorted {
            if $0.status.sortRank != $1.status.sortRank {
                return $0.status.sortRank < $1.status.sortRank
            }
            return $0.filePath.localizedCaseInsensitiveCompare($1.filePath) == .orderedAscending
        }
    }

    static func parseStatus(_ raw: String) -> [(path: String, status: FileStatus)] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .compactMap { rawLine in
                let line = String(rawLine)
                guard line.count >= 3 else { return nil }

                if line.hasPrefix("?? ") {
                    return (String(line.dropFirst(3)), .untracked)
                }

                let markers = Array(line.prefix(2))
                guard markers.count == 2 else { return nil }
                let index = line.index(line.startIndex, offsetBy: 2)
                let pathPart = String(line[index...]).trimmingCharacters(in: .whitespaces)
                guard !pathPart.isEmpty else { return nil }

                let status = resolvePorcelainStatus(index: markers[0], workTree: markers[1])

                if status == .renamed, let arrow = pathPart.range(of: " -> ") {
                    return (String(pathPart[arrow.upperBound...]), .renamed)
                }

                return (pathPart, status)
            }
    }

    private static func resolvePorcelainStatus(index: Character, workTree: Character) -> FileStatus {
        let markers = [index, workTree]

        if markers.contains("R") || markers.contains("C") {
            return .renamed
        }
        if workTree == "D" {
            return .deleted
        }
        if markers.contains("A") {
            return .added
        }
        if markers.contains("D") {
            return .deleted
        }
        if markers.contains("M") || markers.contains("U") {
            return .modified
        }
        return .modified
    }

    static func makeSyntheticAddedFileDiff(
        filePath: String,
        fileContent: String,
        agentName: String? = nil
    ) -> FileDiff {
        let normalized = fileContent.replacingOccurrences(of: "\r\n", with: "\n")
        var fileLines = normalized.components(separatedBy: "\n")
        if normalized.hasSuffix("\n"), fileLines.last == "" {
            fileLines.removeLast()
        }
        let additions = fileLines.enumerated().map { index, line in
            DiffLine(
                kind: .addition,
                content: line,
                oldLineNumber: nil,
                newLineNumber: index + 1
            )
        }
        let hunk = DiffHunk(
            header: "@@ -0,0 +1,\(max(additions.count, 1)) @@",
            oldStart: 0,
            oldCount: 0,
            newStart: 1,
            newCount: max(additions.count, 1),
            lines: additions
        )
        return FileDiff(filePath: filePath, status: .added, hunks: [hunk], agentName: agentName)
    }

    private static func parsePathLine(_ line: String, prefix: String) -> String {
        let value = String(line.dropFirst(prefix.count))
        let untimestamped = value
            .split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? value
        let unquoted = stripSurroundingQuotes(from: untimestamped)
            .trimmingCharacters(in: .whitespaces)
        guard unquoted != "/dev/null" else { return unquoted }
        return stripGitDiffPrefix(from: unquoted)
    }

    fileprivate static func stripGitDiffPrefix(from value: String) -> String {
        guard value.count > 2 else { return value }
        let characters = Array(value)
        if characters[1] == "/", ["a", "b", "c", "i", "o", "w"].contains(String(characters[0])) {
            return String(value.dropFirst(2))
        }
        return value
    }

    private static func stripSurroundingQuotes(from value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }
}

private struct FileBlock {
    let diffHeader: String
    var minusPath: String?
    var plusPath: String?
    var status: FileStatus?
    var hunks: [DiffHunk] = []
    var isBinary = false
    var didEncounterMalformedHunk = false

    var resolvedStatus: FileStatus {
        if let status { return status }
        if minusPath == "/dev/null" { return .added }
        if plusPath == "/dev/null" { return .deleted }
        return .modified
    }

    var reviewNote: String? {
        if isBinary {
            return "Binary file changed. Open the file directly to inspect its contents."
        }
        if didEncounterMalformedHunk {
            return "Part of this diff could not be parsed cleanly. Showing only the hunks that were recovered."
        }
        return nil
    }

    var resolvedPath: String {
        switch resolvedStatus {
        case .deleted:
            return sanitize(minusPath) ?? fallbackPath
        case .added, .modified, .renamed, .untracked:
            return sanitize(plusPath) ?? sanitize(minusPath) ?? fallbackPath
        }
    }

    var originalPath: String? {
        guard resolvedStatus == .renamed else { return nil }
        let candidate = sanitize(minusPath)
        guard let candidate, candidate != resolvedPath else { return nil }
        return candidate
    }

    private var fallbackPath: String {
        let pieces = diffHeader.split(separator: " ")
        guard pieces.count >= 4 else { return "" }
        return DiffParser.stripGitDiffPrefix(from: String(pieces[3]))
    }

    private func sanitize(_ path: String?) -> String? {
        guard let path, path != "/dev/null" else { return nil }
        return DiffParser.stripGitDiffPrefix(from: path)
    }

    mutating func markBinary(from line: String) {
        isBinary = true
        if status == nil {
            status = .modified
        }

        guard let match = line.range(
            of: #"^Binary files (.+) and (.+) differ$"#,
            options: .regularExpression
        ) else { return }

        let payload = String(line[match])
            .replacingOccurrences(of: "Binary files ", with: "")
            .replacingOccurrences(of: " differ", with: "")
        let parts = payload.components(separatedBy: " and ")
        guard parts.count == 2 else { return }
        minusPath = DiffParser.stripGitDiffPrefix(from: parts[0])
        plusPath = DiffParser.stripGitDiffPrefix(from: parts[1])
    }

    mutating func markMalformedHunk(header: String) {
        didEncounterMalformedHunk = true
    }
}

private struct HunkBuilder {
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    private(set) var lines: [DiffLine] = []
    private var currentOld: Int
    private var currentNew: Int

    init?(header: String) {
        guard let match = header.range(of: #"^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@"#, options: .regularExpression) else {
            return nil
        }

        let matched = String(header[match])
        let numbers = matched
            .replacingOccurrences(of: "@@ -", with: "")
            .replacingOccurrences(of: " @@", with: "")
            .replacingOccurrences(of: "+", with: "")
            .split(separator: " ")

        guard numbers.count == 2 else { return nil }

        let oldParts = numbers[0].split(separator: ",")
        let newParts = numbers[1].split(separator: ",")

        let oldStart = Int(oldParts[0]) ?? 0
        let oldCount = oldParts.count > 1 ? (Int(oldParts[1]) ?? 1) : 1
        let newStart = Int(newParts[0]) ?? 0
        let newCount = newParts.count > 1 ? (Int(newParts[1]) ?? 1) : 1

        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.currentOld = oldStart
        self.currentNew = newStart
    }

    mutating func append(_ rawLine: String) {
        guard let marker = rawLine.first else { return }
        let content = String(rawLine.dropFirst())

        switch marker {
        case " ":
            lines.append(
                DiffLine(
                    kind: .context,
                    content: content,
                    oldLineNumber: currentOld,
                    newLineNumber: currentNew
                )
            )
            currentOld += 1
            currentNew += 1
        case "-":
            lines.append(
                DiffLine(
                    kind: .deletion,
                    content: content,
                    oldLineNumber: currentOld,
                    newLineNumber: nil
                )
            )
            currentOld += 1
        case "+":
            lines.append(
                DiffLine(
                    kind: .addition,
                    content: content,
                    oldLineNumber: nil,
                    newLineNumber: currentNew
                )
            )
            currentNew += 1
        default:
            break
        }
    }

    func build() -> DiffHunk {
        DiffHunk(
            header: header,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: lines
        )
    }
}
