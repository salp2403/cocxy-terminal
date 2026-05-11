// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSandboxProfile.swift - Sandbox profile planning for Agent providers.

import Foundation

struct AgentSandboxProfile: Sendable, Equatable {
    let provider: AgentProviderKind
    let workspaceURL: URL
    let configURL: URL
    let additionalReadableURLs: [URL]

    init(
        provider: AgentProviderKind,
        workspaceURL: URL,
        configURL: URL,
        additionalReadableURLs: [URL] = []
    ) {
        self.provider = provider
        self.workspaceURL = workspaceURL
        self.configURL = configURL
        self.additionalReadableURLs = additionalReadableURLs
    }

    var capabilities: Set<SandboxCapability> {
        var capabilities: Set<SandboxCapability> = [.filesystemRead]
        if provider.requiresNetworkSandboxCapability {
            capabilities.insert(.network)
        }
        return capabilities
    }

    func profile(builder: SandboxProfileBuilder = SandboxProfileBuilder()) -> String {
        builder.profile(
            capabilities: capabilities,
            readablePaths: [workspaceURL, configURL] + additionalReadableURLs,
            writablePaths: [],
            executablePaths: []
        )
    }
}

private extension AgentProviderKind {
    var requiresNetworkSandboxCapability: Bool {
        self != .foundationModelsOnDevice
    }
}
