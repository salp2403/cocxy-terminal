// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRReviewerSuggester.swift - Local reviewer suggestions from git blame.

import Foundation

struct PRReviewerCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let email: String?
    let lineCount: Int
    let fileCount: Int
}

struct PRReviewerSuggester: Sendable {
    typealias BlameProvider = @Sendable (_ root: URL, _ filePath: String) throws -> String

    private let blameProvider: BlameProvider

    init(
        blameProvider: @escaping BlameProvider = { root, filePath in
            try PRReviewerSuggester.gitBlame(root: root, filePath: filePath)
        }
    ) {
        self.blameProvider = blameProvider
    }

    func suggestions(
        root: URL,
        changedFilePaths: [String],
        excludingEmails: Set<String> = [],
        limit: Int = 5
    ) -> [PRReviewerCandidate] {
        guard limit > 0 else { return [] }

        let excluded = Set(excludingEmails.compactMap(Self.normalizedEmail))
        var accumulators: [String: CandidateAccumulator] = [:]

        for filePath in safeRelativePaths(from: changedFilePaths, root: root) {
            guard let blame = try? blameProvider(root, filePath), !blame.isEmpty else {
                continue
            }
            for author in Self.parseBlameAuthors(blame) {
                if let email = author.email, excluded.contains(email) {
                    continue
                }
                let key = author.email ?? "name:\(author.displayName.lowercased())"
                var accumulator = accumulators[key] ?? CandidateAccumulator(
                    displayName: author.displayName,
                    email: author.email
                )
                accumulator.lineCount += 1
                accumulator.filePaths.insert(filePath)
                accumulators[key] = accumulator
            }
        }

        return accumulators.values
            .map(\.candidate)
            .sorted(by: Self.candidateSort)
            .prefix(limit)
            .map { $0 }
    }

    func aiSuggestions(
        root: URL,
        changedFilePaths: [String],
        diff: String,
        settings: GitAssistantSettings,
        client: any AgentLLMClient,
        excludingEmails: Set<String> = [],
        limit: Int = 5
    ) async throws -> [PRReviewerCandidate] {
        guard limit > 0 else { return [] }
        let localCandidates = suggestions(
            root: root,
            changedFilePaths: changedFilePaths,
            excludingEmails: excludingEmails,
            limit: max(limit * 3, limit)
        )
        guard !localCandidates.isEmpty else { return [] }

        let summary = DiffSummarizer(maxLines: min(settings.maxDiffLines, 800))
            .summarize(rawDiff: diff)
        let response = try await client.nextResponse(for: [
            AgentMessage(
                id: "system-git-assistant-reviewers",
                role: .system,
                content: GitAssistantPrompts.systemPrompt(settings: settings)
            ),
            AgentMessage(
                id: "user-reviewer-suggestions",
                role: .user,
                content: Self.aiReviewerPrompt(
                    candidates: localCandidates,
                    summary: summary,
                    limit: limit
                )
            ),
        ])

        let ranked = Self.rankCandidates(
            localCandidates,
            using: response.content,
            limit: limit
        )
        return ranked.isEmpty ? Array(localCandidates.prefix(limit)) : ranked
    }

