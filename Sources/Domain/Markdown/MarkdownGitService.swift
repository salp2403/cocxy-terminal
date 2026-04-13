// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownGitService.swift - Git blame and diff operations for markdown files.

import Foundation

// MARK: - Blame Line

/// A single line of git blame output.
public struct GitBlameLine: Equatable, Sendable {
    /// The abbreviated commit hash.
    public let commitHash: String

    /// The author name.
    public let author: String

    /// The date string (YYYY-MM-DD).
    public let date: String

    /// 1-based line number.
    public let lineNumber: Int

    /// The line content.
    public let content: String
}

// MARK: - Diff Hunk

/// A section of a git diff.
public struct GitDiffHunk: Equatable, Sendable {
    /// The hunk header (e.g., "@@ -10,5 +10,7 @@").
    public let header: String

    /// Lines in this hunk with their change type.
    public let lines: [GitDiffLine]
}

/// A single line in a diff hunk.
public struct GitDiffLine: Equatable, Sendable {
    public enum ChangeType: Equatable, Sendable {
        case context
        case addition
        case deletion
    }

    public let type: ChangeType
    public let text: String
}

// MARK: - Git Service

/// Executes git commands for markdown files.
///
/// All operations run `git` as a child process on a background queue.
/// Results are delivered asynchronously via completion handlers on main.
public enum MarkdownGitService {

    /// Checks whether the given file is tracked by git.
    ///
    /// - Parameters:
    ///   - fileURL: The file to check.
    ///   - completion: Called on main with `true` if the file is tracked.
    public static func isTracked(fileURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        let dir = fileURL.deletingLastPathComponent().path
        let file = fileURL.lastPathComponent
        runGit(args: ["ls-files", "--error-unmatch", file], workingDirectory: dir) { output, exitCode in
            DispatchQueue.main.async { completion(exitCode == 0) }
        }
    }

    /// Runs `git blame` on a file and parses the output.
    ///
    /// - Parameters:
    ///   - fileURL: The file to blame.
    ///   - completion: Called on main with the parsed blame lines (empty if not a git file).
    public static func blame(fileURL: URL, completion: @escaping @Sendable ([GitBlameLine]) -> Void) {
        let dir = fileURL.deletingLastPathComponent().path
        let file = fileURL.lastPathComponent
        runGit(args: ["blame", "--porcelain", file], workingDirectory: dir) { output, exitCode in
            let lines = exitCode == 0 ? parseBlameOutput(output) : []
            DispatchQueue.main.async { completion(lines) }
        }
    }

    /// Runs `git diff HEAD` on a file and parses the output.
    ///
    /// - Parameters:
    ///   - fileURL: The file to diff.
    ///   - completion: Called on main with parsed diff hunks (empty if no changes or not tracked).
    public static func diff(fileURL: URL, completion: @escaping @Sendable ([GitDiffHunk]) -> Void) {
        let dir = fileURL.deletingLastPathComponent().path
        let file = fileURL.lastPathComponent
        runGit(args: ["diff", "HEAD", "--", file], workingDirectory: dir) { output, exitCode in
            let hunks = exitCode == 0 ? parseDiffOutput(output) : []
            DispatchQueue.main.async { completion(hunks) }
        }
    }

    // MARK: - Git Execution

    private static func runGit(
        args: [String],
        workingDirectory: String,
        completion: @escaping @Sendable (String, Int32) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                // Drain stdout BEFORE waiting for exit to avoid deadlock.
                // If git produces more than the pipe buffer (~64KB), it blocks
                // on write until someone reads. waitUntilExit() would never
                // return because git is stuck writing.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                completion(output, process.terminationStatus)
            } catch {
                completion("", 1)
            }
        }
    }

    // MARK: - Blame Parsing

    /// Parses `git blame --porcelain` output into structured blame lines.
    public static func parseBlameOutput(_ output: String) -> [GitBlameLine] {
        guard !output.isEmpty else { return [] }

        var results: [GitBlameLine] = []
        let rawLines = output.components(separatedBy: "\n")

        var currentHash = ""
        var currentAuthor = ""
        var currentDate = ""
        var currentLineNumber = 0
        var index = 0

        while index < rawLines.count {
            let line = rawLines[index]

            // Commit header line: <hash> <orig-line> <final-line> [<num-lines>]
            if line.count >= 40, !line.hasPrefix("\t") {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 3 {
                    currentHash = String(parts[0].prefix(8))
                    currentLineNumber = Int(parts[2]) ?? 0
                }
            } else if line.hasPrefix("author ") {
                currentAuthor = String(line.dropFirst(7))
            } else if line.hasPrefix("author-time ") {
                if let timestamp = TimeInterval(String(line.dropFirst(12))) {
                    let date = Date(timeIntervalSince1970: timestamp)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    currentDate = formatter.string(from: date)
                }
            } else if line.hasPrefix("\t") {
                // Content line
                let content = String(line.dropFirst(1))
                results.append(GitBlameLine(
                    commitHash: currentHash,
                    author: currentAuthor,
                    date: currentDate,
                    lineNumber: currentLineNumber,
                    content: content
                ))
            }
            index += 1
        }

        return results
    }

    // MARK: - Diff Parsing

    /// Parses unified diff output into structured hunks.
    public static func parseDiffOutput(_ output: String) -> [GitDiffHunk] {
        guard !output.isEmpty else { return [] }

        var hunks: [GitDiffHunk] = []
        var currentHeader = ""
        var currentLines: [GitDiffLine] = []

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                // Save previous hunk
                if !currentHeader.isEmpty {
                    hunks.append(GitDiffHunk(header: currentHeader, lines: currentLines))
                }
                currentHeader = line
                currentLines = []
            } else if !currentHeader.isEmpty {
                if line.hasPrefix("+") {
                    currentLines.append(GitDiffLine(type: .addition, text: String(line.dropFirst(1))))
                } else if line.hasPrefix("-") {
                    currentLines.append(GitDiffLine(type: .deletion, text: String(line.dropFirst(1))))
                } else if line.hasPrefix(" ") {
                    currentLines.append(GitDiffLine(type: .context, text: String(line.dropFirst(1))))
                }
            }
        }

        // Save last hunk
        if !currentHeader.isEmpty {
            hunks.append(GitDiffHunk(header: currentHeader, lines: currentLines))
        }

        return hunks
    }
}
