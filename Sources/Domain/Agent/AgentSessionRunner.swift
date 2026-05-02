// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSessionRunner.swift - Runtime composition for built-in Agent Mode.

import Foundation

protocol AgentPromptRunning: Sendable {
    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult
}

protocol AgentLLMClientMaking: Sendable {
    func makeClient(configuration: AgentModeConfig) throws -> any AgentLLMClient
}

extension AgentProviderClientFactory: AgentLLMClientMaking {}

enum AgentSessionRunnerError: Error, Sendable, Equatable {
    case workspaceUnavailable
}

extension AgentSessionRunnerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            return "No active workspace is available for Agent Mode."
        }
    }
}

struct AgentSessionRunner: AgentPromptRunning {
    private let clientFactory: any AgentLLMClientMaking
    private let workspaceRootProvider: @MainActor @Sendable () -> URL?
    private let conversationID: String
    private let registry: AgentToolRegistry
    private let permissionPolicy: AgentToolPermissionPolicy
    private let processRunner: any AgentProcessRunning
    private let terminalOutputProvider: (any AgentTerminalOutputProviding)?
    private let lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)?

    init(
        clientFactory: any AgentLLMClientMaking = AgentProviderClientFactory(
            foundationModelsAvailable: false
        ),
        workspaceRootProvider: @escaping @MainActor @Sendable () -> URL?,
        conversationID: String = "agent-\(UUID().uuidString)",
        registry: AgentToolRegistry = .minimumBuiltIns(),
        permissionPolicy: AgentToolPermissionPolicy = AgentToolPermissionPolicy(),
        processRunner: any AgentProcessRunning = AgentProcessRunner(),
        terminalOutputProvider: (any AgentTerminalOutputProviding)? = nil,
        lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)? = nil
    ) {
        self.clientFactory = clientFactory
        self.workspaceRootProvider = workspaceRootProvider
        self.conversationID = conversationID
        self.registry = registry
        self.permissionPolicy = permissionPolicy
        self.processRunner = processRunner
        self.terminalOutputProvider = terminalOutputProvider
        self.lspDiagnosticsProvider = lspDiagnosticsProvider
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        guard let workspaceRoot = await workspaceRootProvider() else {
            throw AgentSessionRunnerError.workspaceUnavailable
        }

        let provider = try clientFactory.makeClient(configuration: configuration)
        let workspace = AgentWorkspace(rootURL: workspaceRoot)
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(),
            processRunner: processRunner,
            terminalOutputProvider: terminalOutputProvider,
            lspDiagnosticsProvider: lspDiagnosticsProvider
        )
        let store = AgentConversationStore(
            rootDirectory: Self.conversationRootDirectory(from: configuration.conversationStorageDir)
        )
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            registry: registry,
            permissionPolicy: permissionPolicy,
            conversationStore: store
        )

        return try await loop.run(
            conversationID: conversationID,
            userPrompt: prompt,
            configuration: configuration,
            history: history
        )
    }

    private static func conversationRootDirectory(from rawPath: String) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredPath = trimmed.isEmpty
            ? AgentModeConfig.defaults.conversationStorageDir
            : rawPath
        let expandedPath = (configuredPath as NSString).expandingTildeInPath

        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath, isDirectory: true)
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(expandedPath, isDirectory: true)
    }
}