    private func safeRelativePaths(from paths: [String], root: URL) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { rawPath in
            guard let path = Self.safeRelativePath(rawPath, root: root),
                  seen.insert(path).inserted else {
                return nil
            }
            return path
        }
    }

    private static func safeRelativePath(_ rawPath: String, root: URL) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let rootURL = root.standardizedFileURL
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = rootURL.appendingPathComponent(trimmed, isDirectory: false).standardizedFileURL
        }

        let rootPath = rootURL.path
        guard candidate.path.hasPrefix(rootPath + "/") else {
            return nil
        }

        let relative = String(candidate.path.dropFirst(rootPath.count + 1))
        guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else {
            return nil
        }
        return relative
    }

    private static func aiReviewerPrompt(
        candidates: [PRReviewerCandidate],
        summary: GitAssistantDiffSummary,
        limit: Int
    ) -> String {
        let candidateLines = candidates.map { candidate in
            let email = candidate.email.map { " <\($0)>" } ?? ""
            return "- \(candidate.displayName)\(email): \(candidate.lineCount) blamed lines across \(candidate.fileCount) files"
        }.joined(separator: "\n")
        return """
        Rank up to \(limit) reviewers for this pull request.

        Return only reviewer names or emails, one per line, from the candidate list.
        Do not invent reviewers.

        Candidates:
        \(candidateLines)

        Redacted diff summary:
        \(summary.text)
        """
    }

    private static func rankCandidates(
        _ candidates: [PRReviewerCandidate],
        using rawResponse: String,
        limit: Int
    ) -> [PRReviewerCandidate] {
        var lookup: [String: PRReviewerCandidate] = [:]
        for candidate in candidates {
            lookup[normalizedLookup(candidate.id)] = candidate
            lookup[normalizedLookup(candidate.displayName)] = candidate
            if let email = candidate.email {
                lookup[normalizedLookup(email)] = candidate
            }
        }

        var seen = Set<String>()
        var ranked: [PRReviewerCandidate] = []
        for token in reviewerTokens(from: rawResponse) {
            guard let candidate = lookup[normalizedLookup(token)] else { continue }
            guard seen.insert(candidate.id).inserted else { continue }
            ranked.append(candidate)
            if ranked.count == limit { return ranked }
        }

        for candidate in candidates where ranked.count < limit {
            guard seen.insert(candidate.id).inserted else { continue }
            ranked.append(candidate)
        }
        return ranked
    }

    private static func reviewerTokens(from rawResponse: String) -> [String] {
        rawResponse
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map {
                String($0)
                    .replacingOccurrences(of: #"^\s*[-*\d.)]+\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "<>`"))
            }
            .filter { !$0.isEmpty }
    }

    private static func normalizedLookup(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>`"))
            .lowercased()
    }

    private static func parseBlameAuthors(_ output: String) -> [BlameAuthor] {
        var authors: [BlameAuthor] = []
        var currentName: String?
        var currentEmail: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("author ") {
                let name = String(line.dropFirst("author ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentName = name.isEmpty ? nil : name
            } else if line.hasPrefix("author-mail ") {
                let email = String(line.dropFirst("author-mail ".count))
                currentEmail = normalizedEmail(email)
            } else if line.hasPrefix("\t"), let name = currentName {
                authors.append(BlameAuthor(displayName: name, email: currentEmail))
                currentName = nil
                currentEmail = nil
            }
        }

        return authors
    }

    private static func normalizedEmail(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func candidateSort(_ lhs: PRReviewerCandidate, _ rhs: PRReviewerCandidate) -> Bool {
        if lhs.lineCount != rhs.lineCount {
            return lhs.lineCount > rhs.lineCount
        }
        if lhs.fileCount != rhs.fileCount {
            return lhs.fileCount > rhs.fileCount
        }
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return (lhs.email ?? "") < (rhs.email ?? "")
    }

    private static func gitBlame(root: URL, filePath: String) throws -> String {
        let result = try CodeReviewGit.run(
            workingDirectory: root,
            arguments: ["blame", "--line-porcelain", "--", filePath]
        )
        guard result.terminationStatus == 0 else {
            return ""
        }
        return result.stdout
    }

    private struct BlameAuthor {
        let displayName: String
        let email: String?
    }

    private struct CandidateAccumulator {
        let displayName: String
        let email: String?
        var lineCount = 0
        var filePaths = Set<String>()

        var candidate: PRReviewerCandidate {
            let id = email ?? "name:\(displayName.lowercased())"
            return PRReviewerCandidate(
                id: id,
                displayName: displayName,
                email: email,
                lineCount: lineCount,
                fileCount: filePaths.count
            )
        }
    }
}
