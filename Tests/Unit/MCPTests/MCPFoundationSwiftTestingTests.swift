// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPFoundationSwiftTestingTests.swift - Local MCP integration contracts.

import Darwin
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

    @Test("config loader rejects invalid explicit stdio environment keys")
    func configLoaderRejectsInvalidExplicitStdioEnvironmentKeys() throws {
        let root = temporaryDirectory(named: "mcp-invalid-env-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("mcp.json")
        try """
        {
          "mcpServers": {
            "local": {
              "command": "mcp-server",
              "env": {
                "BAD-KEY": "1"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        #expect(throws: MCPServerConfigError.invalidEnvironmentKey("local", "BAD-KEY")) {
            _ = try MCPServerConfigLoader().loadServers(from: configURL)
        }
    }

    @Test("config loader reads HTTP bearer authorization from environment reference")
    func configLoaderReadsHTTPBearerAuthorizationFromEnvironmentReference() throws {
        let root = temporaryDirectory(named: "mcp-auth-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("mcp.json")
        try """
        {
          "mcpServers": {
            "docs": {
              "url": "http://127.0.0.1:8765/mcp",
              "authorization": {
                "type": "bearer",
                "tokenEnv": "MCP_DOCS_TOKEN"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let servers = try MCPServerConfigLoader().loadServers(from: configURL)
        let docs = try #require(servers.first)

        #expect(docs.authorization == .bearerToken(environmentKey: "MCP_DOCS_TOKEN"))
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

    @Test("HTTP transport sends MCP JSON headers")
    func httpTransportSendsMCPJSONHeaders() async throws {
        let httpTransport = RecordingMCPHTTPTransport { request in
            #expect(request.method == "POST")
            #expect(request.headers["Content-Type"] == "application/json")
            #expect(request.headers["Accept"] == "application/json, text/event-stream")
            return AgentHTTPResponse(
                statusCode: 200,
                data: try AgentToolProtocolCodec.encode(MCPJSONRPCResponse(
                    id: "1",
                    result: .object(["ok": .bool(true)])
                ))
            )
        }
        let transport = MCPHTTPTransport(httpTransport: httpTransport)
        let server = MCPServer(
            id: "docs",
            transport: .http(url: URL(string: "http://127.0.0.1:8765/mcp")!)
        )

        let response = try await transport.send(
            MCPJSONRPCRequest(id: "1", method: "ping"),
            to: server
        )

        #expect(response.result == .object(["ok": .bool(true)]))
    }

    @Test("HTTP transport resolves configured bearer authorization without storing token in config")
    func httpTransportResolvesConfiguredBearerAuthorization() async throws {
        let httpTransport = RecordingMCPHTTPTransport { request in
            #expect(request.headers["Authorization"] == "Bearer local-oauth-token")
            return AgentHTTPResponse(
                statusCode: 200,
                data: try AgentToolProtocolCodec.encode(MCPJSONRPCResponse(
                    id: "1",
                    result: .object(["ok": .bool(true)])
                ))
            )
        }
        let transport = MCPHTTPTransport(
            httpTransport: httpTransport,
            authorizationResolver: MCPAuthorizationResolver(environment: [
                "MCP_DOCS_TOKEN": "local-oauth-token",
            ])
        )
        let server = MCPServer(
            id: "docs",
            authorization: .bearerToken(environmentKey: "MCP_DOCS_TOKEN"),
            transport: .http(
                url: URL(string: "http://127.0.0.1:8765/mcp")!,
                headers: ["Authorization": "Bearer stale-config-token"]
            )
        )

        let response = try await transport.send(
            MCPJSONRPCRequest(id: "1", method: "ping"),
            to: server
        )

        #expect(response.result == .object(["ok": .bool(true)]))
    }

    @Test("HTTP transport fails closed when configured bearer token is missing")
    func httpTransportFailsClosedWhenConfiguredBearerTokenIsMissing() async throws {
        let transport = MCPHTTPTransport(
            httpTransport: RecordingMCPHTTPTransport { _ in
                Issue.record("HTTP request should not be sent without the configured token")
                return AgentHTTPResponse(statusCode: 200, data: Data())
            },
            authorizationResolver: MCPAuthorizationResolver(environment: [:])
        )
        let server = MCPServer(
            id: "docs",
            authorization: .bearerToken(environmentKey: "MCP_DOCS_TOKEN"),
            transport: .http(url: URL(string: "http://127.0.0.1:8765/mcp")!)
        )

        await #expect(throws: MCPAuthorizationError.missingEnvironmentVariable("MCP_DOCS_TOKEN")) {
            _ = try await transport.send(
                MCPJSONRPCRequest(id: "1", method: "ping"),
                to: server
            )
        }
    }

    @Test("HTTP transport redacts configured authorization from error bodies")
    func httpTransportRedactsConfiguredAuthorizationFromErrorBodies() async throws {
        let transport = MCPHTTPTransport(
            httpTransport: RecordingMCPHTTPTransport { _ in
                AgentHTTPResponse(
                    statusCode: 500,
                    data: Data("authorization=Bearer local-oauth-token token=local-oauth-token".utf8)
                )
            },
            authorizationResolver: MCPAuthorizationResolver(environment: [
                "MCP_DOCS_TOKEN": "local-oauth-token",
            ])
        )
        let server = MCPServer(
            id: "docs",
            authorization: .bearerToken(environmentKey: "MCP_DOCS_TOKEN"),
            transport: .http(url: URL(string: "http://127.0.0.1:8765/mcp")!)
        )

        do {
            _ = try await transport.send(
                MCPJSONRPCRequest(id: "1", method: "ping"),
                to: server
            )
            Issue.record("Expected MCP HTTP error")
        } catch {
            #expect(error.localizedDescription.contains("local-oauth-token") == false)
            #expect(error.localizedDescription.contains("[redacted]"))
        }
    }

    @Test("stdio sandbox keeps a minimal inherited environment and explicit secret opt-ins only")
    func stdioSandboxKeepsMinimalInheritedEnvironmentAndExplicitSecretOptInsOnly() throws {
        let policy = MCPStdioSandboxPolicy(inheritedEnvironment: [
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/dev",
            "TMPDIR": "/var/folders/tmp",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "GITHUB_TOKEN": "ghp_local_secret",
            "AWS_SECRET_ACCESS_KEY": "aws-secret",
            "PROJECT_API_PASSWORD": "password",
        ])

        let environment = try policy.resolvedEnvironment(overrides: [
            "GITHUB_TOKEN": "${GITHUB_TOKEN}",
            "SAFE_MODE": "1",
        ])
        let pathComponents = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        #expect(pathComponents.contains("/opt/homebrew/bin"))
        #expect(pathComponents.contains("/usr/local/bin"))
        #expect(pathComponents.contains("/usr/bin"))
        #expect(pathComponents.contains("/bin"))
        #expect(environment["HOME"] == "/Users/dev")
        #expect(environment["TMPDIR"] == "/var/folders/tmp")
        #expect(environment["LANG"] == "en_US.UTF-8")
        #expect(environment["LC_ALL"] == "en_US.UTF-8")
        #expect(environment["GITHUB_TOKEN"] == "ghp_local_secret")
        #expect(environment["SAFE_MODE"] == "1")
        #expect(environment["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(environment["PROJECT_API_PASSWORD"] == nil)
    }

    @Test("stdio transport sends newline JSON and reconnects after process exit")
    func stdioTransportSendsNewlineJSONAndReconnectsAfterProcessExit() async throws {
        let launcher = ScriptedMCPStdioProcessLauncher(processes: [
            ScriptedMCPStdioProcess(responseLines: [
                #"{"id":"1","jsonrpc":"2.0","result":{"server":"first"}}"#,
            ]),
            ScriptedMCPStdioProcess(responseLines: [
                #"{"id":"2","jsonrpc":"2.0","result":{"server":"second"}}"#,
            ]),
        ])
        let transport = MCPStdioTransport(processLauncher: launcher)
        let server = MCPServer(
            id: "local",
            transport: .stdio(command: "mcp-server", arguments: ["--stdio"])
        )

        let first = try await transport.send(MCPJSONRPCRequest(id: "1", method: "tools/list"), to: server)
        let second = try await transport.send(MCPJSONRPCRequest(id: "2", method: "tools/list"), to: server)
        let processes = launcher.launchedProcesses
        let sentLines = processes.flatMap(\.sentPayloads).map { data in
            String(data: data, encoding: .utf8) ?? ""
        }
        let decodedRequests = try sentLines.map { line in
            try JSONDecoder().decode(MCPJSONRPCRequest.self, from: Data(line.dropLast().utf8))
        }

        #expect(first.result == .object(["server": .string("first")]))
        #expect(second.result == .object(["server": .string("second")]))
        #expect(processes.count == 2)
        #expect(sentLines.allSatisfy { line in
            line.hasSuffix("\n") && !line.dropLast().contains("\n")
        })
        #expect(decodedRequests.map(\.method) == ["tools/list", "tools/list"])
    }

    @Test("stdio transport reconnects when write sees broken pipe before process state updates")
    func stdioTransportReconnectsAfterBrokenPipeWrite() async throws {
        let launcher = ScriptedMCPStdioProcessLauncher(processes: [
            ScriptedMCPStdioProcess(
                responseLines: [],
                writeError: Self.brokenPipeWriteError(),
                runningAfterWriteError: true
            ),
            ScriptedMCPStdioProcess(responseLines: [
                #"{"id":"2","jsonrpc":"2.0","result":{"server":"second"}}"#,
            ]),
        ])
        let transport = MCPStdioTransport(processLauncher: launcher)
        let server = MCPServer(
            id: "local",
            transport: .stdio(command: "mcp-server", arguments: ["--stdio"])
        )

        do {
            _ = try await transport.send(MCPJSONRPCRequest(id: "1", method: "tools/list"), to: server)
            Issue.record("Expected the first write to fail with broken pipe")
        } catch {
            let nsError = error as NSError
            let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            #expect(underlying?.code == Int(EPIPE))
        }

        let second = try await transport.send(MCPJSONRPCRequest(id: "2", method: "tools/list"), to: server)

        #expect(second.result == .object(["server": .string("second")]))
        #expect(launcher.launchedProcesses.count == 2)
    }

    @Test("stdio transport skips notifications until the matching response")
    func stdioTransportSkipsNotificationsUntilMatchingResponse() async throws {
        let launcher = ScriptedMCPStdioProcessLauncher(processes: [
            ScriptedMCPStdioProcess(responseLines: [
                #"{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info"}}"#,
                #"{"id":"1","jsonrpc":"2.0","result":{"ok":true}}"#,
            ]),
        ])
        let transport = MCPStdioTransport(processLauncher: launcher)
        let server = MCPServer(
            id: "local",
            transport: .stdio(command: "mcp-server")
        )

        let response = try await transport.send(MCPJSONRPCRequest(id: "1", method: "tools/list"), to: server)

        #expect(response.result == .object(["ok": .bool(true)]))
    }

    @Test("stdio transport executes a real external MCP server process")
    func stdioTransportExecutesRealExternalMCPServerProcess() async throws {
        let pythonURL = try #require(Self.python3URL())
        let root = temporaryDirectory(named: "mcp-real-process")
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("server.py")
        try writeMCPServerScript(to: scriptURL)

        let transport = MCPStdioTransport()
        do {
            let server = MCPServer(
                id: "local",
                displayName: "Local",
                transport: .stdio(command: pythonURL.path, arguments: [scriptURL.path])
            )
            let manager = await MCPManager(clients: [MCPClient(server: server, transport: transport)])

            let descriptors = try await manager.listToolDescriptors()
            let result = try await manager.executeTool(
                agentToolID: "mcp__local__echo",
                arguments: ["message": .string("hello")]
            )

            #expect(descriptors.map(\.id) == ["mcp__local__echo"])
            #expect(result == .object([
                "isError": .bool(false),
                "content": .array([.string("echo:hello")]),
            ]))
            await transport.shutdownAll()
        } catch {
            await transport.shutdownAll()
            throw error
        }
    }

    @Test("stdio transport reconnects after a real MCP server process exits")
    func stdioTransportReconnectsAfterRealMCPServerProcessExits() async throws {
        let pythonURL = try #require(Self.python3URL())
        let root = temporaryDirectory(named: "mcp-real-reconnect")
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("server.py")
        let markerURL = root.appendingPathComponent("crashed-once")
        try writeMCPServerScript(to: scriptURL)

        let transport = MCPStdioTransport()
        do {
            let server = MCPServer(
                id: "local",
                displayName: "Local",
                transport: .stdio(command: pythonURL.path, arguments: [scriptURL.path, markerURL.path])
            )
            let manager = await MCPManager(clients: [MCPClient(server: server, transport: transport)])

            do {
                _ = try await manager.listToolDescriptors()
                Issue.record("Expected first MCP process to exit before responding")
            } catch {
                #expect(FileManager.default.fileExists(atPath: markerURL.path))
            }

            let descriptors = try await manager.listToolDescriptors()
            let result = try await manager.executeTool(
                agentToolID: "mcp__local__echo",
                arguments: ["message": .string("reconnected")]
            )

            #expect(descriptors.map(\.id) == ["mcp__local__echo"])
            #expect(result == .object([
                "isError": .bool(false),
                "content": .array([.string("echo:reconnected")]),
            ]))
            await transport.shutdownAll()
        } catch {
            await transport.shutdownAll()
            throw error
        }
    }

    @Test("configured manager loads enabled MCP servers from the user config")
    func configuredManagerLoadsEnabledMCPServersFromUserConfig() async throws {
        let root = temporaryDirectory(named: "mcp-configured-manager")
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("mcp.json")
        try """
        {
          "mcpServers": {
            "github": {
              "command": "github-mcp-server",
              "args": ["stdio"]
            },
            "disabled_docs": {
              "url": "http://127.0.0.1:8765/mcp",
              "enabled": false
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let stdioTransport = RecordingMCPTransport { request in
            switch request.method {
            case "tools/list":
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "tools": .array([
                            .object([
                                "name": .string("list_prs"),
                                "description": .string("List pull requests"),
                                "inputSchema": .object(["type": .string("object")]),
                            ]),
                        ]),
                    ])
                )
            case "tools/call":
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
        let manager = MCPConfiguredManager(
            configURL: configURL,
            transportFactory: MCPClientTransportFactory(stdioTransport: stdioTransport)
        )

        let descriptors = try await manager.listToolDescriptors()
        let result = try await manager.executeTool(
            agentToolID: "mcp__github__list_prs",
            arguments: [:]
        )
        let requests = await stdioTransport.requests

        #expect(descriptors.map(\.id) == ["mcp__github__list_prs"])
        #expect(result == .object([
            "isError": .bool(false),
            "content": .array([.string("PR #1")]),
        ]))
        #expect(requests.map(\.method) == ["tools/list", "tools/list", "tools/call"])
    }

    @Test("configured manager routes five real stdio MCP servers")
    func configuredManagerRoutesFiveRealStdioMCPServers() async throws {
        let pythonURL = try #require(Self.python3URL())
        let root = temporaryDirectory(named: "mcp-five-real-servers")
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("server.py")
        let configURL = root.appendingPathComponent("mcp.json")
        try writeMCPServerScript(to: scriptURL)
        let serverIDs = ["docs", "filesystem", "issues", "memory", "repo"]
        let serverEntries = serverIDs.map { id in
            """
                "\(id)": {
                  "command": "\(pythonURL.path)",
                  "args": ["\(scriptURL.path)"]
                }
            """
        }.joined(separator: ",\n")
        try """
        {
          "mcpServers": {
        \(serverEntries)
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let transport = MCPStdioTransport()
        do {
            let manager = MCPConfiguredManager(
                configURL: configURL,
                transportFactory: MCPClientTransportFactory(stdioTransport: transport)
            )
            let descriptors = try await manager.listToolDescriptors()
            let expectedToolIDs = serverIDs.map { "mcp__\($0)__echo" }

            #expect(descriptors.map(\.id) == expectedToolIDs)

            for toolID in expectedToolIDs {
                let result = try await manager.executeTool(
                    agentToolID: toolID,
                    arguments: ["message": .string(toolID)]
                )
                #expect(result == .object([
                    "isError": .bool(false),
                    "content": .array([.string("echo:\(toolID)")]),
                ]))
            }
            await transport.shutdownAll()
        } catch {
            await transport.shutdownAll()
            throw error
        }
    }

    private static func python3URL() -> URL? {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func brokenPipeWriteError() -> NSError {
        NSError(
            domain: NSCocoaErrorDomain,
            code: 512,
            userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPIPE))
            ]
        )
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

