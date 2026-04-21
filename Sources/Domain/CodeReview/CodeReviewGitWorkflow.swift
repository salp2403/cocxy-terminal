// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewGitWorkflow.swift - Git workflow actions for Agent Code Review.

import Foundation

struct CodeReviewGitStatus: Equatable, Sendable {
    let branch: String
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let ahead: Int
    let behind: Int

    var changedCount: Int {
        stagedCount + unstagedCount + untrackedCount
    }

    var summary: String {
        var parts = ["\(branch)"]
        if changedCount > 0 {
            parts.append("\(changedCount) changed")
        } else {
            parts.append("clean")
        }
        if ahead > 0 { parts.append("ahead \(ahead)") }
        if behind > 0 { parts.append("behind \(behind)") }
        return parts.joined(separator: " · ")
    }
}

protocol CodeReviewGitWorkflowing: Sendable {
    func status(workingDirectory: URL) throws -> CodeReviewGitStatus
    func createBranch(named branchName: String, workingDirectory: URL) throws
    func commitAll(message: String, workingDirectory: URL) throws -> String
    func pushCurrentBranch(workingDirectory: URL) throws -> String
}

struct CodeReviewGitWorkflowService: CodeReviewGitWorkflowing {

    func status(workingDirectory: URL) throws -> CodeReviewGitStatus {
        let branch = try run(workingDirectory, ["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let porcelain = try run(workingDirectory, ["status", "--porcelain=v1", "--branch"])
        let counts = Self.parsePorcelainStatus(porcelain)
        return CodeReviewGitStatus(
            branch: branch.isEmpty ? "HEAD" : branch,
            stagedCount: counts.staged,
            unstagedCount: counts.unstaged,
            untrackedCount: counts.untracked,
            ahead: counts.ahead,
            behind: counts.behind
        )
    }

    func createBranch(named branchName: String, workingDirectory: URL) throws {
        let sanitized = try Self.sanitizedBranchName(branchName)
        _ = try run(workingDirectory, ["switch", "-c", sanitized])
    }

    func commitAll(message: String, workingDirectory: URL) throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HunkActionError.commandFailed("Commit message cannot be empty.")
        }

        _ = try run(workingDirectory, ["add", "--all"])
        return try run(workingDirectory, ["commit", "-m", trimmed])
    }

    func pushCurrentBranch(workingDirectory: URL) throws -> String {
        let branch = try run(workingDirectory, ["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw HunkActionError.commandFailed("Cannot push from detached HEAD.")
        }
        return try run(workingDirectory, ["push", "-u", "origin", branch])
    }

    private func run(_ workingDirectory: URL, _ arguments: [String]) throws -> String {
        try SessionDiffTrackerImpl.runGit(workingDirectory, arguments)
    }

    static func parsePorcelainStatus(_ output: String) -> (
        staged: Int,
        unstaged: Int,
        untracked: Int,
        ahead: Int,
        behind: Int
    ) {
        var staged = 0
        var unstaged = 0
        var untracked = 0
        var ahead = 0
        var behind = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("##") {
                let text = String(line)
                if let match = text.firstMatch(for: #"ahead ([0-9]+)"#) {
                    ahead = Int(match) ?? 0
                }
                if let match = text.firstMatch(for: #"behind ([0-9]+)"#) {
                    behind = Int(match) ?? 0
                }
                continue
            }

            guard line.count >= 2 else { continue }
            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]
            if x == "?" && y == "?" {
                untracked += 1
                continue
            }
            if x != " " { staged += 1 }
            if y != " " { unstaged += 1 }
        }

        return (staged, unstaged, untracked, ahead, behind)
    }

    static func sanitizedBranchName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HunkActionError.commandFailed("Branch name cannot be empty.")
        }
        guard trimmed.range(of: #"[\s~^:?*\[\\]"#, options: .regularExpression) == nil,
              !trimmed.contains(".."),
              !trimmed.hasPrefix("-"),
              !trimmed.hasSuffix("."),
              !trimmed.hasSuffix("/") else {
            throw HunkActionError.commandFailed("Branch name contains unsupported characters.")
        }
        return trimmed
    }
}

private extension String {
    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: self,
                range: NSRange(startIndex..., in: self)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[range])
    }
}
