// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPFoundationSwiftTestingTests.swift - Local MCP integration contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MCP foundation")
struct MCPFoundationSwiftTestingTests {

    @Test("config loader reads user-managed stdio and HTTP MCP servers")
    func configLoaderReadsUserManagedServers() throws {
        let root = temporaryDirectory(named: "mcp-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("mcp.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "/usr/local/bin/github-mcp-server",
              "args": ["stdio"],
              "env": {
                "GITHUB_TOKEN": "${GITHUB_TOKEN}"
              },
              "cwd": "/tmp"
            },
            "docs": {
              "url": "http://127.0.0.1:8765/mcp",
              "headers": {
                "Authorization": "Bearer local-token"
              },
              "enabled": false
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let servers = try MCPServerConfigLoader().loadServers(from: configURL)

        #expect(servers.map(\.id) == ["docs", "github"])
        let docs = try #require(servers.first { $0.id == "docs" })
        #expect(docs.enabled == false)
        if case .http(let url, let headers) = docs.transport {
            #expect(url.absoluteString == "http://127.0.0.1:8765/mcp")
            #expect(headers["Authorization"] == "Bearer local-token")
        } else {
            Issue.record("Expected HTTP MCP server")
        }

        let github = try #require(servers.first { $0.id == "github" })
        #expect(github.enabled == true)
        if case .stdio(let command, let arguments, let environment, let workingDirectory) = github.transport {
            #expect(command == "/usr/local/bin/github-mcp-server")
            #expect(arguments == ["stdio"])
            #expect(environment["GITHUB_TOKEN"] == "${GITHUB_TOKEN}")
            #expect(workingDirectory == "/tmp")
        } else {
            Issue.record("Expected stdio MCP server")
        }
    }

    @Test("config loader rejects invalid server identifiers")
    func configLoaderRejectsInvalidServerIDs() throws {
        let root = temporaryDirectory(named: "mcp-invalid-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("mcp.json")
        try """
        {
          "mcpServers": {
            "Bad Server": {
              "command": "mcp-server"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        #expect(throws: MCPServerConfigError.invalidServerID("Bad Server")) {
            _ = try MCPServerConfigLoader().loadServers(from: configURL)
        }
    }

    @Test("client sends JSON-RPC requests for initialize, tools and resources")
    func clientSendsJSONRPCRequestsForToolsAndResources() async throws {
        let transport = RecordingMCPTransport { request in
            switch request.method {
            case "initialize":
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "protocolVersion": .string("2025-03-26"),
                        "capabilities": .object([
                            "tools": .object([:]),
                            "resources": .object([:]),
                        ]),
                    ])
                )
            case "tools/list":
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("list_prs"),
                                "description": .string("List pull requests"),
                                "inputSchema": .object([
                                    "type": .string("object"),
                                    "properties": .object([
                                        "state": .object([
                                            "type": .string("string"),
                                            "description": .string("Pull request state"),
                                        ]),
                                    ]),
                                    "required": .array([.string("state")]),
                                ]),
                            ]),
                        ]),
                    ])
                )
            case "tools/call":
                #expect(request.params?["name"] == .string("list_prs"))
                #expect(request.params?["arguments"] == .object(["state": .string("open")]))
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("PR #1"),
                            ]),
                        ]),
                    ])
                )
            case "resources/list":
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "resources": .array([
                            .object([
                                "uri": .string("repo://README.md"),
                                "name": .string("README"),
                                "mimeType": .string("text/markdown"),
                            ]),
                        ]),
                    ])
                )
            case "resources/read":
                #expect(request.params?["uri"] == .string("repo://README.md"))
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "contents": .array([
                            .object([
                                "uri": .string("repo://README.md"),
                                "mimeType": .string("text/markdown"),
                                "text": .string("# README"),
                            ]),
                        ]),
                    ])
                )
            default:
                return MCPJSONRPCResponse(
                    id: request.id,
                    error: MCPJSONRPCError(code: -32601, message: "Unknown method")
                )
            }
        }
        let client = MCPClient(
            server: MCPServer(
                id: "github",
                displayName: "GitHub",
                transport: .stdio(command: "github-mcp-server")
            ),
            transport: transport
        )

        let capabilities = try await client.initialize()
        let tools = try await client.listTools()
        let callResult = try await client.callTool(
            name: "list_prs",
            arguments: ["state": .string("open")]
        )
        let resources = try await client.listResources()
        let resourceContent = try await client.readResource(uri: "repo://README.md")
        let requests = await transport.requests

        #expect(capabilities.supportsTools == true)
        #expect(capabilities.supportsResources == true)
        #expect(tools == [
            MCPTool(
                name: "list_prs",
                description: "List pull requests",
                inputSchema: MCPToolInputSchema(
                    properties: [
                        "state": MCPToolInputProperty(type: "string", description: "Pull request state"),
                    ],
                    required: ["state"]
                )
            ),
        ])
        #expect(callResult.content == [.text("PR #1")])
        #expect(resources == [
            MCPResource(uri: "repo://README.md", name: "README", description: nil, mimeType: "text/markdown"),
        ])
        #expect(resourceContent.contents == [
            MCPResourceContent(uri: "repo://README.md", mimeType: "text/markdown", text: "# README"),
        ])
        #expect(requests.map(\.method) == [
            "initialize",
            "tools/list",
            "tools/call",
            "resources/list",
            "resources/read",
        ])
    }

    @Test("tool bridge exposes MCP tools as external Agent descriptors")
    func toolBridgeExposesMCPToolsAsExternalAgentDescriptors() throws {
        let descriptor = MCPToolBridge.descriptor(
            for: MCPTool(
                name: "list-prs",
                description: "List pull requests",
                inputSchema: MCPToolInputSchema(
                    properties: [
                        "state": MCPToolInputProperty(type: "string", description: "Pull request state"),
                        "limit": MCPToolInputProperty(type: "number", description: "Maximum results"),
                    ],
                    required: ["state"]
                )
            ),
            serverID: "github"
        )

        #expect(descriptor.id == "mcp__github__list_prs")
        #expect(descriptor.capability == .external)
        #expect(descriptor.inputSchema.required == ["state"])
        #expect(descriptor.inputSchema.properties["state"]?.type == .string)
        #expect(descriptor.inputSchema.properties["limit"]?.type == .number)
        #expect(MCPToolBridge.parseToolID("mcp__github__list_prs") == MCPToolRoute(
            serverID: "github",
            toolName: "list_prs"
        ))
        #expect(MCPToolBridge.parseToolID("mcp__local_github__list_prs") == MCPToolRoute(
            serverID: "local_github",
            toolName: "list_prs"
        ))

        let policy = AgentToolPermissionPolicy(autoModeEnabled: true)
        #expect(policy.decision(for: AgentToolInvocation(
            toolID: descriptor.id,
            capability: descriptor.capability
        )) == .prompt(.externalToolApprovalRequired(toolID: descriptor.id)))
    }

    @Test("manager calls original MCP tool names after Agent descriptor sanitization")
    func managerCallsOriginalToolNamesAfterDescriptorSanitization() async throws {
        let transport = RecordingMCPTransport { request in
            switch request.method {
            case "tools/list":
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("list-prs"),
                                "description": .string("List pull requests"),
                                "inputSchema": .object(["type": .string("object")]),
                            ]),
                        ]),
                    ])
                )
            case "tools/call":
                #expect(request.params?["name"] == .string("list-prs"))
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("PR #1"),
                            ]),
                        ]),
                    ])
                )
            default:
                return MCPJSONRPCResponse(id: request.id, result: .object([:]))
            }
        }
        let client = MCPClient(
            server: MCPServer(
                id: "github",
                displayName: "GitHub",
                transport: .stdio(command: "github-mcp-server")
            ),
            transport: transport
        )
        let manager = await MCPManager(clients: [client])

        let descriptors = try await manager.listToolDescriptors()
        let result = try await manager.executeTool(
            agentToolID: "mcp__github__list_prs",
            arguments: [:]
        )

        #expect(descriptors.map(\.id) == ["mcp__github__list_prs"])
        #expect(result == .object([
            "isError": .bool(false),
            "content": .array([.string("PR #1")]),
        ]))
    }

    @Test("local executor requires approval before calling an MCP tool")
    func localExecutorRequiresApprovalBeforeCallingMCPTool() async throws {
        let root = temporaryDirectory(named: "mcp-agent-workspace")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = RecordingMCPManager(result: .object([
            "content": .array([.string("PR #1")]),
        ]))
        let call = AgentToolCall(
            id: "call-mcp",
            toolID: "mcp__github__list_prs",
            arguments: ["state": .string("open")]
        )

        let pending = try await AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            mcpManager: manager
        ).execute(call)
        let approved = try await AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedExternalToolCallIDs: ["call-mcp"]),
            mcpManager: manager
        ).execute(call)
        let managerCalls = await manager.calls

        #expect(pending.status == .failure)
        #expect(pending.error?.code == "approval_required")
        #expect(approved.status == .success)
        #expect(try contentObject(approved)["content"] == .array([.string("PR #1")]))
        #expect(managerCalls == [
            RecordingMCPCall(toolID: "mcp__github__list_prs", arguments: ["state": .string("open")]),
        ])
    }

    @Test("session runner advertises MCP tools and executes them after approval")
    func sessionRunnerAdvertisesMCPToolsAndExecutesAfterApproval() async throws {
        let workspace = temporaryDirectory(named: "mcp-session-workspace")
        let conversations = temporaryDirectory(named: "mcp-session-conversations")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: conversations)
        }
        let manager = RecordingMCPManager(result: .object([
            "content": .array([.string("PR #1")]),
        ]))
        let call = AgentToolCall(
            id: "call-mcp",
            toolID: "mcp__github__list_prs",
            arguments: ["state": .string("open")]
        )
        let provider = ScriptedMCPAgentClient(responses: [
            AgentLLMResponse(content: "I will list pull requests.", toolCalls: [call]),
            AgentLLMResponse(content: "PR #1 is open.", toolCalls: []),
        ])
        let factory = RecordingMCPAgentClientFactory(client: provider)
        let runner = AgentSessionRunner(
            clientFactory: factory,
            workspaceRootProvider: { workspace },
            conversationID: "mcp-agent-session",
            mcpManager: manager
        )
        let configuration = AgentModeConfig(
            enabled: true,
            preferredProvider: .openai,
            maxIterations: 4,
            conversationStorageDir: conversations.path
        )

        let pending = try await runner.run(
            prompt: "List open pull requests",
            history: [],
            configuration: configuration
        )
        guard case .permissionRequired(let approval) = pending.stopReason else {
            Issue.record("Expected MCP approval request")
            return
        }
        let completed = try await runner.approve(
            request: approval,
            history: pending.messages,
            configuration: configuration
        )
        let managerCalls = await manager.calls
        let factoryRegistries = factory.registries

        #expect(approval.reason == .externalToolApprovalRequired(toolID: "mcp__github__list_prs"))
        #expect(approval.preview.kind == .externalTool)
        #expect(factoryRegistries.first?.descriptor(for: "mcp__github__list_prs")?.capability == .external)
        #expect(completed.stopReason == .completed)
        #expect(completed.messages.contains { message in
            message.role == .tool
                && message.toolName == "mcp__github__list_prs"
                && message.content.contains("PR #1")
        })
        #expect(managerCalls == [
            RecordingMCPCall(toolID: "mcp__github__list_prs", arguments: ["state": .string("open")]),
        ])
    }
}

private actor RecordingMCPTransport: MCPTransport {
    private let handler: @Sendable (MCPJSONRPCRequest) async throws -> MCPJSONRPCResponse
    private(set) var requests: [MCPJSONRPCRequest] = []

    init(handler: @escaping @Sendable (MCPJSONRPCRequest) async throws -> MCPJSONRPCResponse) {
        self.handler = handler
    }

    func send(_ request: MCPJSONRPCRequest, to server: MCPServer) async throws -> MCPJSONRPCResponse {
        _ = server
        requests.append(request)
        return try await handler(request)
    }
}

private struct RecordingMCPCall: Sendable, Equatable {
    let toolID: String
    let arguments: [String: AgentJSONValue]
}

private actor RecordingMCPManager: MCPManaging {
    let result: AgentJSONValue
    private(set) var calls: [RecordingMCPCall] = []

    init(result: AgentJSONValue) {
        self.result = result
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        [
            AgentToolDescriptor(
                id: "mcp__github__list_prs",
                displayName: "GitHub: list_prs",
                description: "List pull requests",
                capability: .external
            ),
        ]
    }

    func executeTool(agentToolID: String, arguments: [String: AgentJSONValue]) async throws -> AgentJSONValue {
        calls.append(RecordingMCPCall(toolID: agentToolID, arguments: arguments))
        return result
    }
}

private actor ScriptedMCPAgentClient: AgentLLMClient {
    private var responses: [AgentLLMResponse]

    init(responses: [AgentLLMResponse]) {
        self.responses = responses
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        _ = messages
        guard !responses.isEmpty else {
            return AgentLLMResponse(content: "Done.", toolCalls: [])
        }
        return responses.removeFirst()
    }
}

private final class RecordingMCPAgentClientFactory: AgentLLMClientMaking, @unchecked Sendable {
    let client: ScriptedMCPAgentClient
    private let lock = NSLock()
    private var registryStorage: [AgentToolRegistry] = []

    var registries: [AgentToolRegistry] {
        lock.lock()
        defer { lock.unlock() }
        return registryStorage
    }

    init(client: ScriptedMCPAgentClient) {
        self.client = client
    }

    func makeClient(configuration: AgentModeConfig) throws -> any AgentLLMClient {
        _ = configuration
        return client
    }

    func makeClient(
        configuration: AgentModeConfig,
        toolRegistry: AgentToolRegistry
    ) throws -> any AgentLLMClient {
        _ = configuration
        lock.lock()
        registryStorage.append(toolRegistry)
        lock.unlock()
        return client
    }
}

private func temporaryDirectory(named name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func contentObject(_ result: AgentToolResult) throws -> [String: AgentJSONValue] {
    guard case .object(let object) = result.content else {
        throw MCPTestError.missingObjectContent
    }
    return object
}

private enum MCPTestError: Error {
    case missingObjectContent
}
