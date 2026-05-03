// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLoop.swift - Local iterative Agent Mode orchestration.

import Foundation

struct AgentLLMUsage: Sendable, Equatable {
    let provider: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int

    init(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) {
        let trimmedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.provider = trimmedProvider.isEmpty ? "unknown" : trimmedProvider
        self.model = trimmedModel.isEmpty ? "unknown" : trimmedModel
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
    }
}

struct AgentLLMResponse: Sendable, Equatable {
    let content: String
    let toolCalls: [AgentToolCall]
    let usage: AgentLLMUsage?

    init(
        content: String,
        toolCalls: [AgentToolCall] = [],
        usage: AgentLLMUsage? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

typealias AgentUsageRecording = @Sendable (AgentLLMUsage) async -> Void

protocol AgentLLMClient {
    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse
}

protocol AgentToolExecuting {
    func execute(_ call: AgentToolCall) async throws -> AgentToolResult
}

protocol AgentConversationRecording {
    func append(_ message: AgentMessage, conversationID: String) throws
}

extension AgentConversationStore: AgentConversationRecording {}

protocol AgentMessageIDGenerating {
    func nextMessageID(role: AgentMessageRole) -> String
}

struct UUIDAgentMessageIDGenerator: AgentMessageIDGenerating {
    func nextMessageID(role: AgentMessageRole) -> String {
        "\(role.rawValue)-\(UUID().uuidString)"
    }
}

enum AgentLoopStopReason: Sendable, Equatable {
    case completed
    case maxIterationsReached
    case permissionRequired(AgentToolApprovalRequest)
    case denied(AgentToolDenyReason)
    case protocolFailure(AgentToolProtocolError)
}

struct AgentLoopResult: Sendable, Equatable {
    let messages: [AgentMessage]
    let stopReason: AgentLoopStopReason
}

struct AgentLoop {
    let provider: any AgentLLMClient
    let toolExecutor: any AgentToolExecuting
    let toolPreviewer: (any AgentToolPreviewing)?
    let registry: AgentToolRegistry
    let permissionPolicy: AgentToolPermissionPolicy
    let conversationStore: (any AgentConversationRecording)?
    let idGenerator: any AgentMessageIDGenerating
    let usageRecorder: AgentUsageRecording?

    init(
        provider: any AgentLLMClient,
        toolExecutor: any AgentToolExecuting,
        toolPreviewer: (any AgentToolPreviewing)? = nil,
        registry: AgentToolRegistry = .minimumBuiltIns(),
        permissionPolicy: AgentToolPermissionPolicy = AgentToolPermissionPolicy(),
        conversationStore: (any AgentConversationRecording)? = nil,
        usageRecorder: AgentUsageRecording? = nil,
        idGenerator: any AgentMessageIDGenerating = UUIDAgentMessageIDGenerator()
    ) {
        self.provider = provider
        self.toolExecutor = toolExecutor
        self.toolPreviewer = toolPreviewer
        self.registry = registry
        self.permissionPolicy = permissionPolicy
        self.conversationStore = conversationStore
        self.usageRecorder = usageRecorder
        self.idGenerator = idGenerator
    }

    func run(
        conversationID: String,
        userPrompt: String,
        configuration: AgentModeConfig,
        history: [AgentMessage] = []
    ) async throws -> AgentLoopResult {
        var messages = history
        try append(
            AgentMessage(
                id: idGenerator.nextMessageID(role: .user),
                role: .user,
                content: userPrompt
            ),
            conversationID: conversationID,
            messages: &messages
        )

        return try await continueRun(
            conversationID: conversationID,
            configuration: configuration,
            messages: &messages
        )
    }

    func resume(
        conversationID: String,
        approvedRequest: AgentToolApprovalRequest,
        configuration: AgentModeConfig,
        history: [AgentMessage]
    ) async throws -> AgentLoopResult {
        var messages = history
        let toolResult = try await toolExecutor.execute(approvedRequest.call)
        try append(
            AgentMessage(
                id: idGenerator.nextMessageID(role: .tool),
                role: .tool,
                content: try Self.encodedToolResult(toolResult),
                toolName: toolResult.toolID,
                toolCallID: toolResult.callID
            ),
            conversationID: conversationID,
            messages: &messages
        )

        return try await continueRun(
            conversationID: conversationID,
            configuration: configuration,
            messages: &messages
        )
    }

    private func continueRun(
        conversationID: String,
        configuration: AgentModeConfig,
        messages: inout [AgentMessage]
    ) async throws -> AgentLoopResult {
        let activePermissionPolicy = AgentToolPermissionPolicy(
            autoModeEnabled: configuration.autoMode,
            computerUseConfirm: configuration.computerUseConfirm,
            commandAllowRules: permissionPolicy.commandAllowRules
        )

        for _ in 0..<configuration.maxIterations {
            let response = try await provider.nextResponse(for: messages)
            if let usage = response.usage {
                await usageRecorder?(usage)
            }
            try append(
                AgentMessage(
                    id: idGenerator.nextMessageID(role: .assistant),
                    role: .assistant,
                    content: response.content,
                    toolCalls: response.toolCalls
                ),
                conversationID: conversationID,
                messages: &messages
            )

            guard !response.toolCalls.isEmpty else {
                return AgentLoopResult(messages: messages, stopReason: .completed)
            }

            for call in response.toolCalls {
                let invocation: AgentToolInvocation
                do {
                    invocation = try call.invocation(using: registry)
                } catch let error as AgentToolProtocolError {
                    return AgentLoopResult(messages: messages, stopReason: .protocolFailure(error))
                }

                switch activePermissionPolicy.decision(for: invocation) {
                case .allow:
                    let toolResult = try await toolExecutor.execute(call)
                    try append(
                        AgentMessage(
                            id: idGenerator.nextMessageID(role: .tool),
                            role: .tool,
                            content: try Self.encodedToolResult(toolResult),
                            toolName: toolResult.toolID,
                            toolCallID: toolResult.callID
                        ),
                        conversationID: conversationID,
                        messages: &messages
                    )
                case .prompt(let reason):
                    guard let request = await approvalRequest(for: call, reason: reason) else {
                        return AgentLoopResult(
                            messages: messages,
                            stopReason: .denied(.previewUnavailable(toolID: call.toolID))
                        )
                    }
                    return AgentLoopResult(messages: messages, stopReason: .permissionRequired(request))
                case .deny(let reason):
                    return AgentLoopResult(messages: messages, stopReason: .denied(reason))
                }
            }
        }

        return AgentLoopResult(messages: messages, stopReason: .maxIterationsReached)
    }

    private func approvalRequest(
        for call: AgentToolCall,
        reason: AgentToolPromptReason
    ) async -> AgentToolApprovalRequest? {
        let preview: AgentToolApprovalPreview
        if let toolPreviewer {
            do {
                preview = try await toolPreviewer.preview(for: call)
            } catch {
                return nil
            }
        } else {
            preview = defaultPreview(for: call, reason: reason)
        }
        return AgentToolApprovalRequest(call: call, reason: reason, preview: preview)
    }

    private func defaultPreview(
        for call: AgentToolCall,
        reason: AgentToolPromptReason
    ) -> AgentToolApprovalPreview {
        switch reason {
        case .commandApprovalRequired(let command):
            return AgentToolApprovalPreview(
                kind: .command,
                title: "Approve command",
                body: command
            )
        case .computerUseApprovalRequired(let toolID):
            return AgentToolApprovalPreview(
                kind: .computerUse,
                title: "Approve computer action",
                body: "Allow \(toolID) to control this Mac locally."
            )
        case .externalToolApprovalRequired(let toolID):
            return AgentToolApprovalPreview(
                kind: .externalTool,
                title: "Approve external tool",
                body: "Allow \(toolID) to call a configured local MCP server."
            )
        case .diffPreviewRequired(let toolID):
            return AgentToolApprovalPreview(
                kind: .diff,
                title: "Review changes for \(toolID)",
                body: "Diff preview is unavailable for call \(call.id)."
            )
        case .userInputRequired(let toolID):
            return AgentToolApprovalPreview(
                kind: .userInput,
                title: "Agent requested input",
                body: "The agent requested input for \(toolID)."
            )
        }
    }

    private func append(
        _ message: AgentMessage,
        conversationID: String,
        messages: inout [AgentMessage]
    ) throws {
        messages.append(message)
        try conversationStore?.append(message, conversationID: conversationID)
    }

    private static func encodedToolResult(_ result: AgentToolResult) throws -> String {
        let data = try AgentToolProtocolCodec.encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return json
    }
}
