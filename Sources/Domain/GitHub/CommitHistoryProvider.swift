// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommitHistoryProvider.swift - Paged git log reader for Source Control UI.

import Foundation

struct CommitHistoryQuery: Equatable, Sendable {
    let ref: String?
    let searchText: String?
    let limit: Int
    let skip: Int

    init(
        ref: String? = nil,
        searchText: String? = nil,
        limit: Int = 50,
        skip: Int = 0
    ) {
        self.ref = ref
        self.searchText = searchText
        self.limit = limit
        self.skip = skip
    }
}

struct CommitHistoryProvider {
    private let runner: GitCommandRunner

    init(runner: @escaping GitCommandRunner = CommitHistoryProvider.defaultRunner) {
        self.runner = runner
    }

    func history(
        at workingDirectory: URL,
        query: CommitHistoryQuery = CommitHistoryQuery()
    ) throws -> [GitCommit] {
        let clampedLimit = max(1, min(query.limit, 200))
        let skip = max(0, query.skip)
        var args = ["log"]
        if let ref = query.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ref.isEmpty {
            args.append(ref)
        }
        args.append(contentsOf: [
            "--date=iso-strict",
            "--pretty=format:%H%x09%h%x09%an%x09%ae%x09%aI%x09%D%x09%s",
            "-n", "\(clampedLimit)",
            "--skip", "\(skip)",
        ])

        let result = try runner(workingDirectory, args)
        guard result.terminationStatus == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HunkActionError.commandFailed(stderr.isEmpty ? "git log failed." : stderr)
        }

        return Self.parse(result.stdout)
            .filtered(by: query.searchText)
    }

    static func parse(_ output: String) -> [GitCommit] {
        output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parseLine)
    }

    private static func parseLine(_ rawLine: Substring) -> GitCommit? {
        let fields = rawLine
            .split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count >= 7,
              let authoredAt = parseDate(fields[4]) else {
            return nil
        }
        return GitCommit(
            hash: fields[0],
            shortHash: fields[1],
            subject: fields[6],
            authorName: fields[2],
            authorEmail: fields[3],
            authoredAt: authoredAt,
            refs: fields[5]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }

    private static let defaultRunner: GitCommandRunner = { workingDirectory, args in
        try CodeReviewGit.run(workingDirectory: workingDirectory, arguments: args)
    }
}

private extension Array where Element == GitCommit {
    func filtered(by searchText: String?) -> [GitCommit] {
        let needle = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !needle.isEmpty else { return self }
        return filter { commit in
            commit.hash.lowercased().contains(needle) ||
                commit.shortHash.lowercased().contains(needle) ||
                commit.subject.lowercased().contains(needle) ||
                commit.authorName.lowercased().contains(needle) ||
                commit.authorEmail.lowercased().contains(needle) ||
                commit.refs.contains { $0.lowercased().contains(needle) }
        }
    }
}
