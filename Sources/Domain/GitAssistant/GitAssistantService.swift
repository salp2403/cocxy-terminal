// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantService.swift - Orchestrates local Git Assistant generators.

import Foundation

protocol GitAssistantService {
    func generateCommitMessage(
        diff: String,
        settings: GitAssistantSettings
    ) async throws -> GitAssistantCommitMessageDraft

    func generatePullRequestDraft(
        baseBranch: String,
        headBranch: String,
        diff: String,
        settings: GitAssistantSettings
    ) async throws -> GitAssistantPullRequestDraft

    func generateReleaseNotes(
        commits: [GitAssistantCommit],
        settings: GitAssistantSettings
    ) async throws -> GitAssistantReleaseNotesDraft
}

struct DefaultGitAssistantService: GitAssistantService {
    let client: any AgentLLMClient

    func generateCommitMessage(
        diff: String,
        settings: GitAssistantSettings
    ) async throws -> GitAssistantCommitMessageDraft {
        try await CommitMessageGenerator(client: client).generate(diff: diff, settings: settings)
    }

    func generatePullRequestDraft(
        baseBranch: String,
        headBranch: String,
        diff: String,
        settings: GitAssistantSettings
    ) async throws -> GitAssistantPullRequestDraft {
        try await PullRequestDraftGenerator(client: client).generate(
            baseBranch: baseBranch,
            headBranch: headBranch,
            diff: diff,
            settings: settings
        )
    }

    func generateReleaseNotes(
        commits: [GitAssistantCommit],
        settings: GitAssistantSettings
    ) async throws -> GitAssistantReleaseNotesDraft {
        try await ReleaseNotesGenerator(client: client).generate(commits: commits, settings: settings)
    }
}
