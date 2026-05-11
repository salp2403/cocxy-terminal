// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantGenerators.swift - LLM-backed Git draft generators.

import Foundation

struct CommitMessageGenerator {
    let client: any AgentLLMClient

    func generate(diff: String, settings: GitAssistantSettings) async throws -> GitAssistantCommitMessageDraft {
        let summary = DiffSummarizer(maxLines: settings.maxDiffLines).summarize(rawDiff: diff)
        let response = try await client.nextResponse(for: [
            AgentMessage(id: "system-git-assistant", role: .system, content: GitAssistantPrompts.systemPrompt(settings: settings)),
            AgentMessage(id: "user-commit-message", role: .user, content: GitAssistantPrompts.commitMessagePrompt(summary: summary)),
        ])
        return Self.parse(response.content)
    }

    static func parse(_ raw: String) -> GitAssistantCommitMessageDraft {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let subject = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return GitAssistantCommitMessageDraft(subject: subject, body: body)
    }
}

struct PullRequestDraftGenerator {
    let client: any AgentLLMClient

    func generate(
        baseBranch: String,
        headBranch: String,
        diff: String,
        settings: GitAssistantSettings
    ) async throws -> GitAssistantPullRequestDraft {
        let summary = DiffSummarizer(maxLines: settings.maxDiffLines).summarize(rawDiff: diff)
        let response = try await client.nextResponse(for: [
            AgentMessage(id: "system-git-assistant", role: .system, content: GitAssistantPrompts.systemPrompt(settings: settings)),
            AgentMessage(
                id: "user-pr-draft",
                role: .user,
                content: GitAssistantPrompts.pullRequestPrompt(
                    baseBranch: baseBranch,
                    headBranch: headBranch,
                    summary: summary
                )
            ),
        ])
        return Self.parse(response.content)
    }

    static func parse(_ raw: String) -> GitAssistantPullRequestDraft {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title: String
        if first.lowercased().hasPrefix("title:") {
            title = first.dropFirst("Title:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeFirst()
        } else {
            title = first
            if !lines.isEmpty { lines.removeFirst() }
        }

        let body = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return GitAssistantPullRequestDraft(title: title, body: body)
    }
}

struct ReleaseNotesGenerator {
    let client: any AgentLLMClient

    func generate(
        commits: [GitAssistantCommit],
        settings: GitAssistantSettings
    ) async throws -> GitAssistantReleaseNotesDraft {
        let grouped = Self.groupedCommits(commits)
        let response = try await client.nextResponse(for: [
            AgentMessage(id: "system-git-assistant", role: .system, content: GitAssistantPrompts.systemPrompt(settings: settings)),
            AgentMessage(id: "user-release-notes", role: .user, content: GitAssistantPrompts.releaseNotesPrompt(groupedCommits: grouped)),
        ])
        return GitAssistantReleaseNotesDraft(markdown: response.content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func groupedCommits(_ commits: [GitAssistantCommit]) -> String {
        var groups: [String: [GitAssistantCommit]] = [:]
        for commit in commits {
            groups[groupName(for: commit.subject), default: []].append(commit)
        }

        let order = ["Features", "Bug Fixes", "Documentation", "Tests", "Maintenance", "Other"]
        return order.compactMap { group in
            guard let commits = groups[group], !commits.isEmpty else { return nil }
            let rows = commits.map { "- \($0.hash.prefix(7)) \($0.subject)" }.joined(separator: "\n")
            return "## \(group)\n\(rows)"
        }
        .joined(separator: "\n\n")
    }

    private static func groupName(for subject: String) -> String {
        let lower = subject.lowercased()
        if lower.hasPrefix("feat") { return "Features" }
        if lower.hasPrefix("fix") { return "Bug Fixes" }
        if lower.hasPrefix("docs") { return "Documentation" }
        if lower.hasPrefix("test") { return "Tests" }
        if lower.hasPrefix("chore") || lower.hasPrefix("refactor") || lower.hasPrefix("build") {
            return "Maintenance"
        }
        return "Other"
    }
}
