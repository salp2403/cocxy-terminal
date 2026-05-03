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

    @Test("runner requires saved master password when conversation encryption is enabled")
    func runnerRequiresSavedMasterPasswordForConversationEncryption() async throws {
        let workspace = temporaryDirectory(named: "encrypted-missing-password-workspace")
        let conversationRoot = temporaryDirectory(named: "encrypted-missing-password-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let factory = RecordingSessionRunnerClientFactory(
            client: ScriptedSessionRunnerClient(responses: [])
        )
        let runner = AgentSessionRunner(
            clientFactory: factory,
            workspaceRootProvider: { workspace },
            conversationID: "agent-encrypted-missing-password",
            agentSecrets: AgentSecrets(store: InMemoryAgentSecretStore())
        )

        await #expect(throws: AgentSessionRunnerError.conversationMasterPasswordUnavailable) {
            _ = try await runner.run(
                prompt: "Persist securely",
                history: [],
                configuration: AgentModeConfig(
                    enabled: true,
                    preferredProvider: .openai,
                    conversationStorageDir: conversationRoot.path,
                    conversationEncryption: .masterPassword
                )
            )
        }
        #expect(factory.configurations.isEmpty)
    }

    @Test("runner persists encrypted conversations when master password is configured")
    func runnerPersistsEncryptedConversations() async throws {
        let workspace = temporaryDirectory(named: "encrypted-workspace")
        let conversationRoot = temporaryDirectory(named: "encrypted-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let secretStore = InMemoryAgentSecretStore()
        let secrets = AgentSecrets(store: secretStore)
        try secrets.saveConversationMasterPassword("local-master-password")
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Stored locally.", toolCalls: []),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-encrypted-test",
            agentSecrets: secrets
        )

        let result = try await runner.run(
            prompt: "Persist this secret prompt",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path,
                conversationEncryption: .masterPassword
            )
        )
        let fileURL = AgentConversationStore(rootDirectory: conversationRoot)
            .fileURL(forConversationID: "agent-encrypted-test")
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let decrypted = try AgentConversationStore(
            rootDirectory: conversationRoot,
            lineCodec: try AgentConversationLineCodec.encrypted(passphrase: "local-master-password")
        )
        .load(conversationID: "agent-encrypted-test")

        #expect(result.stopReason == .completed)
        #expect(raw.hasPrefix(AgentConversationEncryptionCodec.linePrefix))
        #expect(!raw.contains("Persist this secret prompt"))
        #expect(!raw.contains("Stored locally."))
        #expect(decrypted.map(\.role) == [.user, .assistant])
        #expect(decrypted.map(\.content) == ["Persist this secret prompt", "Stored locally."])
    }

    @Test("runner applies local command allowlist before prompting")
    func runnerAppliesCommandAllowlistBeforePrompting() async throws {
        let workspace = temporaryDirectory(named: "allowlist-workspace")
        let conversationRoot = temporaryDirectory(named: "allowlist-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "I will run focused tests.",
                toolCalls: [
                    AgentToolCall(
                        id: "call-run",
                        toolID: "run_command",
                        arguments: ["command": .string("swift test --filter AgentSessionRunner")]
                    ),
                ]
            ),
            AgentLLMResponse(content: "Tests passed.", toolCalls: []),
        ])
        let processRunner = RecordingSessionProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-allowlist-test",
            processRunner: processRunner,
            commandAllowlist: StaticAgentCommandAllowlist(rules: [
                .prefix("swift test --filter"),
            ])
        )

        let result = try await runner.run(
            prompt: "Run focused tests",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path
            )
        )

        #expect(result.stopReason == .completed)
        #expect(result.messages.map(\.role) == [.user, .assistant, .tool, .assistant])
        #expect(processRunner.calls.map(\.arguments) == [
            ["-lc", "swift test --filter AgentSessionRunner"],
        ])
    }

    @Test("runner wires terminal output provider into read_terminal_output tool")
    func runnerWiresTerminalOutputProvider() async throws {
        let workspace = temporaryDirectory(named: "terminal-output-workspace")
        let conversationRoot = temporaryDirectory(named: "terminal-output-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "Reading terminal context.",
                toolCalls: [
                    AgentToolCall(
                        id: "read-terminal-1",
                        toolID: "read_terminal_output",
                        arguments: ["limit": .number(3)]
                    ),
                ]
            ),
            AgentLLMResponse(content: "I saw the recent command output.", toolCalls: []),
        ])
        let terminalOutputProvider = RecordingSessionTerminalOutputProvider(
            output: "recent command output\n"
        )
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-terminal-output-test",
            terminalOutputProvider: terminalOutputProvider
        )

        let result = try await runner.run(
            prompt: "Read terminal output",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path
            )
        )
        let terminalToolMessage = try #require(result.messages.first { message in
            message.role == .tool && message.toolName == "read_terminal_output"
        })

        #expect(result.stopReason == .completed)
        #expect(terminalOutputProvider.limits == [3])
        #expect(terminalToolMessage.content.contains("recent command output"))
    }

    @Test("runner wires LSP diagnostics provider into read_lsp_diagnostics tool")
    func runnerWiresLSPDiagnosticsProvider() async throws {
        let workspace = temporaryDirectory(named: "lsp-diagnostics-workspace")
        let conversationRoot = temporaryDirectory(named: "lsp-diagnostics-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "Reading diagnostics.",
                toolCalls: [
                    AgentToolCall(
                        id: "read-lsp-1",
                        toolID: "read_lsp_diagnostics",
                        arguments: ["limit": .number(2)]
                    ),
                ]
            ),
            AgentLLMResponse(content: "I saw the diagnostics.", toolCalls: []),
        ])
        let diagnosticsProvider = RecordingSessionLSPDiagnosticsProvider(diagnostics: [
            AgentLSPDiagnostic(
                path: "Sources/App.swift",
                line: 12,
                column: 8,
                severity: "error",
                message: "Cannot find value.",
                source: "sourcekit"
            ),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-lsp-diagnostics-test",
            lspDiagnosticsProvider: diagnosticsProvider
        )

        let result = try await runner.run(
            prompt: "Read LSP diagnostics",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                maxIterations: 4,
                conversationStorageDir: conversationRoot.path
            )
        )
        let diagnosticsToolMessage = try #require(result.messages.first { message in
            message.role == .tool && message.toolName == "read_lsp_diagnostics"
        })

        #expect(result.stopReason == .completed)
        #expect(diagnosticsProvider.limits == [2])
        #expect(diagnosticsToolMessage.content.contains("App.swift"))
        #expect(diagnosticsToolMessage.content.contains("Cannot find value."))
    }

    @Test("runner prompts for computer use by default before executing")
    func runnerPromptsForComputerUseByDefault() async throws {
        let workspace = temporaryDirectory(named: "computer-use-prompt-workspace")
        let conversationRoot = temporaryDirectory(named: "computer-use-prompt-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "I need to inspect the screen.",
                toolCalls: [AgentToolCall(id: "shot-1", toolID: "computer_screenshot")]
            ),
        ])
        let controller = RecordingSessionComputerUseController(result: .screenshot(
            fileURL: URL(fileURLWithPath: "/tmp/cocxy-runner-shot.png"),
            width: 100,
            height: 80
        ))
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-computer-use-prompt-test",
            computerUseController: controller
        )

        let result = try await runner.run(
            prompt: "Inspect screen",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                conversationStorageDir: conversationRoot.path
            )
        )

        if case .permissionRequired(let request) = result.stopReason {
            #expect(request.reason == .computerUseApprovalRequired(toolID: "computer_screenshot"))
            #expect(request.preview.kind == .computerUse)
        } else {
            Issue.record("Expected computer use approval request")
        }
        #expect(await controller.actions.isEmpty)
    }

    @Test("runner executes computer use without prompt only when config disables per-action confirmation")
    func runnerExecutesComputerUseWhenConfirmationDisabled() async throws {
        let workspace = temporaryDirectory(named: "computer-use-run-workspace")
        let conversationRoot = temporaryDirectory(named: "computer-use-run-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let screenshotURL = URL(fileURLWithPath: "/tmp/cocxy-runner-shot.png")
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "Capturing screen.",
                toolCalls: [AgentToolCall(id: "shot-1", toolID: "computer_screenshot")]
            ),
            AgentLLMResponse(content: "Screen captured locally.", toolCalls: []),
        ])
        let controller = RecordingSessionComputerUseController(result: .screenshot(
            fileURL: screenshotURL,
            width: 100,
            height: 80
        ))
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-computer-use-run-test",
            computerUseController: controller
        )

        let result = try await runner.run(
            prompt: "Capture screen",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                computerUseConfirm: false,
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
        #expect(await controller.actions == [.screenshot(.mainDisplay)])
        #expect(await controller.promptFlags == [true])
        #expect(decodedToolResult.content == .object([
            "action": .string("screenshot.main_display"),
            "path": .string(screenshotURL.path),
            "width": .number(100),
            "height": .number(80),
        ]))
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

    @Test("runner forwards provider token usage to the injected recorder")
    func runnerForwardsProviderUsageToRecorder() async throws {
        let workspace = temporaryDirectory(named: "usage-workspace")
        let conversationRoot = temporaryDirectory(named: "usage-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let usage = AgentLLMUsage(
            provider: "openai",
            model: "local-model",
            inputTokens: 88,
            outputTokens: 13
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Usage captured.", usage: usage),
        ])
        let recorder = RecordingSessionUsageRecorder()
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-usage-test",
            usageRecorder: { usage in
                await recorder.record(usage)
            }
        )

        let result = try await runner.run(
            prompt: "Answer",
            history: [],
            configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                conversationStorageDir: conversationRoot.path
            )
        )

        #expect(result.stopReason == .completed)
        #expect(await recorder.records == [usage])
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

