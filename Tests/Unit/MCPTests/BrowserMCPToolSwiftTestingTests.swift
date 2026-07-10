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

        #expect(names == expectedBrowserMCPToolNames)
        #expect(Set(names).count == names.count)
        #expect(tools.allSatisfy { $0.inputSchema.additionalProperties == false })
        #expect(try #require(tools.first { $0.name == "browser_navigate" }).inputSchema.required == ["url"])
        #expect(try #require(tools.first { $0.name == "browser_context" }).inputSchema.required == [])
        #expect(try #require(tools.first { $0.name == "browser_context" })
            .inputSchema.properties["around"]?.type == "number")
        #expect(try #require(tools.first { $0.name == "browser_snapshot" }).inputSchema.required == [])
        #expect(try #require(tools.first { $0.name == "browser_click" }).inputSchema.required == ["ref"])
        #expect(try #require(tools.first { $0.name == "browser_click" })
            .inputSchema.properties["timeout"]?.type == "number")
        #expect(try #require(tools.first { $0.name == "browser_fill" }).inputSchema.required == ["ref", "text"])
        #expect(try #require(tools.first { $0.name == "browser_upload" }).inputSchema.required == ["ref", "path"])
        #expect(try #require(tools.first { $0.name == "browser_scroll" }).inputSchema.required == ["x", "y"])
        #expect(try #require(tools.first { $0.name == "browser_scroll" })
            .inputSchema.properties["x"]?.type == "number")
        #expect(try #require(tools.first { $0.name == "browser_eval" }).inputSchema.required == ["script"])
        #expect(try #require(tools.first { $0.name == "browser_cookies_set" }).inputSchema.required == ["name", "value"])
        #expect(try #require(tools.first { $0.name == "browser_cookies_set" })
            .inputSchema.properties["secure"]?.type == "boolean")
        #expect(try #require(tools.first { $0.name == "browser_cookies_set" })
            .inputSchema.properties["max-age"]?.type == "number")
        #expect(try #require(tools.first { $0.name == "browser_storage_set" }).inputSchema.required == ["key", "value"])
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
        let navigate = await provider.callTool(name: "browser_navigate", arguments: [
            "url": .string("https://cocxy.dev"),
        ])
        let context = await provider.callTool(name: "browser_context", arguments: [
            "target": .string("card-1"),
            "around": .number(2),
            "console": .number(5),
            "network": .number(8),
        ])
        let click = await provider.callTool(name: "browser_click", arguments: ["ref": .string("button-1")])
        let doubleClick = await provider.callTool(name: "browser_dblclick", arguments: [
            "ref": .string("button-1"),
            "timeout": .number(2_000),
        ])
        let fill = await provider.callTool(name: "browser_fill", arguments: [
            "ref": .string("input-1"),
            "text": .string("hello"),
        ])
        let upload = await provider.callTool(name: "browser_upload", arguments: [
            "ref": .string("file-1"),
            "path": .string("/tmp/cocxy-upload.txt"),
        ])
        let type = await provider.callTool(name: "browser_type", arguments: [
            "ref": .string("input-1"),
            "text": .string(" world"),
            "timeout": .number(750),
        ])
        let scroll = await provider.callTool(name: "browser_scroll", arguments: [
            "x": .number(12),
            "y": .number(-24),
        ])
        let findNth = await provider.callTool(name: "browser_find_nth", arguments: [
            "index": .number(1),
            "selector": .string(".row"),
        ])
        let eval = await provider.callTool(name: "browser_eval", arguments: ["script": .string("document.title")])
        let cookie = await provider.callTool(name: "browser_cookies_set", arguments: [
            "name": .string("sid"),
            "value": .string("abc"),
            "secure": .bool(true),
            "max-age": .number(60),
        ])
        let storage = await provider.callTool(name: "browser_storage_set", arguments: [
            "area": .string("session"),
            "key": .string("draft"),
            "value": .string("hello"),
        ])
        let screenshot = await provider.callTool(name: "browser_screenshot", arguments: [
            "output": .string("/tmp/cocxy-browser.png"),
        ])
        let commands = await executor.commands

        #expect(snapshot.isError == false)
        #expect(navigate.isError == false)
        #expect(context.isError == false)
        #expect(click.content == [.json(.object(["status": .string("ok"), "result": .string("done")]))])
        #expect(doubleClick.isError == false)
        #expect(fill.isError == false)
        #expect(upload.isError == false)
        #expect(type.isError == false)
        #expect(scroll.isError == false)
        #expect(findNth.isError == false)
        #expect(eval.isError == false)
        #expect(cookie.isError == false)
        #expect(storage.isError == false)
        #expect(screenshot.isError == false)
        #expect(commands == [
            BrowserMCPCommand(socketCommand: .browserSnapshot, params: [:]),
            BrowserMCPCommand(socketCommand: .browserNavigate, params: ["url": "https://cocxy.dev"]),
            BrowserMCPCommand(socketCommand: .browserContext, params: [
                "target": "card-1",
                "around": "2",
                "console": "5",
                "network": "8",
            ]),
            BrowserMCPCommand(socketCommand: .browserClick, params: ["ref": "button-1"]),
            BrowserMCPCommand(socketCommand: .browserDblClick, params: [
                "ref": "button-1",
                "timeout": "2000",
            ]),
            BrowserMCPCommand(socketCommand: .browserFill, params: ["ref": "input-1", "text": "hello"]),
            BrowserMCPCommand(socketCommand: .browserUpload, params: [
                "path": "/tmp/cocxy-upload.txt",
                "ref": "file-1",
            ]),
            BrowserMCPCommand(socketCommand: .browserType, params: [
                "ref": "input-1",
                "text": " world",
                "timeout": "750",
            ]),
            BrowserMCPCommand(socketCommand: .browserScroll, params: ["x": "12", "y": "-24"]),
            BrowserMCPCommand(socketCommand: .browserFindNth, params: ["index": "1", "selector": ".row"]),
            BrowserMCPCommand(socketCommand: .browserEval, params: ["script": "document.title"]),
            BrowserMCPCommand(socketCommand: .browserCookiesSet, params: [
                "name": "sid",
                "value": "abc",
                "secure": "true",
                "max-age": "60",
            ]),
            BrowserMCPCommand(socketCommand: .browserStorageSet, params: [
                "area": "session",
                "key": "draft",
                "value": "hello",
            ]),
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

    @Test("browser MCP rejects oversized script and style payloads")
    func rejectsOversizedScriptAndStylePayloads() async throws {
        let provider = BrowserMCPToolProvider(executor: RecordingBrowserMCPCommandExecutor(response: [:]))
        let longPayload = String(repeating: "x", count: 10_001)

        let script = await provider.callTool(name: "browser_eval", arguments: ["script": .string(longPayload)])
        let style = await provider.callTool(name: "browser_add_style", arguments: ["css": .string(longPayload)])

        #expect(script.isError == true)
        #expect(style.isError == true)
        #expect(script.content == [
            .text("browser_eval script length 10001 exceeds maximum 10000 characters"),
        ])
        #expect(style.content == [
            .text("browser_add_style css length 10001 exceeds maximum 10000 characters"),
        ])
    }

    @Test("browser MCP rejects non-finite fractional and unrepresentable numbers without executing")
    func rejectsUnsafeNumbersWithoutExecuting() async {
        let executor = RecordingBrowserMCPCommandExecutor(response: [:])
        let provider = BrowserMCPToolProvider(executor: executor)
        let invalidNumbers = [
            Double.nan,
            Double.infinity,
            -Double.infinity,
            1e300,
            -1e300,
            1.5,
        ]

        for number in invalidNumbers {
            let result = await provider.callTool(name: "browser_scroll", arguments: [
                "x": .number(number),
                "y": .number(0),
            ])

            #expect(result.isError == true)
            #expect(result.content == [
                .text("browser_scroll x must be a finite, representable integer"),
            ])
        }
        #expect(await executor.commands.isEmpty)
    }

    @Test("browser MCP enforces numeric domains before executing socket commands")
    func enforcesNumericDomainsBeforeExecuting() async {
        let executor = RecordingBrowserMCPCommandExecutor(response: [:])
        let provider = BrowserMCPToolProvider(executor: executor)

        let results = [
            await provider.callTool(name: "browser_context", arguments: ["around": .number(21)]),
            await provider.callTool(name: "browser_click", arguments: [
                "ref": .string("button-1"),
                "timeout": .number(99),
            ]),
            await provider.callTool(name: "browser_wait", arguments: [
                "selector": .string(".ready"),
                "timeout": .number(30_001),
            ]),
            await provider.callTool(name: "browser_scroll", arguments: [
                "x": .number(100_001),
                "y": .number(0),
            ]),
            await provider.callTool(name: "browser_find_nth", arguments: [
                "index": .number(-1),
                "selector": .string(".row"),
            ]),
            await provider.callTool(name: "browser_cookies_set", arguments: [
                "name": .string("sid"),
                "value": .string("abc"),
                "max-age": .number(-1),
            ]),
            await provider.callTool(name: "browser_network", arguments: ["tail": .number(0)]),
        ]

        #expect(results.allSatisfy { $0.isError })
        #expect(await executor.commands.isEmpty)
    }

    @Test("browser MCP accepts established numeric domain boundaries")
    func acceptsEstablishedNumericDomainBoundaries() async {
        let executor = RecordingBrowserMCPCommandExecutor(response: [:])
        let provider = BrowserMCPToolProvider(executor: executor)

        let results = [
            await provider.callTool(name: "browser_context", arguments: [
                "around": .number(20),
                "console": .number(100),
                "network": .number(100),
            ]),
            await provider.callTool(name: "browser_click", arguments: [
                "ref": .string("button-1"),
                "timeout": .number(60_000),
            ]),
            await provider.callTool(name: "browser_wait", arguments: [
                "selector": .string(".ready"),
                "timeout": .number(30_000),
            ]),
            await provider.callTool(name: "browser_scroll", arguments: [
                "x": .number(-100_000),
                "y": .number(100_000),
            ]),
            await provider.callTool(name: "browser_find_nth", arguments: [
                "index": .number(0),
                "selector": .string(".row"),
            ]),
            await provider.callTool(name: "browser_cookies_set", arguments: [
                "name": .string("sid"),
                "value": .string("abc"),
                "max-age": .number(0),
            ]),
            await provider.callTool(name: "browser_network", arguments: ["tail": .number(1)]),
        ]

        #expect(results.allSatisfy { !$0.isError })
        #expect(await executor.commands.count == results.count)
    }

    @Test("browser MCP handles exact Int64 boundaries without trapping")
    func handlesInt64BoundariesWithoutTrapping() async {
        let executor = RecordingBrowserMCPCommandExecutor(response: [:])
        let provider = BrowserMCPToolProvider(executor: executor)
        let largestRepresentableInt64Double = Double(Int64.max).nextDown

        let accepted = await provider.callTool(name: "browser_find_nth", arguments: [
            "index": .number(largestRepresentableInt64Double),
            "selector": .string(".row"),
        ])
        let rejected = await provider.callTool(name: "browser_find_nth", arguments: [
            "index": .number(Double(Int64.max)),
            "selector": .string(".row"),
        ])

        #expect(accepted.isError == false)
        #expect(rejected.isError == true)
        #expect(await executor.commands.count == 1)
    }

    @Test("browser MCP preserves fractional scalar formatting for text fields")
    func preservesFractionalTextScalarFormatting() async throws {
        let executor = RecordingBrowserMCPCommandExecutor(response: [:])
        let provider = BrowserMCPToolProvider(executor: executor)

        let result = await provider.callTool(name: "browser_fill", arguments: [
            "ref": .string("input-1"),
            "text": .number(1.5),
        ])
        let command = try #require(await executor.commands.first)

        #expect(result.isError == false)
        #expect(command.params["text"] == "1.5")
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

        let descriptorIDs = descriptors.map(\.id)
        #expect(descriptorIDs.count == expectedBrowserMCPToolNames.count)
        #expect(descriptorIDs.contains("mcp__cocxy_browser__browser_navigate"))
        #expect(descriptorIDs.contains("mcp__cocxy_browser__browser_click"))
        #expect(descriptorIDs.contains("mcp__cocxy_browser__browser_eval"))
        #expect(descriptorIDs.contains("mcp__cocxy_browser__browser_storage_set"))
        #expect(descriptorIDs.contains("mcp__cocxy_browser__browser_screenshot"))
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

private let expectedBrowserMCPToolNames = [
    "browser_navigate",
    "browser_back",
    "browser_forward",
    "browser_reload",
    "browser_get_state",
    "browser_state_save",
    "browser_state_load",
    "browser_eval",
    "browser_add_script",
    "browser_add_style",
    "browser_init_script_add",
    "browser_init_scripts_list",
    "browser_dialogs",
    "browser_dialog_accept",
    "browser_dialog_dismiss",
    "browser_get_text",
    "browser_list_tabs",
    "browser_snapshot",
    "browser_context",
    "browser_click",
    "browser_dblclick",
    "browser_hover",
    "browser_focus",
    "browser_fill",
    "browser_upload",
    "browser_type",
    "browser_press",
    "browser_keydown",
    "browser_keyup",
    "browser_check",
    "browser_uncheck",
    "browser_select",
    "browser_scroll",
    "browser_scroll_into_view",
    "browser_get_html",
    "browser_get_value",
    "browser_get_attr",
    "browser_get_title",
    "browser_get_count",
    "browser_get_box",
    "browser_get_styles",
    "browser_is_visible",
    "browser_is_enabled",
    "browser_is_checked",
    "browser_find_role",
    "browser_find_text",
    "browser_find_label",
    "browser_find_placeholder",
    "browser_find_alt",
    "browser_find_title",
    "browser_find_testid",
    "browser_find_first",
    "browser_find_last",
    "browser_find_nth",
    "browser_screenshot",
    "browser_console",
    "browser_wait",
    "browser_cookies_list",
    "browser_cookies_set",
    "browser_cookies_delete",
    "browser_network",
    "browser_frames",
    "browser_downloads",
    "browser_storage_list",
    "browser_storage_get",
    "browser_storage_set",
    "browser_storage_delete",
]

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
