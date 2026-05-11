// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BranchListProvider.swift - Local and remote git branch discovery.

import Foundation

typealias GitCommandRunner = @Sendable (URL, [String]) throws -> CodeReviewGitResult

struct BranchListQuery: Equatable, Sendable {
    let searchText: String?
    let includeRemotes: Bool
    let refreshRemotes: Bool

    init(
        searchText: String? = nil,
        includeRemotes: Bool = true,
        refreshRemotes: Bool = false
    ) {
        self.searchText = searchText
        self.includeRemotes = includeRemotes
        self.refreshRemotes = refreshRemotes
    }
}

struct BranchListProvider {
    private let runner: GitCommandRunner

    init(runner: @escaping GitCommandRunner = BranchListProvider.defaultRunner) {
        self.runner = runner
    }

    func listBranches(
        at workingDirectory: URL,
        query: BranchListQuery = BranchListQuery()
    ) throws -> [GitBranch] {
        if query.refreshRemotes {
            try runAndRequireSuccess(
                ["fetch", "--prune", "--all"],
                at: workingDirectory,
                commandName: "git fetch --prune --all"
            )
        }

        let args = [
            "branch",
            "--all",
            "--no-color",
            "--format=%(HEAD)%09%(refname)%09%(refname:short)%09%(upstream:short)%09%(objectname:short)%09%(subject)",
        ]
        let result = try runAndRequireSuccess(
            args,
            at: workingDirectory,
            commandName: "git branch --all"
        )
        return Self.parse(result.stdout)
            .filter { query.includeRemotes || !$0.isRemote }
            .filtered(by: query.searchText)
            .sorted()
    }

    static func parse(_ output: String) -> [GitBranch] {
        output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parseLine)
    }

    private static func parseLine(_ rawLine: Substring) -> GitBranch? {
        let fields = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 5 else { return nil }

        let marker = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRef: String?
        let name: String
        let upstream: String
        let hash: String
        let subject: String

        if fields.count >= 6 {
            fullRef = fields[1]
            name = normalizedBranchName(fields[2])
            upstream = fields[3]
            hash = fields[4]
            subject = fields.dropFirst(5).joined(separator: "\t")
        } else {
            fullRef = nil
            name = normalizedBranchName(fields[1])
            upstream = fields[2]
            hash = fields[3]
            subject = fields.dropFirst(4).joined(separator: "\t")
        }

        guard !name.isEmpty,
              !name.hasSuffix("/HEAD"),
              !name.contains("HEAD ->") else {
            return nil
        }

        let isRemote = fullRef?.contains("refs/remotes/") == true || isRemoteBranchName(name)
        return GitBranch(
            name: name,
            upstreamName: upstream.nilIfBlank,
            isCurrent: marker == "*",
            isRemote: isRemote,
            lastCommitHash: hash.nilIfBlank,
            lastCommitSubject: subject.nilIfBlank
        )
    }

    private static func normalizedBranchName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("remotes/") {
            return String(trimmed.dropFirst("remotes/".count))
        }
        return trimmed
    }

    private static func isRemoteBranchName(_ name: String) -> Bool {
        let firstComponent = name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        return ["origin", "upstream"].contains(firstComponent)
    }

    @discardableResult
    private func runAndRequireSuccess(
        _ args: [String],
        at workingDirectory: URL,
        commandName: String
    ) throws -> CodeReviewGitResult {
        let result = try runner(workingDirectory, args)
        guard result.terminationStatus == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HunkActionError.commandFailed(stderr.isEmpty ? "\(commandName) failed." : stderr)
        }
        return result
    }

    private static let defaultRunner: GitCommandRunner = { workingDirectory, args in
        try CodeReviewGit.run(workingDirectory: workingDirectory, arguments: args)
    }
}

private extension Array where Element == GitBranch {
    func filtered(by searchText: String?) -> [GitBranch] {
        let needle = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !needle.isEmpty else { return self }
        return filter { branch in
            branch.name.lowercased().contains(needle) ||
                branch.upstreamName?.lowercased().contains(needle) == true ||
                branch.lastCommitSubject?.lowercased().contains(needle) == true
        }
    }

    func sorted() -> [GitBranch] {
        sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            if lhs.isRemote != rhs.isRemote { return !lhs.isRemote }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
