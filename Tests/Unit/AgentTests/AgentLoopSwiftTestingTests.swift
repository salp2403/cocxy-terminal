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
        #expect(result.messages.first { $0.role == .assistant }?.toolCalls == [
            AgentToolCall(id: "call-1", toolID: "git_status"),
        ])
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

    @Test("loop persists parent-linked messages when a thread is provided")
    func loopPersistsParentLinkedMessagesWhenThreadIsProvided() async throws {
        let store = AgentConversationStore(rootDirectory: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(
                content: "I will inspect status.",
                toolCalls: [AgentToolCall(id: "call-status", toolID: "git_status")]
            ),
            AgentLLMResponse(content: "Status is clean enough.", toolCalls: []),
        ])
        let executor = RecordingAgentToolExecutor(results: [
            AgentToolResult.success(
                callID: "call-status",
                toolID: "git_status",
                content: .string("## main")
            ),
        ])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            conversationStore: store,
            idGenerator: StableAgentIDGenerator(prefix: "thread")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Check status",
            configuration: AgentModeConfig(maxIterations: 4),
            imageAttachments: [],
            threadID: " focused "
        )

        #expect(result.stopReason == .completed)
        #expect(result.messages.map(\.threadID) == ["focused", "focused", "focused", "focused"])
        #expect(result.messages.map(\.parentMessageID) == [
            nil,
            "thread-user-1",
            "thread-assistant-2",
            "thread-tool-3",
        ])

        let persisted = try store.load(conversationID: "conv", threadID: "focused")
        #expect(persisted.map(\.id) == result.messages.map(\.id))
        #expect(persisted.map(\.role) == result.messages.map(\.role))
        #expect(persisted.map(\.threadID) == result.messages.map(\.threadID))
        #expect(persisted.map(\.parentMessageID) == result.messages.map(\.parentMessageID))
        #expect(persisted.map(\.content) == result.messages.map(\.content))
        #expect(try store.threadIDs(conversationID: "conv") == ["focused"])
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

        guard case .permissionRequired(let request) = result.stopReason else {
            Issue.record("Expected command approval request")
            return
        }
        #expect(request.id == "call-run")
        #expect(request.call.toolID == "run_command")
        #expect(request.reason == .commandApprovalRequired(
            command: "swift test --filter AgentLoopSwiftTestingTests"
        ))
        #expect(request.preview.kind == .command)
        #expect(request.preview.body.contains("swift test --filter AgentLoopSwiftTestingTests"))
        #expect(calls.isEmpty)
        #expect(result.messages.map(\.role) == [.user, .assistant])
    }

    @Test("loop resumes after an approved request by executing the pending tool")
    func loopResumesAfterApprovedRequest() async throws {
        let pendingCall = AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: ["command": .string("swift test --filter AgentLoopSwiftTestingTests")]
        )
        let request = AgentToolApprovalRequest(
            call: pendingCall,
            reason: .commandApprovalRequired(command: "swift test --filter AgentLoopSwiftTestingTests"),
            preview: AgentToolApprovalPreview(
                kind: .command,
                title: "Run command",
                body: "swift test --filter AgentLoopSwiftTestingTests"
            )
        )
        let history = [
            AgentMessage(id: "u1", role: .user, content: "Run tests"),
            AgentMessage(id: "a1", role: .assistant, content: "I need to run tests."),
        ]
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(content: "Tests finished.", toolCalls: []),
        ])
        let executor = RecordingAgentToolExecutor(results: [
            AgentToolResult.success(
                callID: "call-run",
                toolID: "run_command",
                content: .object(["exitCode": .number(0)])
            ),
        ])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            idGenerator: StableAgentIDGenerator(prefix: "resume")
        )

        let result = try await loop.resume(
            conversationID: "conv",
            approvedRequest: request,
            configuration: AgentModeConfig(maxIterations: 4),
            history: history
        )
        let calls = await executor.calls

        #expect(result.stopReason == .completed)
        #expect(calls == [pendingCall])
        #expect(result.messages.map(\.role) == [.user, .assistant, .tool, .assistant])
        #expect(result.messages.last?.content == "Tests finished.")
    }

    @Test("loop denies approval when preview cannot be generated")
    func loopDeniesApprovalWhenPreviewCannotBeGenerated() async throws {
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(
                content: "I need to write a file.",
                toolCalls: [
                    AgentToolCall(
                        id: "call-write",
                        toolID: "write_file",
                        arguments: [
                            "path": .string("Sources/App.swift"),
                            "content": .string("let value = 2\n"),
                        ]
                    ),
                ]
            ),
        ])
        let executor = RecordingAgentToolExecutor(results: [])
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            toolPreviewer: ThrowingAgentToolPreviewer(),
            idGenerator: StableAgentIDGenerator(prefix: "preview")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Update a file",
            configuration: AgentModeConfig(maxIterations: 4)
        )
        let calls = await executor.calls

        #expect(result.stopReason == .denied(.previewUnavailable(toolID: "write_file")))
        #expect(calls.isEmpty)
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

    @Test("loop forwards provider token usage to the local recorder")
    func loopForwardsProviderUsageToRecorder() async throws {
        let usage = AgentLLMUsage(
            provider: "openai",
            model: "local-model",
            inputTokens: 40,
            outputTokens: 12
        )
        let provider = ScriptedAgentLLMClient(responses: [
            AgentLLMResponse(content: "Done.", usage: usage),
        ])
        let executor = RecordingAgentToolExecutor(results: [])
        let recorder = RecordingAgentUsageRecorder()
        let loop = AgentLoop(
            provider: provider,
            toolExecutor: executor,
            usageRecorder: { usage in
                await recorder.record(usage)
            },
            idGenerator: StableAgentIDGenerator(prefix: "usage")
        )

        let result = try await loop.run(
            conversationID: "conv",
            userPrompt: "Answer",
            configuration: AgentModeConfig(maxIterations: 2)
        )

        #expect(result.stopReason == .completed)
        #expect(await recorder.records == [usage])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-loop-\(UUID().uuidString)", isDirectory: true)
    }
}

private struct ThrowingAgentToolPreviewer: AgentToolPreviewing {
    func preview(for call: AgentToolCall) async throws -> AgentToolApprovalPreview {
        throw PreviewError.failed
    }

    private enum PreviewError: Error {
        case failed
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

private actor RecordingAgentUsageRecorder {
    private(set) var records: [AgentLLMUsage] = []

    func record(_ usage: AgentLLMUsage) {
        records.append(usage)
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
