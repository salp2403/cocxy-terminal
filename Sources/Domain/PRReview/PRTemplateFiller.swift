// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRTemplateFiller.swift - Local pull request body defaults from repo templates.

import Foundation

struct PRTemplateFiller: Sendable {
    typealias CommitSummaryProvider = @Sendable (_ root: URL, _ baseBranch: String?) -> [String]

    private let commitSummaryProvider: CommitSummaryProvider

    init(
        commitSummaryProvider: @escaping CommitSummaryProvider = { root, baseBranch in
            PRTemplateFiller.gitCommitSummaries(root: root, baseBranch: baseBranch)
        }
    ) {
        self.commitSummaryProvider = commitSummaryProvider
    }

    func body(root: URL, explicitBody: String?, baseBranch: String?) -> String? {
        if let explicit = explicitBody,
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }

        guard let template = readTemplate(at: root) else {
            return nil
        }

        let summaries = sanitizedSummaries(commitSummaryProvider(root, baseBranch))
        guard !summaries.isEmpty, !containsCommitsHeading(template) else {
            return template
        }

        return template + "\n\n## Commits\n\n" + summaries.map { "- \($0)" }.joined(separator: "\n")
    }

    private func readTemplate(at root: URL) -> String? {
        for relativePath in Self.templateSearchPaths {
            let url = root.appendingPathComponent(relativePath, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path),
                  let raw = try? String(contentsOf: url, encoding: .utf8),
                  let template = normalized(raw),
                  !template.isEmpty else {
                continue
            }
            return template
        }
        return nil
    }

    private func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedSummaries(_ summaries: [String]) -> [String] {
        var seen = Set<String>()
        return summaries.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private func containsCommitsHeading(_ template: String) -> Bool {
        template.range(
            of: #"(?m)^\s*#{1,6}\s+commits\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static let templateSearchPaths = [
        ".github/pull_request_template.md",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/pull_request_template.txt",
        "pull_request_template.md",
    ]

    private static func gitCommitSummaries(root: URL, baseBranch: String?) -> [String] {
        for range in commitRanges(root: root, baseBranch: baseBranch) {
            let summaries = logSummaries(root: root, range: range)
            if !summaries.isEmpty {
                return summaries
            }
        }
        return []
    }

    private static func commitRanges(root: URL, baseBranch: String?) -> [String] {
        var ranges: [String] = []

        if let base = baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !base.isEmpty {
            ranges.append("origin/\(base)..HEAD")
            ranges.append("\(base)..HEAD")
        }

        if let originDefault = originDefaultBranch(root: root), !originDefault.isEmpty {
            ranges.append("\(originDefault)..HEAD")
        }

        var seen = Set<String>()
        return ranges.filter { seen.insert($0).inserted }
    }

    private static func originDefaultBranch(root: URL) -> String? {
        guard let result = try? CodeReviewGit.run(
            workingDirectory: root,
            arguments: ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]
        ), result.terminationStatus == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func logSummaries(root: URL, range: String) -> [String] {
        guard let result = try? CodeReviewGit.run(
            workingDirectory: root,
            arguments: ["log", "--format=%s", "--no-merges", "--max-count=12", range]
        ), result.terminationStatus == 0 else {
            return []
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
