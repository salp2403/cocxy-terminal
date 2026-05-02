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
