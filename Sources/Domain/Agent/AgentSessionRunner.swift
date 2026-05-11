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

protocol AgentAttachmentPromptRunning: AgentPromptRunning {
    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig,
        imageAttachments: [AgentImageAttachment]
    ) async throws -> AgentLoopResult
}

extension AgentAttachmentPromptRunning {
    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        try await run(
            prompt: prompt,
            history: history,
            configuration: configuration,
            imageAttachments: []
        )
    }
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
    func makeClient(
        configuration: AgentModeConfig,
        toolRegistry: AgentToolRegistry
    ) throws -> any AgentLLMClient
}

extension AgentProviderClientFactory: AgentLLMClientMaking {}

extension AgentLLMClientMaking {
    func makeClient(
        configuration: AgentModeConfig,
        toolRegistry: AgentToolRegistry
    ) throws -> any AgentLLMClient {
        _ = toolRegistry
        return try makeClient(configuration: configuration)
    }
}

enum AgentSessionRunnerError: Error, Sendable, Equatable {
    case workspaceUnavailable
    case conversationMasterPasswordUnavailable
}

extension AgentSessionRunnerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            return "No active workspace is available for Agent Mode."
        case .conversationMasterPasswordUnavailable:
            return "Agent conversation encryption is enabled, but no master password is saved."
        }
    }
}

