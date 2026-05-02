// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLoopSwiftTestingTests.swift - Iterative Agent loop domain contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentLoop")
struct AgentLoopSwiftTestingTests {

    @Test("loop executes an allowed tool call then completes with persisted transcript")
    func loopExecutesAllowedToolCallThenCompletes() async throws {
        let store = AgentConversationStore(rootDirectory: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(
                content: "I will read git status.",
                toolCalls: [AgentToolCall(id: "call-1", toolID: "git_status")]
            ),
            AgentLLMResponse(content: "The repository status is available.", toolCalls: []),
        ])
        let executor = RecordingAgentToolExecutor(results: [
            AgentToolResult.success(
                callID: "call-1",
                toolID: "git_status",
                content: .string("## main...origin/main [ahead 1]")
            ),
        ])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            conversationStore: store,
            idGenerator: StableAgentIDGenerator(prefix: "test")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Check repository state",
            configuration: AgentModeConfig(maxIterations: 4)
        )
        let calls = await executor.calls
        let snapshots = await provider.snapshots

        #expect(result.stopReason == .completed)
        #expect(calls.map(\.toolID) == ["git_status"])
        #expect(snapshots.count == 2)
        let secondProviderSnapshot = try #require(snapshots.dropFirst().first)
        let toolMessage = try #require(secondProviderSnapshot.first { message in
            message.role == .tool
                && message.toolName == "git_status"
                && message.toolCallID == "call-1"
        })
        let decodedToolResult = try JSONDecoder().decode(
            AgentToolResult.self,
            from: Data(toolMessage.content.utf8)
        )
        #expect(decodedToolResult.content == .string("## main...origin/main [ahead 1]"))

        let persisted = try store.load(conversationID: "conv")
        #expect(persisted.map(\.role) == [.user, .assistant, .tool, .assistant])
        #expect(persisted.last?.content == "The repository status is available.")
    }

    @Test("loop stops before executing a command that requires approval")
    func loopStopsBeforeExecutingCommandThatRequiresApproval() async throws {
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(
                content: "I need to run tests.",
                toolCalls: [
                    AgentToolCall(
                        id: "call-run",
                        toolID: "run_command",
                        arguments: ["command": .string("swift test --filter AgentLoopSwiftTestingTests")]
                    ),
                ]
            ),
        ])
        let executor = RecordingAgentToolExecutor(results: [])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            idGenerator: StableAgentIDGenerator(prefix: "approval")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Run focused tests",
            configuration: AgentModeConfig(maxIterations: 4)
        )
        let calls = await executor.calls

        #expect(result.stopReason == .permissionRequired(.commandApprovalRequired(
            command: "swift test --filter AgentLoopSwiftTestingTests"
        )))
        #expect(calls.isEmpty)
        #expect(result.messages.map(\.role) == [.user, .assistant])
    }

    @Test("loop denies dangerous commands before executor is called")
    func loopDeniesDangerousCommandsBeforeExecutor() async throws {
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(
                content: "This command should never run.",
                toolCalls: [
                    AgentToolCall(
                        id: "call-danger",
                        toolID: "run_command",
                        arguments: ["command": .string("rm -rf /")]
                    ),
                ]
            ),
        ])
        let executor = RecordingAgentToolExecutor(results: [])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            idGenerator: StableAgentIDGenerator(prefix: "danger")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Clean everything",
            configuration: AgentModeConfig(maxIterations: 4)
        )
        let calls = await executor.calls

        #expect(result.stopReason == .denied(.dangerousCommand(command: "rm -rf /")))
        #expect(calls.isEmpty)
    }

    @Test("loop stops at max iterations when provider keeps requesting tools")
    func loopStopsAtMaxIterations() async throws {
        let provider = RepeatingAgentLLMClient(response: AgentLLMResponse(
            content: "Reading one more file.",
            toolCalls: [
                AgentToolCall(
                    id: "call-read",
                    toolID: "read_file",
                    arguments: ["path": .string("Package.swift")]
                ),
            ]
        ))
        let executor = RecordingAgentToolExecutor(results: [
            AgentToolResult.success(callID: "call-read", toolID: "read_file", content: .string("contents")),
            AgentToolResult.success(callID: "call-read", toolID: "read_file", content: .string("contents")),
        ])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            idGenerator: StableAgentIDGenerator(prefix: "limit")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Inspect files",
            configuration: AgentModeConfig(maxIterations: 2)
        )
        let callCount = await provider.callCount
        let calls = await executor.calls

        #expect(result.stopReason == .maxIterationsReached)
        #expect(callCount == 2)
        #expect(calls.count == 2)
        #expect(result.messages.map(\.role) == [.user, .assistant, .tool, .assistant, .tool])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-loop-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor ScriptedAgentLLMClient: AgentLLMClient {
    private var responses: [AgentLLMResponse]
    private(set) var snapshots: [[AgentMessage]] = []

    init(responses: [AgentLLMResponse]) {
        self.responses = responses
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        snapshots.append(messages)
        return responses.isEmpty ? AgentLLMResponse(content: "Done", toolCalls: []) : responses.removeFirst()
    }
}

private actor RepeatingAgentLLMClient: AgentLLMClient {
    private let response: AgentLLMResponse
    private(set) var callCount = 0

    init(response: AgentLLMResponse) {
        self.response = response
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        callCount += 1
        return response
    }
}

private actor RecordingAgentToolExecutor: AgentToolExecuting {
    private var results: [AgentToolResult]
    private(set) var calls: [AgentToolCall] = []

    init(results: [AgentToolResult]) {
        self.results = results
    }

    func execute(_ call: AgentToolCall) async throws -> AgentToolResult {
        calls.append(call)
        return results.isEmpty
            ? AgentToolResult.success(callID: call.id, toolID: call.toolID)
            : results.removeFirst()
    }
}

private final class StableAgentIDGenerator: AgentMessageIDGenerating {
    private let prefix: String
    private let lock = NSLock()
    private var nextValue = 0

    init(prefix: String) {
        self.prefix = prefix
    }

    func nextMessageID(role: AgentMessageRole) -> String {
        lock.lock()
        defer { lock.unlock() }
        nextValue += 1
        return "\(prefix)-\(role.rawValue)-\(nextValue)"
    }
}
