// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSessionRunnerSwiftTestingTests.swift - Agent Mode runtime composition contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentSessionRunner")
struct AgentSessionRunnerSwiftTestingTests {

    @Test("runner composes provider, local tools and JSONL conversation persistence")
    func runnerComposesProviderToolsAndPersistence() async throws {
        let workspace = temporaryDirectory(named: "workspace")
        let conversationRoot = temporaryDirectory(named: "conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try "Hello from Cocxy\n".write(
            to: workspace.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "Reading README.",
                toolCalls: [
                    AgentToolCall(
                        id: "read-1",
                        toolID: "read_file",
                        arguments: ["path": .string("README.md")]
                    ),
                ]
            ),
            AgentLLMResponse(content: "The README says hello.", toolCalls: []),
        ])
        let factory = RecordingSessionRunnerClientFactory(client: provider)
        let runner = AgentSessionRunner(
            clientFactory: factory,
            workspaceRootProvider: { workspace },
            conversationID: "agent-session-test"
        )

        let result = try await runner.run(
            prompt: "Inspect README",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path
            )
        )
        let snapshots = await provider.snapshots
        let persisted = try AgentConversationStore(rootDirectory: conversationRoot)
            .load(conversationID: "agent-session-test")

        #expect(result.stopReason == .completed)
        #expect(factory.configurations.map(\.preferredProvider) == [.openai])
        #expect(snapshots.count == 2)
        #expect(snapshots.last?.contains(where: { message in
            message.role == .tool
                && message.toolName == "read_file"
                && message.content.contains("Hello from Cocxy")
        }) == true)
        #expect(persisted.map(\.role) == [.user, .assistant, .tool, .assistant])
    }

    @Test("runner fails before provider creation when no workspace is available")
    func runnerRequiresWorkspace() async throws {
        let factory = RecordingSessionRunnerClientFactory(
            client: ScriptedSessionRunnerClient(responses: [])
        )
        let runner = AgentSessionRunner(
            clientFactory: factory,
            workspaceRootProvider: { () -> URL? in nil },
            conversationID: "missing-workspace"
        )

        await #expect(throws: AgentSessionRunnerError.workspaceUnavailable) {
            _ = try await runner.run(
                prompt: "Inspect",
                history: [],
                configuration: AgentModeConfig(enabled: true, preferredProvider: .openai)
            )
        }
        #expect(factory.configurations.isEmpty)
    }

    @Test("runner approval resumes a pending write and persists the tool result")
    func runnerApprovalResumesPendingWriteAndPersistsToolResult() async throws {
        let workspace = temporaryDirectory(named: "approval-workspace")
        let conversationRoot = temporaryDirectory(named: "approval-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        let target = workspace.appendingPathComponent("Sources/App.swift")
        try "let value = 1\n".write(to: target, atomically: true, encoding: .utf8)

        let call = AgentToolCall(
            id: "call-write",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string("let value = 2\n"),
            ]
        )
        let request = AgentToolApprovalRequest(
            call: call,
            reason: .diffPreviewRequired(toolID: "write_file"),
            preview: AgentToolApprovalPreview(
                kind: .diff,
                title: "Review changes to Sources/App.swift",
                body: "--- a/Sources/App.swift\n+++ b/Sources/App.swift\n"
            )
        )
        let history = [
            AgentMessage(id: "u1", role: .user, content: "Update the file"),
            AgentMessage(id: "a1", role: .assistant, content: "I need to edit Sources/App.swift."),
        ]
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Updated Sources/App.swift.", toolCalls: []),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-approval-test"
        )

        let result = try await runner.approve(
            request: request,
            history: history,
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path
            )
        )
        let persisted = try AgentConversationStore(rootDirectory: conversationRoot)
            .load(conversationID: "agent-approval-test")

        #expect(result.stopReason == .completed)
        #expect(try String(contentsOf: target, encoding: .utf8) == "let value = 2\n")
        #expect(result.messages.map(\.role) == [.user, .assistant, .tool, .assistant])
        #expect(result.messages.last?.content == "Updated Sources/App.swift.")
        #expect(persisted.map(\.role) == [.tool, .assistant])
    }

    @Test("runner approval resumes a pending user question with the human answer")
    func runnerApprovalResumesPendingUserQuestion() async throws {
        let workspace = temporaryDirectory(named: "ask-user-workspace")
        let conversationRoot = temporaryDirectory(named: "ask-user-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let call = AgentToolCall(
            id: "call-ask",
            toolID: "ask_user",
            arguments: ["prompt": .string("Which branch should I use?")]
        )
        let request = AgentToolApprovalRequest(
            call: call,
            reason: .userInputRequired(toolID: "ask_user"),
            preview: AgentToolApprovalPreview(
                kind: .userInput,
                title: "Agent requested input",
                body: "Which branch should I use?"
            )
        )
        let history = [
            AgentMessage(id: "u1", role: .user, content: "Prepare the change"),
            AgentMessage(id: "a1", role: .assistant, content: "I need clarification."),
        ]
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "I will use main.", toolCalls: []),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-ask-user-test"
        )

        let result = try await runner.approve(
            request: request,
            userInput: "Use main.",
            history: history,
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path
            )
        )
        let toolMessage = try #require(result.messages.first { $0.role == .tool })
        let decodedToolResult = try JSONDecoder().decode(
            AgentToolResult.self,
            from: Data(toolMessage.content.utf8)
        )

        #expect(result.stopReason == .completed)
        #expect(decodedToolResult.status == .success)
        #expect(decodedToolResult.content == AgentJSONValue.object([
            "prompt": AgentJSONValue.string("Which branch should I use?"),
            "answer": AgentJSONValue.string("Use main."),
        ]))
        #expect(result.messages.last?.content == "I will use main.")
    }

    private func temporaryDirectory(named name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-runner-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor ScriptedSessionRunnerClient: AgentLLMClient {
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

private final class RecordingSessionRunnerClientFactory: AgentLLMClientMaking, @unchecked Sendable {
    private let client: any AgentLLMClient
    private let lock = NSLock()
    private var configurationStorage: [AgentModeConfig] = []

    var configurations: [AgentModeConfig] {
        lock.lock()
        defer { lock.unlock() }
        return configurationStorage
    }

    init(client: any AgentLLMClient) {
        self.client = client
    }

    func makeClient(configuration: AgentModeConfig) throws -> any AgentLLMClient {
        lock.lock()
        configurationStorage.append(configuration)
        lock.unlock()
        return client
    }
}
