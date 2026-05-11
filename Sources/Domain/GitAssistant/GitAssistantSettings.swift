// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantSettings.swift - Local-first settings for Git Assistant.

import Foundation

enum GitAssistantPromptStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case conventional
    case descriptive
    case minimal
}

struct GitAssistantSettings: Codable, Sendable, Equatable {
    static let minMaxDiffLines = 100
    static let maxMaxDiffLines = 20_000

    let enabled: Bool
    let defaultProvider: AgentProviderKind
    let maxDiffLines: Int
    let promptStyle: GitAssistantPromptStyle
    let autoGeneratePRBodyOnCreate: Bool
    let autoGenerateCommitMessageOnStage: Bool

    static var defaults: GitAssistantSettings {
        GitAssistantSettings()
    }

    init(
        enabled: Bool = true,
        defaultProvider: AgentProviderKind = .foundationModelsOnDevice,
        maxDiffLines: Int = 4_000,
        promptStyle: GitAssistantPromptStyle = .conventional,
        autoGeneratePRBodyOnCreate: Bool = false,
        autoGenerateCommitMessageOnStage: Bool = false
    ) {
        self.enabled = enabled
        self.defaultProvider = defaultProvider
        self.maxDiffLines = Self.clampedMaxDiffLines(maxDiffLines)
        self.promptStyle = promptStyle
        self.autoGeneratePRBodyOnCreate = autoGeneratePRBodyOnCreate
        self.autoGenerateCommitMessageOnStage = autoGenerateCommitMessageOnStage
    }

    private static func clampedMaxDiffLines(_ value: Int) -> Int {
        min(max(value, minMaxDiffLines), maxMaxDiffLines)
    }
}
