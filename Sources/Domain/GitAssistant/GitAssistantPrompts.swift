// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantPrompts.swift - Prompt builders for local Git Assistant tasks.

import Foundation

enum GitAssistantPrompts {
    static func systemPrompt(settings: GitAssistantSettings) -> String {
        """
        You are Cocxy Git Assistant running inside a local macOS terminal.
        Produce concise Git output only. Do not mention private tooling or hidden implementation details.
        The diff has already been redacted for common secrets and personal data. If context is insufficient, return a conservative draft instead of inventing details.
        Preferred style: \(settings.promptStyle.rawValue).
        """
    }

    static func commitMessagePrompt(summary: GitAssistantDiffSummary) -> String {
        """
        Generate one Git commit message for this staged diff.

        Requirements:
        - First line must be a conventional commit subject.
        - Keep subject under 72 characters when practical.
        - Add a short body only when it clarifies behavior or tests.

        Diff stats: +\(summary.additions) -\(summary.deletions)
        Diff:
        \(summary.text)
        """
    }

    static func pullRequestPrompt(
        baseBranch: String,
        headBranch: String,
        summary: GitAssistantDiffSummary
    ) -> String {
        """
        Generate a pull request draft from \(headBranch) into \(baseBranch).

        Return:
        Title: <concise title>

        <markdown body with Summary and Tests sections>

        Diff stats: +\(summary.additions) -\(summary.deletions)
        Diff:
        \(summary.text)
        """
    }

    static func releaseNotesPrompt(groupedCommits: String) -> String {
        """
        Generate concise markdown release notes from these local commits.
        Keep user-facing behavior first and avoid private process details.

        \(groupedCommits)
        """
    }
}