private actor RecordingMCPHTTPTransport: AgentHTTPTransport {
    private let handler: @Sendable (AgentHTTPRequest) async throws -> AgentHTTPResponse

    init(handler: @escaping @Sendable (AgentHTTPRequest) async throws -> AgentHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        try await handler(request)
    }
}

private final class ScriptedMCPStdioProcessLauncher: MCPStdioProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingProcesses: [ScriptedMCPStdioProcess]
    private var launchedStorage: [ScriptedMCPStdioProcess] = []

    var launchedProcesses: [ScriptedMCPStdioProcess] {
        lock.lock()
        defer { lock.unlock() }
        return launchedStorage
    }

    init(processes: [ScriptedMCPStdioProcess]) {
        self.pendingProcesses = processes
    }

    func launch(server: MCPServer) throws -> any MCPStdioProcess {
        _ = server
        lock.lock()
        defer { lock.unlock() }
        guard !pendingProcesses.isEmpty else {
            throw MCPStdioTransportError.processUnavailable(serverID: server.id)
        }
        let process = pendingProcesses.removeFirst()
        launchedStorage.append(process)
        return process
    }
}

private final class ScriptedMCPStdioProcess: MCPStdioProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var responseLines: [String]
    private let writeError: Error?
    private let runningAfterWriteError: Bool
    private var runningStorage = true
    private var sentPayloadStorage: [Data] = []

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningStorage
    }

    var sentPayloads: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return sentPayloadStorage
    }

    init(
        responseLines: [String],
        writeError: Error? = nil,
        runningAfterWriteError: Bool = false
    ) {
        self.responseLines = responseLines
        self.writeError = writeError
        self.runningAfterWriteError = runningAfterWriteError
    }

    func write(_ data: Data) throws {
        lock.lock()
        sentPayloadStorage.append(data)
        if writeError != nil {
            runningStorage = runningAfterWriteError
        }
        lock.unlock()
        if let writeError {
            throw writeError
        }
    }

    func readLine() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !responseLines.isEmpty else {
            runningStorage = false
            throw MCPStdioTransportError.processExited(serverID: "test")
        }
        let line = responseLines.removeFirst()
        if responseLines.isEmpty {
            runningStorage = false
        }
        return line
    }

    func terminate() {
        lock.lock()
        runningStorage = false
        lock.unlock()
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

private func writeMCPServerScript(to url: URL) throws {
    try """
    import json
    import os
    import sys

    marker = sys.argv[1] if len(sys.argv) > 1 else ""
    if marker and not os.path.exists(marker):
        with open(marker, "w", encoding="utf-8") as handle:
            handle.write("crashed")
        sys.stdin.readline()
        sys.exit(17)

    def send(request, result=None, error=None):
        response = {"jsonrpc": "2.0", "id": request.get("id")}
        if error is not None:
            response["error"] = error
        else:
            response["result"] = result if result is not None else {}
        print(json.dumps(response), flush=True)

    for line in sys.stdin:
        request = json.loads(line)
        method = request.get("method")
        if method == "tools/list":
            send(request, {
                "tools": [{
                    "name": "echo",
                    "description": "Echo a message",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "message": {
                                "type": "string",
                                "description": "Message to echo"
                            }
                        },
                        "required": ["message"]
                    }
                }]
            })
        elif method == "tools/call":
            params = request.get("params") or {}
            arguments = params.get("arguments") or {}
            message = arguments.get("message") or ""
            send(request, {
                "content": [{
                    "type": "text",
                    "text": "echo:" + str(message)
                }],
                "isError": False
            })
        else:
            send(request, {})
    """.write(to: url, atomically: true, encoding: .utf8)
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
