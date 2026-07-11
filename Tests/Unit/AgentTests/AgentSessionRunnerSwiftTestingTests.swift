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

    @Test("runner applies local exact command allowlist before prompting")
    func runnerAppliesExactCommandAllowlistBeforePrompting() async throws {
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
                .exact("swift test --filter AgentSessionRunner"),
            ]),
            securitySandboxConfigProvider: {
                SecuritySandboxConfig(
                    pluginsStrict: true,
                    agentsIsolated: false,
                    mcpIsolated: true,
                    auditLogEnabled: false,
                    warnOnGrant: true
                )
            }
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

    @Test("runner previews prefix-matched commands and executes only after approval")
    func runnerPromptsForPrefixMatchedCommands() async throws {
        let workspace = temporaryDirectory(named: "prefix-prompt-workspace")
        let conversationRoot = temporaryDirectory(named: "prefix-prompt-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let command = "printf allowed; printf appended"
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "I will run the command.",
                toolCalls: [
                    AgentToolCall(
                        id: "call-prefix",
                        toolID: "run_command",
                        arguments: ["command": .string(command)]
                    ),
                ]
            ),
            AgentLLMResponse(content: "Command completed.", toolCalls: []),
        ])
        let processRunner = RecordingSessionProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "allowedappended", stderr: ""),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-prefix-prompt-test",
            processRunner: processRunner,
            commandAllowlist: StaticAgentCommandAllowlist(rules: [
                .prefix("printf allowed"),
            ]),
            securitySandboxConfigProvider: {
                SecuritySandboxConfig(
                    pluginsStrict: true,
                    agentsIsolated: false,
                    mcpIsolated: true,
                    auditLogEnabled: false,
                    warnOnGrant: true
                )
            }
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            maxIterations: 4,
            conversationStorageDir: conversationRoot.path
        )

        let pending = try await runner.run(
            prompt: "Run the command",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected command approval for a preserved prefix rule")
            return
        }

        #expect(request.reason == .commandApprovalRequired(command: command))
        #expect(request.preview.kind == .command)
        #expect(request.preview.body.contains("command: \(command)"))
        #expect(processRunner.calls.isEmpty)

        let completed = try await runner.approve(
            request: request,
            history: pending.messages,
            configuration: configuration
        )

        #expect(completed.stopReason == .completed)
        #expect(processRunner.calls.map(\.arguments) == [["-lc", command]])
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

    @Test("runner combines codebase search skills and approved MCP tools in one session")
    func runnerCombinesCodebaseSearchSkillsAndApprovedMCPTools() async throws {
        let workspace = temporaryDirectory(named: "local-context-workspace")
        let conversationRoot = temporaryDirectory(named: "local-context-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "func restoreTerminalPalette() {}\n".write(
            to: workspace.appendingPathComponent("Sources/RestoreCoordinator.swift"),
            atomically: true,
            encoding: .utf8
        )
        try writeProjectSkill(
            id: "local-context",
            name: "Local Context",
            summary: "Use local project context.",
            body: "Prefer local files, local skills, and local tool outputs.",
            in: workspace
        )

        let mcpCall = AgentToolCall(
            id: "mcp-lookup",
            toolID: "mcp__local__lookup",
            arguments: ["query": .string("restore")]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "Gathering local context.",
                toolCalls: [
                    AgentToolCall(id: "skills-list", toolID: "list_skills"),
                    AgentToolCall(
                        id: "skill-use",
                        toolID: "use_skill",
                        arguments: ["id": .string("local-context")]
                    ),
                    AgentToolCall(
                        id: "codebase-search",
                        toolID: "search_codebase",
                        arguments: [
                            "query": .string("restore palette"),
                            "limit": .number(5),
                        ]
                    ),
                ]
            ),
            AgentLLMResponse(
                content: "Calling approved local MCP tool.",
                toolCalls: [mcpCall]
            ),
            AgentLLMResponse(content: "Combined local context and MCP result.", toolCalls: []),
        ])
        let factory = RecordingSessionRunnerClientFactory(client: provider)
        let mcpManager = RecordingSessionMCPManager(result: .object([
            "content": .array([.string("MCP local restore result")]),
        ]))
        let runner = AgentSessionRunner(
            clientFactory: factory,
            workspaceRootProvider: { workspace },
            conversationID: "agent-local-context-integration",
            mcpManager: mcpManager
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            maxIterations: 5,
            conversationStorageDir: conversationRoot.path
        )

        let pending = try await runner.run(
            prompt: "Use local context and then call the local MCP lookup.",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let approval) = pending.stopReason else {
            Issue.record("Expected MCP approval after local context tools ran")
            return
        }
        let secondSnapshot = try #require(await provider.snapshots.dropFirst().first)
        #expect(approval.reason == .externalToolApprovalRequired(toolID: "mcp__local__lookup"))
        #expect(factory.registries.first?.descriptor(for: "search_codebase")?.capability == .read)
        #expect(factory.registries.first?.descriptor(for: "use_skill")?.capability == .read)
        #expect(factory.registries.first?.descriptor(for: "mcp__local__lookup")?.capability == .external)
        #expect(secondSnapshot.contains { message in
            message.role == .tool
                && message.toolName == "list_skills"
                && message.content.contains("local-context")
        })
        #expect(secondSnapshot.contains { message in
            message.role == .tool
                && message.toolName == "use_skill"
                && message.content.contains("Prefer local files")
        })
        #expect(secondSnapshot.contains { message in
            message.role == .tool
                && message.toolName == "search_codebase"
                && message.content.contains("RestoreCoordinator.swift")
        })

        let completed = try await runner.approve(
            request: approval,
            history: pending.messages,
            configuration: configuration
        )

        #expect(completed.stopReason == .completed)
        #expect(completed.messages.contains { message in
            message.role == .tool
                && message.toolName == "mcp__local__lookup"
                && message.content.contains("MCP local restore result")
        })
        #expect(await mcpManager.calls == [
            AgentSessionMCPCall(toolID: "mcp__local__lookup", arguments: ["query": .string("restore")]),
        ])
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

    @Test("runner discloses the exact keyboard payload before approved execution")
    func runnerDisclosesExactKeyboardPayloadBeforeExecution() async throws {
        let workspace = temporaryDirectory(named: "computer-type-preview-workspace")
        let conversationRoot = temporaryDirectory(named: "computer-type-preview-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let payload = "printf safe-preview\n"
        let call = AgentToolCall(
            id: "type-1",
            toolID: "computer_type_text",
            arguments: ["text": .string(payload)]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "I need to type text.", toolCalls: [call]),
            AgentLLMResponse(content: "Text typed.", toolCalls: []),
        ])
        let controller = RecordingSessionComputerUseController(
            result: .keyboardTyped(characters: payload.count)
        )
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-computer-type-preview-test",
            computerUseController: controller
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )

        let pending = try await runner.run(
            prompt: "Type locally",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected computer type approval request")
            return
        }
        #expect(request.call == call)
        #expect(request.preview.body.contains("current global keyboard focus"))
        #expect(request.preview.body.contains(#""printf\u{20}safe-preview\n""#))
        #expect(await controller.actions.isEmpty)

        let completed = try await runner.approve(
            request: request,
            history: pending.messages,
            configuration: configuration
        )

        #expect(completed.stopReason == .completed)
        #expect(await controller.actions == [.keyboard(.typeText(payload))])
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
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(
                content: "I need to edit Sources/App.swift.",
                toolCalls: [call]
            ),
            AgentLLMResponse(content: "Updated Sources/App.swift.", toolCalls: []),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "agent-approval-test"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            maxIterations: 4,
            conversationStorageDir: conversationRoot.path
        )

        let pending = try await runner.run(
            prompt: "Update the file",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a bound write approval request")
            return
        }

        let result = try await runner.approve(
            request: request,
            history: pending.messages,
            configuration: configuration
        )
        let persisted = try AgentConversationStore(rootDirectory: conversationRoot)
            .load(conversationID: "agent-approval-test")

        #expect(result.stopReason == .completed)
        #expect(try String(contentsOf: target, encoding: .utf8) == "let value = 2\n")
        #expect(result.messages.map(\.role) == [.user, .assistant, .tool, .assistant])
        #expect(result.messages.last?.content == "Updated Sources/App.swift.")
        #expect(request.binding != nil)
        #expect(persisted.map(\.role) == [.user, .assistant, .tool, .assistant])
    }

    @Test("write approval fails closed when the active workspace changes")
    @MainActor
    func writeApprovalRejectsActiveWorkspaceChange() async throws {
        let workspaceA = temporaryDirectory(named: "write-drift-a")
        let workspaceB = temporaryDirectory(named: "write-drift-b")
        let conversationRoot = temporaryDirectory(named: "write-drift-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspaceA)
            try? FileManager.default.removeItem(at: workspaceB)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let targetA = workspaceA.appendingPathComponent("target.txt")
        let targetB = workspaceB.appendingPathComponent("target.txt")
        try "workspace-a\n".write(to: targetA, atomically: true, encoding: .utf8)
        try "workspace-b\n".write(to: targetB, atomically: true, encoding: .utf8)
        let call = AgentToolCall(
            id: "call-write-drift",
            toolID: "write_file",
            arguments: [
                "path": .string("target.txt"),
                "content": .string("approved\n"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this write.", toolCalls: [call]),
            AgentLLMResponse(content: "Write completed."),
        ])
        let selection = MutableSessionWorkspaceRoot(workspaceA)
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { selection.rootURL },
            conversationID: "write-workspace-drift"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )

        let pending = try await runner.run(
            prompt: "Update target.txt",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a write approval request")
            return
        }
        #expect(request.preview.body.contains("-workspace-a"))
        selection.rootURL = workspaceB

        await #expect(throws: AgentToolApprovalError.staleContext) {
            _ = try await runner.approve(
                request: request,
                history: pending.messages,
                configuration: configuration
            )
        }
        #expect(try String(contentsOf: targetA, encoding: .utf8) == "workspace-a\n")
        #expect(try String(contentsOf: targetB, encoding: .utf8) == "workspace-b\n")
    }

    @Test("approval call ID cannot authorize changed file arguments")
    func approvalCallIDCannotAuthorizeChangedArguments() async throws {
        let workspace = temporaryDirectory(named: "write-call-identity-workspace")
        let conversationRoot = temporaryDirectory(named: "write-call-identity-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let target = workspace.appendingPathComponent("target.txt")
        try "original\n".write(to: target, atomically: true, encoding: .utf8)
        let call = AgentToolCall(
            id: "call-write-identity",
            toolID: "write_file",
            arguments: [
                "path": .string("target.txt"),
                "content": .string("previewed-change\n"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this write.", toolCalls: [call]),
            AgentLLMResponse(content: "Write completed."),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "write-call-identity"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )
        let pending = try await runner.run(
            prompt: "Update target.txt",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a write approval request")
            return
        }
        let changedCall = AgentToolCall(
            id: request.call.id,
            toolID: request.call.toolID,
            arguments: [
                "path": .string("target.txt"),
                "content": .string("different-change\n"),
            ]
        )
        let changedRequest = AgentToolApprovalRequest(
            call: changedCall,
            reason: request.reason,
            preview: request.preview,
            binding: request.binding
        )

        await #expect(throws: AgentToolApprovalError.staleContext) {
            _ = try await runner.approve(
                request: changedRequest,
                history: pending.messages,
                configuration: configuration
            )
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "original\n")
    }

    @Test("apply_diff approval fails closed when the active workspace changes")
    @MainActor
    func applyDiffApprovalRejectsActiveWorkspaceChange() async throws {
        let workspaceA = temporaryDirectory(named: "apply-drift-a")
        let workspaceB = temporaryDirectory(named: "apply-drift-b")
        let conversationRoot = temporaryDirectory(named: "apply-drift-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspaceA)
            try? FileManager.default.removeItem(at: workspaceB)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let targetA = workspaceA.appendingPathComponent("target.txt")
        let targetB = workspaceB.appendingPathComponent("target.txt")
        try "alpha-a\n".write(to: targetA, atomically: true, encoding: .utf8)
        try "alpha-b\n".write(to: targetB, atomically: true, encoding: .utf8)
        let call = AgentToolCall(
            id: "call-apply-drift",
            toolID: "apply_diff",
            arguments: [
                "path": .string("target.txt"),
                "oldText": .string("alpha-a"),
                "newText": .string("approved"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this diff.", toolCalls: [call]),
            AgentLLMResponse(content: "Diff completed."),
        ])
        let selection = MutableSessionWorkspaceRoot(workspaceA)
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { selection.rootURL },
            conversationID: "apply-workspace-drift"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )

        let pending = try await runner.run(
            prompt: "Apply the change",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected an apply_diff approval request")
            return
        }
        selection.rootURL = workspaceB

        await #expect(throws: AgentToolApprovalError.staleContext) {
            _ = try await runner.approve(
                request: request,
                history: pending.messages,
                configuration: configuration
            )
        }
        #expect(try String(contentsOf: targetA, encoding: .utf8) == "alpha-a\n")
        #expect(try String(contentsOf: targetB, encoding: .utf8) == "alpha-b\n")
    }

    @Test("command approval binds both implicit and explicit cwd to the preview workspace")
    @MainActor
    func commandApprovalRejectsWorkspaceChangeForImplicitAndExplicitCWD() async throws {
        let cwdValues: [String?] = [nil, "Sources"]
        for (index, rawCWD) in cwdValues.enumerated() {
            let workspaceA = temporaryDirectory(named: "command-drift-a-\(index)")
            let workspaceB = temporaryDirectory(named: "command-drift-b-\(index)")
            let conversationRoot = temporaryDirectory(named: "command-drift-conversations-\(index)")
            defer {
                try? FileManager.default.removeItem(at: workspaceA)
                try? FileManager.default.removeItem(at: workspaceB)
                try? FileManager.default.removeItem(at: conversationRoot)
            }
            try FileManager.default.createDirectory(
                at: workspaceA.appendingPathComponent("Sources", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: workspaceB.appendingPathComponent("Sources", isDirectory: true),
                withIntermediateDirectories: true
            )
            var arguments: [String: AgentJSONValue] = ["command": .string("printf approved")]
            if let rawCWD {
                arguments["cwd"] = .string(rawCWD)
            }
            let call = AgentToolCall(
                id: "call-command-drift-\(index)",
                toolID: "run_command",
                arguments: arguments
            )
            let provider = ScriptedSessionRunnerClient(responses: [
                AgentLLMResponse(content: "Review this command.", toolCalls: [call]),
                AgentLLMResponse(content: "Command completed."),
            ])
            let processRunner = RecordingSessionProcessRunner(results: [
                AgentProcessResult(exitCode: 0, stdout: "approved", stderr: ""),
            ])
            let selection = MutableSessionWorkspaceRoot(workspaceA)
            let runner = AgentSessionRunner(
                clientFactory: RecordingSessionRunnerClientFactory(client: provider),
                workspaceRootProvider: { selection.rootURL },
                conversationID: "command-workspace-drift-\(index)",
                processRunner: processRunner
            )
            let configuration = AgentModeConfig(
                enabled: true,
                preferredProvider: .openai,
                conversationStorageDir: conversationRoot.path
            )

            let pending = try await runner.run(
                prompt: "Run the command",
                history: [],
                configuration: configuration
            )
            guard case .permissionRequired(let request) = pending.stopReason else {
                Issue.record("Expected a command approval request")
                continue
            }
            selection.rootURL = workspaceB

            await #expect(throws: AgentToolApprovalError.staleContext) {
                _ = try await runner.approve(
                    request: request,
                    history: pending.messages,
                    configuration: configuration
                )
            }
            #expect(processRunner.calls.isEmpty)
        }
    }

    @Test("write approval rejects a retargeted relative symlink in the same workspace")
    func writeApprovalRejectsRetargetedFile() async throws {
        let workspace = temporaryDirectory(named: "write-retarget-workspace")
        let conversationRoot = temporaryDirectory(named: "write-retarget-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let firstTarget = workspace.appendingPathComponent("first.txt")
        let secondTarget = workspace.appendingPathComponent("second.txt")
        let link = workspace.appendingPathComponent("target.txt")
        try "first\n".write(to: firstTarget, atomically: true, encoding: .utf8)
        try "second\n".write(to: secondTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstTarget)
        let call = AgentToolCall(
            id: "call-write-retarget",
            toolID: "write_file",
            arguments: [
                "path": .string("target.txt"),
                "content": .string("approved\n"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this write.", toolCalls: [call]),
            AgentLLMResponse(content: "Write completed."),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "write-retarget"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )
        let pending = try await runner.run(
            prompt: "Update target.txt",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a write approval request")
            return
        }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondTarget)

        await #expect(throws: AgentToolApprovalError.staleContext) {
            _ = try await runner.approve(
                request: request,
                history: pending.messages,
                configuration: configuration
            )
        }
        #expect(try String(contentsOf: firstTarget, encoding: .utf8) == "first\n")
        #expect(try String(contentsOf: secondTarget, encoding: .utf8) == "second\n")
    }

    @Test("command approval rejects a retargeted cwd in the same workspace")
    func commandApprovalRejectsRetargetedCWD() async throws {
        let workspace = temporaryDirectory(named: "command-retarget-workspace")
        let conversationRoot = temporaryDirectory(named: "command-retarget-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let firstDirectory = workspace.appendingPathComponent("First", isDirectory: true)
        let secondDirectory = workspace.appendingPathComponent("Second", isDirectory: true)
        let link = workspace.appendingPathComponent("Current", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstDirectory)
        let call = AgentToolCall(
            id: "call-command-retarget",
            toolID: "run_command",
            arguments: [
                "command": .string("printf approved"),
                "cwd": .string("Current"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this command.", toolCalls: [call]),
            AgentLLMResponse(content: "Command completed."),
        ])
        let processRunner = RecordingSessionProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "approved", stderr: ""),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "command-retarget",
            processRunner: processRunner
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )
        let pending = try await runner.run(
            prompt: "Run the command",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a command approval request")
            return
        }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondDirectory)

        await #expect(throws: AgentToolApprovalError.staleContext) {
            _ = try await runner.approve(
                request: request,
                history: pending.messages,
                configuration: configuration
            )
        }
        #expect(processRunner.calls.isEmpty)
    }

    @Test("write approval rejects file content changed after preview")
    func writeApprovalRejectsChangedFileContents() async throws {
        let workspace = temporaryDirectory(named: "write-content-workspace")
        let conversationRoot = temporaryDirectory(named: "write-content-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let target = workspace.appendingPathComponent("target.txt")
        try "previewed\n".write(to: target, atomically: true, encoding: .utf8)
        let call = AgentToolCall(
            id: "call-write-content",
            toolID: "write_file",
            arguments: [
                "path": .string("target.txt"),
                "content": .string("approved\n"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this write.", toolCalls: [call]),
            AgentLLMResponse(content: "Write completed."),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "write-content-change"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )
        let pending = try await runner.run(
            prompt: "Update target.txt",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a write approval request")
            return
        }
        let handle = try FileHandle(forWritingTo: target)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("changed-after-preview\n".utf8))
        try handle.close()

        await #expect(throws: AgentToolApprovalError.staleContext) {
            _ = try await runner.approve(
                request: request,
                history: pending.messages,
                configuration: configuration
            )
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "changed-after-preview\n")
    }

    @Test("equivalent canonical workspace root resumes an approved explicit cwd")
    @MainActor
    func equivalentCanonicalWorkspaceRootResumesCommand() async throws {
        let container = temporaryDirectory(named: "canonical-root-container")
        let conversationRoot = temporaryDirectory(named: "canonical-root-conversations")
        defer {
            try? FileManager.default.removeItem(at: container)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let workspace = container.appendingPathComponent("Workspace", isDirectory: true)
        let sources = workspace.appendingPathComponent("Sources", isDirectory: true)
        let alias = container.appendingPathComponent("WorkspaceAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: workspace)
        let call = AgentToolCall(
            id: "call-canonical-root",
            toolID: "run_command",
            arguments: [
                "command": .string("printf approved"),
                "cwd": .string("Sources"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this command.", toolCalls: [call]),
            AgentLLMResponse(content: "Command completed."),
        ])
        let processRunner = RecordingSessionProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "approved", stderr: ""),
        ])
        let selection = MutableSessionWorkspaceRoot(workspace)
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { selection.rootURL },
            conversationID: "canonical-root",
            processRunner: processRunner,
            securitySandboxConfigProvider: {
                SecuritySandboxConfig(
                    pluginsStrict: true,
                    agentsIsolated: false,
                    mcpIsolated: true,
                    auditLogEnabled: false,
                    warnOnGrant: true
                )
            }
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )
        let pending = try await runner.run(
            prompt: "Run the command",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected a command approval request")
            return
        }
        selection.rootURL = alias

        let result = try await runner.approve(
            request: request,
            history: pending.messages,
            configuration: configuration
        )

        #expect(result.stopReason == .completed)
        #expect(processRunner.calls.map(\.workingDirectory) == [
            sources.standardizedFileURL.resolvingSymlinksInPath(),
        ])
    }

    @Test("runner approval normally resumes a pending apply_diff")
    func runnerApprovalResumesPendingApplyDiff() async throws {
        let workspace = temporaryDirectory(named: "apply-normal-workspace")
        let conversationRoot = temporaryDirectory(named: "apply-normal-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversationRoot)
        }
        let target = workspace.appendingPathComponent("target.txt")
        try "before\n".write(to: target, atomically: true, encoding: .utf8)
        let call = AgentToolCall(
            id: "call-apply-normal",
            toolID: "apply_diff",
            arguments: [
                "path": .string("target.txt"),
                "oldText": .string("before"),
                "newText": .string("after"),
            ]
        )
        let provider = ScriptedSessionRunnerClient(responses: [
            AgentLLMResponse(content: "Review this diff.", toolCalls: [call]),
            AgentLLMResponse(content: "Diff completed."),
        ])
        let runner = AgentSessionRunner(
            clientFactory: RecordingSessionRunnerClientFactory(client: provider),
            workspaceRootProvider: { workspace },
            conversationID: "apply-normal"
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            conversationStorageDir: conversationRoot.path
        )
        let pending = try await runner.run(
            prompt: "Apply the change",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let request) = pending.stopReason else {
            Issue.record("Expected an apply_diff approval request")
            return
        }

        let result = try await runner.approve(
            request: request,
            history: pending.messages,
            configuration: configuration
        )

        #expect(result.stopReason == .completed)
        #expect(try String(contentsOf: target, encoding: .utf8) == "after\n")
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

    private func writeProjectSkill(
        id: String,
        name: String,
        summary: String,
        body: String,
        in root: URL
    ) throws {
        let directory = root
            .appendingPathComponent(".cocxy/skills", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        id: \(id)
        name: \(name)
        description: \(summary)
        ---
        # \(name)

        \(body)
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}

@MainActor
private final class MutableSessionWorkspaceRoot {
    var rootURL: URL?

    init(_ rootURL: URL?) {
        self.rootURL = rootURL
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
    private var registryStorage: [AgentToolRegistry] = []

    var configurations: [AgentModeConfig] {
        lock.lock()
        defer { lock.unlock() }
        return configurationStorage
    }

    var registries: [AgentToolRegistry] {
        lock.lock()
        defer { lock.unlock() }
        return registryStorage
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

    func makeClient(
        configuration: AgentModeConfig,
        toolRegistry: AgentToolRegistry
    ) throws -> any AgentLLMClient {
        lock.lock()
        configurationStorage.append(configuration)
        registryStorage.append(toolRegistry)
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

private struct AgentSessionMCPCall: Sendable, Equatable {
    let toolID: String
    let arguments: [String: AgentJSONValue]
}

private actor RecordingSessionMCPManager: MCPManaging {
    private let result: AgentJSONValue
    private(set) var calls: [AgentSessionMCPCall] = []

    init(result: AgentJSONValue) {
        self.result = result
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        [
            AgentToolDescriptor(
                id: "mcp__local__lookup",
                displayName: "Local: lookup",
                description: "Look up local MCP context.",
                capability: .external
            ),
        ]
    }

    func executeTool(agentToolID: String, arguments: [String: AgentJSONValue]) async throws -> AgentJSONValue {
        calls.append(AgentSessionMCPCall(toolID: agentToolID, arguments: arguments))
        return result
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
