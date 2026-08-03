// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomeModels.swift - Project home context and action contracts.

import Foundation

struct ProjectHomeGitMetadata: Equatable, Sendable {
    let branch: String
    let remoteOrigin: String?
    let statusSummary: String
    let changedFileCount: Int
}

enum ProjectHomeContextError: Error, Equatable, Sendable {
    case gitStatusUnavailable
    case worktreeManifestUnavailable
}

struct ProjectTeamLaunchRequest: Equatable, Sendable {
    static let maximumPromptBytes = 32_768
    static let maximumTeammates = 8

    let teamID: String
    let provider: AgentTeamProvider
    let teammateNames: [String]
    let prompt: String

    static func make(
        teamName: String,
        provider: AgentTeamProvider?,
        teammates: String,
        prompt: String
    ) throws -> ProjectTeamLaunchRequest {
        let teamID = AgentTeamConfig.slug(teamName)
        let names = teammates
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectTeamLaunchError.emptyTeamName
        }
        guard let provider else { throw ProjectTeamLaunchError.missingProvider }
        guard !names.isEmpty else { throw ProjectTeamLaunchError.emptyTeammates }
        guard names.count <= maximumTeammates else {
            throw ProjectTeamLaunchError.tooManyTeammates(maximum: maximumTeammates)
        }
        guard !trimmedPrompt.isEmpty else { throw ProjectTeamLaunchError.emptyPrompt }
        guard trimmedPrompt.utf8.count <= maximumPromptBytes else {
            throw ProjectTeamLaunchError.promptTooLarge(maximumBytes: maximumPromptBytes)
        }
        return ProjectTeamLaunchRequest(
            teamID: teamID,
            provider: provider,
            teammateNames: names,
            prompt: trimmedPrompt
        )
    }
}

enum ProjectTeamLaunchError: Error, Equatable, Sendable {
    case emptyTeamName
    case missingProvider
    case emptyTeammates
    case tooManyTeammates(maximum: Int)
    case emptyPrompt
    case promptTooLarge(maximumBytes: Int)
}

enum ProjectHomeActionFailure: Error, Equatable, Sendable {
    case servicesUnavailable
    case providerUnavailable
    case projectSessionChanged
    case teamAlreadyRunning
    case teamLaunchFailed
    case worktreeOpenFailed
}
