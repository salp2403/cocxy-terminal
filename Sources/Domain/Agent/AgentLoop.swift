// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLoop.swift - Local iterative Agent Mode orchestration.

import Foundation

struct AgentLLMResponse: Sendable, Equatable {
    let content: String
    let toolCalls: [AgentToolCall]

    init(content: String, toolCalls: [AgentToolCall] = []) {
        self.content = content
        self.toolCalls = toolCalls
    }
}
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
    case permissionRequired(AgentToolPromptReason)
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
    let registry: AgentToolRegistry
    let permissionPolicy: AgentToolPermissionPolicy
    let conversationStore: (any AgentConversationRecording)?
    let idGenerator: any AgentMessageIDGenerating

    init(
        provider: any AgentLLMClient,
        toolExecutor: any AgentToolExecuting,
        registry: AgentToolRegistry = .minimumBuiltIns(),
        permissionPolicy: AgentToolPermissionPolicy = AgentToolPermissionPolicy(),
        conversationStore: (any AgentConversationRecording)? = nil,
        idGenerator: any AgentMessageIDGenerating = UUIDAgentMessageIDGenerator()
    ) {
        self.provider = provider
        self.toolExecutor = toolExecutor
        self.registry = registry
        self.permissionPolicy = permissionPolicy
        self.conversationStore = conversationStore
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

        let activePermissionPolicy = AgentToolPermissionPolicy(
            autoModeEnabled: configuration.autoMode,
            commandAllowRules: permissionPolicy.commandAllowRules
        )

        for _ in 0..<configuration.maxIterations {
            let response = try await provider.nextResponse(for: messages)
            try append(
                AgentMessage(
                    id: idGenerator.nextMessageID(role: .assistant),
                    role: .assistant,
                    content: response.content
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
                    return AgentLoopResult(messages: messages, stopReason: .permissionRequired(reason))
                case .deny(let reason):
                    return AgentLoopResult(messages: messages, stopReason: .denied(reason))
                }
            }
        }

        return AgentLoopResult(messages: messages, stopReason: .maxIterationsReached)
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