struct AgentSessionRunner: AgentApprovalRunning, AgentAttachmentPromptRunning {
    private let clientFactory: any AgentLLMClientMaking
    private let workspaceRootProvider: @MainActor @Sendable () -> URL?
    private let conversationID: String
    private let registry: AgentToolRegistry
    private let permissionPolicy: AgentToolPermissionPolicy
    private let processRunner: any AgentProcessRunning
    private let terminalOutputProvider: (any AgentTerminalOutputProviding)?
    private let lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)?
    private let mcpManager: (any MCPManaging)?
    private let computerUseController: any ComputerUseControlling
    private let commandAllowlist: any AgentCommandAllowlistLoading
    private let agentSecrets: AgentSecrets
    private let usageRecorder: AgentUsageRecording?
    private let spotlightConfigProvider: @MainActor @Sendable () -> SpotlightIndexConfig
    private let spotlightIndexWriter: any SpotlightIndexWriting
    private let securitySandboxConfigProvider: @MainActor @Sendable () -> SecuritySandboxConfig

    init(
        clientFactory: any AgentLLMClientMaking = AgentProviderClientFactory(),
        workspaceRootProvider: @escaping @MainActor @Sendable () -> URL?,
        conversationID: String = "agent-\(UUID().uuidString)",
        registry: AgentToolRegistry = .minimumBuiltIns(),
        permissionPolicy: AgentToolPermissionPolicy = AgentToolPermissionPolicy(),
        processRunner: any AgentProcessRunning = AgentProcessRunner(),
        terminalOutputProvider: (any AgentTerminalOutputProviding)? = nil,
        lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)? = nil,
        mcpManager: (any MCPManaging)? = nil,
        computerUseController: any ComputerUseControlling = ComputerUseActor.liveDefault(),
        commandAllowlist: any AgentCommandAllowlistLoading = AgentCommandAllowlist(),
        agentSecrets: AgentSecrets = AgentSecrets(),
        usageRecorder: AgentUsageRecording? = nil,
        spotlightConfigProvider: @escaping @MainActor @Sendable () -> SpotlightIndexConfig = { .defaults },
        spotlightIndexWriter: any SpotlightIndexWriting = CoreSpotlightIndexWriter(),
        securitySandboxConfigProvider: @escaping @MainActor @Sendable () -> SecuritySandboxConfig = { .defaults }
    ) {
        self.clientFactory = clientFactory
        self.workspaceRootProvider = workspaceRootProvider
        self.conversationID = conversationID
        self.registry = registry
        self.permissionPolicy = permissionPolicy
        self.processRunner = processRunner
        self.terminalOutputProvider = terminalOutputProvider
        self.lspDiagnosticsProvider = lspDiagnosticsProvider
        self.mcpManager = mcpManager
        self.computerUseController = computerUseController
        self.commandAllowlist = commandAllowlist
        self.agentSecrets = agentSecrets
        self.usageRecorder = usageRecorder
        self.spotlightConfigProvider = spotlightConfigProvider
        self.spotlightIndexWriter = spotlightIndexWriter
        self.securitySandboxConfigProvider = securitySandboxConfigProvider
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        try await run(
            prompt: prompt,
            history: history,
            configuration: configuration,
            imageAttachments: []
        )
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig,
        imageAttachments: [AgentImageAttachment]
    ) async throws -> AgentLoopResult {
        let loop = try await makeLoop(
            configuration: configuration,
            approvals: baseApprovalContext(for: configuration)
        )

        return try await loop.run(
            conversationID: conversationID,
            userPrompt: prompt,
            configuration: configuration,
            history: history,
            imageAttachments: imageAttachments
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

        let effectiveRegistry = await effectiveToolRegistry()
        let lineCodec = try conversationLineCodec(from: configuration)
        let provider = try clientFactory.makeClient(
            configuration: configuration,
            toolRegistry: effectiveRegistry
        )
        let commandAllowRules = permissionPolicy.commandAllowRules
            + ((try? commandAllowlist.loadRules()) ?? [])
        let effectiveApprovals = approvals
            .allowingComputerUseWithoutApproval(!configuration.computerUseConfirm)
            .addingCommandAllowRules(commandAllowRules)
        let workspace = AgentWorkspace(rootURL: workspaceRoot)
        let sandboxConfig = await securitySandboxConfigProvider()
        let effectiveProcessRunner: any AgentProcessRunning = AgentSandboxedProcessRunner(
            base: processRunner,
            workspaceURL: workspace.rootURL,
            enabled: sandboxConfig.agentsIsolated,
            auditLog: sandboxConfig.auditLogEnabled
                ? SandboxAuditLog(fileURL: .defaultSandboxAuditLog)
                : nil
        )
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: effectiveApprovals,
            processRunner: effectiveProcessRunner,
            terminalOutputProvider: terminalOutputProvider,
            lspDiagnosticsProvider: lspDiagnosticsProvider,
            mcpManager: mcpManager,
            computerUseController: computerUseController
        )
        let store = AgentConversationStore(
            rootDirectory: Self.conversationRootDirectory(from: configuration.conversationStorageDir),
            lineCodec: lineCodec
        )
        let spotlightConfig = await spotlightConfigProvider()
        let conversationRecorder: any AgentConversationRecording = SpotlightIndexingAgentConversationRecorder(
            base: store,
            conversationID: conversationID,
            workspaceRoot: workspaceRoot,
            config: spotlightConfig,
            writer: spotlightIndexWriter
        )
        let effectivePermissionPolicy = AgentToolPermissionPolicy(
            autoModeEnabled: permissionPolicy.autoModeEnabled,
            computerUseConfirm: configuration.computerUseConfirm,
            commandAllowRules: commandAllowRules
        )

        return AgentLoop(
            provider: provider,
            toolExecutor: executor,
            toolPreviewer: executor,
            registry: effectiveRegistry,
            permissionPolicy: effectivePermissionPolicy,
            conversationStore: conversationRecorder,
            usageRecorder: usageRecorder
        )
    }

    private func effectiveToolRegistry() async -> AgentToolRegistry {
        guard let mcpManager else {
            return registry
        }
        do {
            let descriptors = try await mcpManager.listToolDescriptors()
            return try registry.merging(descriptors)
        } catch {
            return registry
        }
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
        case "computer_move_mouse", "computer_click", "computer_screenshot", "computer_type_text":
            return AgentToolApprovalContext(approvedComputerUseCallIDs: [request.call.id])
        case "ask_user":
            let trimmedInput = userInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedInput.isEmpty else {
                return AgentToolApprovalContext()
            }
            return AgentToolApprovalContext(userInputResponsesByCallID: [request.call.id: trimmedInput])
        default:
            if MCPToolBridge.parseToolID(request.call.toolID) != nil {
                return AgentToolApprovalContext(approvedExternalToolCallIDs: [request.call.id])
            }
            return AgentToolApprovalContext()
        }
    }

    private func baseApprovalContext(for configuration: AgentModeConfig) -> AgentToolApprovalContext {
        AgentToolApprovalContext(computerUseAllowedWithoutApproval: !configuration.computerUseConfirm)
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

    private func conversationLineCodec(from configuration: AgentModeConfig) throws -> AgentConversationLineCodec {
        switch configuration.conversationEncryption {
        case .disabled:
            return .plaintext
        case .masterPassword:
            guard let password = try agentSecrets.conversationMasterPassword() else {
                throw AgentSessionRunnerError.conversationMasterPasswordUnavailable
            }
            return try AgentConversationLineCodec.encrypted(passphrase: password)
        }
    }
}
