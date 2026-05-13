// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserMCPToolSwiftTestingTests.swift - Browser MCP tool contracts.

import Testing
@testable import CocxyTerminal

@Suite("Browser MCP tool")
struct BrowserMCPToolSwiftTestingTests {

    @Test("browser MCP exposes scriptable browser tools with stable schemas")
    func exposesScriptableBrowserToolsWithStableSchemas() throws {
        let tools = BrowserMCPToolProvider.tools
        let names = tools.map(\.name)

        #expect(names == [
            "browser_snapshot",
            "browser_click",
            "browser_fill",
            "browser_eval",
            "browser_screenshot",
        ])
        #expect(try #require(tools.first { $0.name == "browser_snapshot" }).inputSchema.required == [])
        #expect(try #require(tools.first { $0.name == "browser_click" }).inputSchema.required == ["ref"])
        #expect(try #require(tools.first { $0.name == "browser_fill" }).inputSchema.required == ["ref", "text"])
        #expect(try #require(tools.first { $0.name == "browser_eval" }).inputSchema.required == ["script"])
        #expect(try #require(tools.first { $0.name == "browser_screenshot" }).inputSchema.required == [])
        #expect(try #require(tools.first { $0.name == "browser_screenshot" })
            .inputSchema.properties["output"]?.type == "string")
    }

    @Test("browser MCP routes tool calls to local browser socket commands")
    func routesToolCallsToLocalBrowserSocketCommands() async throws {
        let executor = RecordingBrowserMCPCommandExecutor(response: [
            "status": "ok",
            "result": "done",
        ])
        let provider = BrowserMCPToolProvider(executor: executor)

        let snapshot = await provider.callTool(name: "browser_snapshot", arguments: [:])
        let click = await provider.callTool(name: "browser_click", arguments: ["ref": .string("button-1")])
        let fill = await provider.callTool(name: "browser_fill", arguments: [
            "ref": .string("input-1"),
            "text": .string("hello"),
        ])
        let eval = await provider.callTool(name: "browser_eval", arguments: ["script": .string("document.title")])
        let screenshot = await provider.callTool(name: "browser_screenshot", arguments: [
            "output": .string("/tmp/cocxy-browser.png"),
        ])
        let commands = await executor.commands

        #expect(snapshot.isError == false)
        #expect(click.content == [.json(.object(["status": .string("ok"), "result": .string("done")]))])
        #expect(fill.isError == false)
        #expect(eval.isError == false)
        #expect(screenshot.isError == false)
        #expect(commands == [
            BrowserMCPCommand(socketCommand: .browserSnapshot, params: [:]),
            BrowserMCPCommand(socketCommand: .browserClick, params: ["ref": "button-1"]),
            BrowserMCPCommand(socketCommand: .browserFill, params: ["ref": "input-1", "text": "hello"]),
            BrowserMCPCommand(socketCommand: .browserEval, params: ["script": "document.title"]),
            BrowserMCPCommand(socketCommand: .browserScreenshot, params: ["output": "/tmp/cocxy-browser.png"]),
        ])
    }

    @Test("browser MCP returns MCP errors for missing required arguments")
    func returnsMCPErrorsForMissingRequiredArguments() async throws {
        let provider = BrowserMCPToolProvider(executor: RecordingBrowserMCPCommandExecutor(response: [:]))

        let result = await provider.callTool(name: "browser_fill", arguments: ["ref": .string("input-1")])

        #expect(result.isError == true)
        #expect(result.content == [.text("Missing required argument: text")])
    }

    @Test("browser MCP tools bridge to external Agent descriptors")
    func toolsBridgeToExternalAgentDescriptors() throws {
        let descriptor = MCPToolBridge.descriptor(
            for: try #require(BrowserMCPToolProvider.tools.first { $0.name == "browser_snapshot" }),
            serverID: BrowserMCPToolProvider.serverID
        )

        #expect(descriptor.id == "mcp__cocxy_browser__browser_snapshot")
        #expect(descriptor.capability == .external)
        #expect(MCPToolBridge.parseToolID(descriptor.id) == MCPToolRoute(
            serverID: "cocxy_browser",
            toolName: "browser_snapshot"
        ))
    }

    @Test("browser MCP manager advertises and executes tools through Agent MCP IDs")
    func managerAdvertisesAndExecutesToolsThroughAgentMCPIDs() async throws {
        let manager = BrowserMCPToolManager(provider: BrowserMCPToolProvider(
            executor: RecordingBrowserMCPCommandExecutor(response: ["status": "clicked"])
        ))

        let descriptors = try await manager.listToolDescriptors()
        let result = try await manager.executeTool(
            agentToolID: "mcp__cocxy_browser__browser_click",
            arguments: ["ref": .string("button-1")]
        )

        #expect(descriptors.map(\.id) == [
            "mcp__cocxy_browser__browser_click",
            "mcp__cocxy_browser__browser_eval",
            "mcp__cocxy_browser__browser_fill",
            "mcp__cocxy_browser__browser_screenshot",
            "mcp__cocxy_browser__browser_snapshot",
        ])
        #expect(result == .object([
            "isError": .bool(false),
            "content": .array([
                .object(["status": .string("clicked")]),
            ]),
        ]))
    }

    @Test("composite MCP manager merges built-in browser and configured tools")
    func compositeManagerMergesBuiltInBrowserAndConfiguredTools() async throws {
        let browserManager = BrowserMCPToolManager(provider: BrowserMCPToolProvider(
            executor: RecordingBrowserMCPCommandExecutor(response: ["status": "captured"])
        ))
        let configuredManager = RecordingMCPManaging(
            descriptors: [
                AgentToolDescriptor(
                    id: "mcp__local_docs__search",
                    displayName: "local-docs: search",
                    description: "Search local docs",
                    capability: .external
                ),
            ],
            result: .object(["source": .string("configured")])
        )
        let manager = MCPCompositeManager(managers: [configuredManager, browserManager])

        let descriptors = try await manager.listToolDescriptors()
        let browserResult = try await manager.executeTool(
            agentToolID: "mcp__cocxy_browser__browser_snapshot",
            arguments: [:]
        )
        let configuredResult = try await manager.executeTool(
            agentToolID: "mcp__local_docs__search",
            arguments: ["query": .string("install")]
        )

        #expect(descriptors.map(\.id).contains("mcp__cocxy_browser__browser_snapshot"))
        #expect(descriptors.map(\.id).contains("mcp__local_docs__search"))
        #expect(browserResult == .object([
            "isError": .bool(false),
            "content": .array([.object(["status": .string("captured")])]),
        ]))
        #expect(configuredResult == .object(["source": .string("configured")]))
        #expect(await configuredManager.calls == [
            RecordingMCPManagingCall(toolID: "mcp__local_docs__search", arguments: ["query": .string("install")]),
        ])
    }
}