private struct StaticAgentCommandAllowlist: AgentCommandAllowlistLoading {
    let rules: [AgentCommandAllowRule]

    func loadRules() throws -> [AgentCommandAllowRule] {
        rules
    }
}

private actor RecordingSessionUsageRecorder {
    private(set) var records: [AgentLLMUsage] = []

    func record(_ usage: AgentLLMUsage) {
        records.append(usage)
    }
}

private final class RecordingSessionProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [AgentSessionProcessCall] = []
    private var results: [AgentProcessResult]

    init(results: [AgentProcessResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        calls.append(AgentSessionProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        ))
        return results.isEmpty
            ? AgentProcessResult(exitCode: 0, stdout: "", stderr: "")
            : results.removeFirst()
    }
}

private struct AgentSessionProcessCall: Equatable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private final class RecordingSessionTerminalOutputProvider: AgentTerminalOutputProviding, @unchecked Sendable {
    private let output: String
    private(set) var limits: [Int] = []

    init(output: String) {
        self.output = output
    }

    func latestCommandBlockOutputs(limit: Int) -> String {
        limits.append(limit)
        return output
    }
}

private final class RecordingSessionLSPDiagnosticsProvider: AgentLSPDiagnosticsProviding, @unchecked Sendable {
    private let diagnostics: [AgentLSPDiagnostic]
    private(set) var limits: [Int] = []

    init(diagnostics: [AgentLSPDiagnostic]) {
        self.diagnostics = diagnostics
    }

    func currentDiagnostics(limit: Int) -> [AgentLSPDiagnostic] {
        limits.append(limit)
        return Array(diagnostics.prefix(max(0, limit)))
    }
}

private actor RecordingSessionComputerUseController: ComputerUseControlling {
    private(set) var actions: [ComputerUseAction] = []
    private(set) var promptFlags: [Bool] = []
    let result: ComputerUseResult

    init(result: ComputerUseResult) {
        self.result = result
    }

    func perform(_ action: ComputerUseAction, promptForPermission: Bool) async throws -> ComputerUseResult {
        actions.append(action)
        promptFlags.append(promptForPermission)
        return result
    }
}
