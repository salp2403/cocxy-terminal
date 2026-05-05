// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeBranchNameGenerator.swift - Convention-based branch previews.

import Foundation

enum WorktreeBranchNameGenerator {
    static func preview(
        template: WorktreeTemplate,
        summary: String,
        issue: String?,
        agent: String?,
        id: String,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let slug = slugComponent(summary, fallback: "work")
        let issueComponent = cleanIssue(issue, fallback: id)
        let pattern = template.branchPattern
            .replacingOccurrences(of: "{slug}", with: slug)
            .replacingOccurrences(of: "{issue}", with: issueComponent)

        return WorktreeBranch.expand(
            template: pattern,
            agent: agent,
            id: id,
            date: date,
            timeZone: timeZone
        )
    }

    private static func slugComponent(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = WorktreeBranch
            .sanitizeGitRefComponent(trimmed.lowercased())
        return normalized.isEmpty ? fallback : normalized
    }

    private static func cleanIssue(_ raw: String?, fallback: String) -> String {
        guard let raw else { return fallback }
        let normalized = WorktreeBranch.sanitizeGitRefComponent(
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return normalized.isEmpty ? fallback : normalized
    }
}
