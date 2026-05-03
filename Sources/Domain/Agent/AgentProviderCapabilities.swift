// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProviderCapabilities.swift - Local Agent provider capability metadata.

extension AgentProviderKind {
    var supportsAgentImageAttachments: Bool {
        switch self {
        case .foundationModelsOnDevice:
            return false
        case .anthropic, .openai, .google:
            return true
        }
    }
}
