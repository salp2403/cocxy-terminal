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

protocol AgentApprovalRunning: AgentPromptRunning {
    func approve(
        request: AgentToolApprovalRequest,
        userInput: String?,
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

struct AgentSessionRunner: AgentApprovalRunning {
    private let clientFactory: any AgentLLMClientMaking
    private let workspaceRootProvider: @MainActor @Sendable () -> URL?
    private let conversationID: String
    private let registry: AgentToolRegistry
    private let permissionPolicy: AgentToolPermissionPolicy
    private let processRunner: any AgentProcessRunning
    private let terminalOutputProvider: (any AgentTerminalOutputProviding)?
    private let lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)?
    private let commandAllowlist: any AgentCommandAllowlistLoading

    init(
        clientFactory: any AgentLLMClientMaking = AgentProviderClientFactory(),
        workspaceRootProvider: @escaping @MainActor @Sendable () -> URL?,
        conversationID: String = "agent-\(UUID().uuidString)",
        registry: AgentToolRegistry = .minimumBuiltIns(),
        permissionPolicy: AgentToolPermissionPolicy = AgentToolPermissionPolicy(),
        processRunner: any AgentProcessRunning = AgentProcessRunner(),
        terminalOutputProvider: (any AgentTerminalOutputProviding)? = nil,
        lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)? = nil,
        commandAllowlist: any AgentCommandAllowlistLoading = AgentCommandAllowlist()
    ) {
        self.clientFactory = clientFactory
        self.workspaceRootProvider = workspaceRootProvider
        self.conversationID = conversationID
        self.registry = registry
        self.permissionPolicy = permissionPolicy
        self.processRunner = processRunner
        self.terminalOutputProvider = terminalOutputProvider
        self.lspDiagnosticsProvider = lspDiagnosticsProvider
        self.commandAllowlist = commandAllowlist
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        let loop = try await makeLoop(
            configuration: configuration,
            approvals: AgentToolApprovalContext()
        )

        return try await loop.run(
            conversationID: conversationID,
            userPrompt: prompt,
            configuration: configuration,
            history: history
        )
    }

    func approve(
        request: AgentToolApprovalRequest,
        userInput: String? = nil,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        let loop = try await makeLoop(
            configuration: configuration,
            approvals: approvalContext(for: request, userInput: userInput)
        )

        return try await loop.resume(
            conversationID: conversationID,
            approvedRequest: request,
            configuration: configuration,
            history: history
        )
    }

    private func makeLoop(
        configuration: AgentModeConfig,
        approvals: AgentToolApprovalContext
    ) async throws -> AgentLoop {
        guard let workspaceRoot = await workspaceRootProvider() else {
            throw AgentSessionRunnerError.workspaceUnavailable
        }

        let provider = try clientFactory.makeClient(configuration: configuration)
        let commandAllowRules = permissionPolicy.commandAllowRules
            + ((try? commandAllowlist.loadRules()) ?? [])
        let effectiveApprovals = approvals.addingCommandAllowRules(commandAllowRules)
        let workspace = AgentWorkspace(rootURL: workspaceRoot)
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: effectiveApprovals,
            processRunner: processRunner,
            terminalOutputProvider: terminalOutputProvider,
            lspDiagnosticsProvider: lspDiagnosticsProvider
        )
        let store = AgentConversationStore(
            rootDirectory: Self.conversationRootDirectory(from: configuration.conversationStorageDir)
        )
        let effectivePermissionPolicy = AgentToolPermissionPolicy(
            autoModeEnabled: permissionPolicy.autoModeEnabled,
            commandAllowRules: commandAllowRules
        )

        return AgentLoop(
            provider: provider,
            toolExecutor: executor,
            toolPreviewer: executor,
            registry: registry,
            permissionPolicy: effectivePermissionPolicy,
            conversationStore: store
        )
    }

    private func approvalContext(
        for request: AgentToolApprovalRequest,
        userInput: String?
    ) -> AgentToolApprovalContext {
        switch request.call.toolID {
        case "write_file", "apply_diff":
            return AgentToolApprovalContext(approvedWriteCallIDs: [request.call.id])
        case "run_command":
            return AgentToolApprovalContext(approvedCommandCallIDs: [request.call.id])
        case "ask_user":
            let trimmedInput = userInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedInput.isEmpty else {
                return AgentToolApprovalContext()
            }
            return AgentToolApprovalContext(userInputResponsesByCallID: [request.call.id: trimmedInput])
        default:
            return AgentToolApprovalContext()
        }
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