private actor RecordingBrowserMCPCommandExecutor: BrowserMCPCommandExecuting {
    private(set) var commands: [BrowserMCPCommand] = []
    private let response: [String: String]

    init(response: [String: String]) {
        self.response = response
    }

    func executeBrowserCommand(_ command: BrowserMCPCommand) async throws -> [String: String] {
        commands.append(command)
        return response
    }
}

private struct RecordingMCPManagingCall: Equatable, Sendable {
    let toolID: String
    let arguments: [String: AgentJSONValue]
}

private actor RecordingMCPManaging: MCPManaging {
    private let descriptors: [AgentToolDescriptor]
    private let result: AgentJSONValue
    private(set) var calls: [RecordingMCPManagingCall] = []

    init(descriptors: [AgentToolDescriptor], result: AgentJSONValue) {
        self.descriptors = descriptors
        self.result = result
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        descriptors
    }

    func executeTool(agentToolID: String, arguments: [String: AgentJSONValue]) async throws -> AgentJSONValue {
        guard descriptors.contains(where: { $0.id == AgentToolDescriptor.normalizedID(agentToolID) }) else {
            throw MCPManagerError.unknownTool(agentToolID)
        }
        calls.append(RecordingMCPManagingCall(toolID: agentToolID, arguments: arguments))
        return result
    }
}
