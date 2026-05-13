// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserMCPTool.swift - Built-in MCP-compatible browser automation tools.

import Foundation

struct BrowserMCPCommand: Sendable, Equatable {
    let socketCommand: CLICommandName
    let params: [String: String]

    init(socketCommand: CLICommandName, params: [String: String] = [:]) {
        self.socketCommand = socketCommand
        self.params = params
    }
}

protocol BrowserMCPCommandExecuting: Sendable {
    func executeBrowserCommand(_ command: BrowserMCPCommand) async throws -> [String: String]
}

struct ClosureBrowserMCPCommandExecutor: BrowserMCPCommandExecuting {
    private let operation: @Sendable (BrowserMCPCommand) async throws -> [String: String]

    init(_ operation: @escaping @Sendable (BrowserMCPCommand) async throws -> [String: String]) {
        self.operation = operation
    }

    func executeBrowserCommand(_ command: BrowserMCPCommand) async throws -> [String: String] {
        try await operation(command)
    }
}

struct BrowserMCPToolProvider: Sendable {
    static let serverID = "cocxy-browser"
    static let tools: [MCPTool] = [
        MCPTool(
            name: "browser_snapshot",
            description: "Capture the current browser accessibility snapshot with stable element refs.",
            inputSchema: MCPToolInputSchema()
        ),
        MCPTool(
            name: "browser_click",
            description: "Click a browser element by snapshot ref.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "ref": MCPToolInputProperty(type: "string", description: "Stable element ref from browser_snapshot."),
                ],
                required: ["ref"]
            )
        ),
        MCPTool(
            name: "browser_fill",
            description: "Fill a browser input element by snapshot ref.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "ref": MCPToolInputProperty(type: "string", description: "Stable input ref from browser_snapshot."),
                    "text": MCPToolInputProperty(type: "string", description: "Text to place in the input."),
                ],
                required: ["ref", "text"]
            )
        ),
        MCPTool(
            name: "browser_eval",
            description: "Evaluate JavaScript in the active embedded browser tab.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "script": MCPToolInputProperty(type: "string", description: "JavaScript source, up to 10000 characters."),
                ],
                required: ["script"]
            )
        ),
        MCPTool(
            name: "browser_screenshot",
            description: "Capture a PNG screenshot of the active embedded browser tab.",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "output": MCPToolInputProperty(type: "string", description: "Optional local output path for the PNG."),
                ]
            )
        ),
    ]

    private static let maxEvalScriptLength = 10_000
    private let executor: any BrowserMCPCommandExecuting

    init(executor: any BrowserMCPCommandExecuting) {
        self.executor = executor
    }

    func callTool(name: String, arguments: [String: AgentJSONValue]) async -> MCPToolCallResult {
        do {
            let command = try Self.command(for: name, arguments: arguments)
            let result = try await executor.executeBrowserCommand(command)
            return MCPToolCallResult(content: [.json(.object(Self.jsonObject(from: result)))])
        } catch {
            return MCPToolCallResult(
                content: [.text(Self.errorMessage(from: error))],
                isError: true
            )
        }
    }

    private static func command(
        for toolName: String,
        arguments: [String: AgentJSONValue]
    ) throws -> BrowserMCPCommand {
        switch toolName {
        case "browser_snapshot":
            return BrowserMCPCommand(socketCommand: .browserSnapshot)
        case "browser_click":
            return BrowserMCPCommand(
                socketCommand: .browserClick,
                params: ["ref": try requiredString("ref", in: arguments)]
            )
        case "browser_fill":
            return BrowserMCPCommand(
                socketCommand: .browserFill,
                params: [
                    "ref": try requiredString("ref", in: arguments),
                    "text": try requiredString("text", in: arguments),
                ]
            )
        case "browser_eval":
            let script = try requiredString("script", in: arguments)
            guard script.count <= maxEvalScriptLength else {
                throw BrowserMCPToolError.invalidArgument(
                    "script",
                    "Script length \(script.count) exceeds maximum \(maxEvalScriptLength) characters"
                )
            }
            return BrowserMCPCommand(socketCommand: .browserEval, params: ["script": script])
        case "browser_screenshot":
            var params: [String: String] = [:]
            if let output = optionalString("output", in: arguments), !output.isEmpty {
                params["output"] = output
            }
            return BrowserMCPCommand(socketCommand: .browserScreenshot, params: params)
        default:
            throw BrowserMCPToolError.unknownTool(toolName)
        }
    }

    private static func requiredString(
        _ name: String,
        in arguments: [String: AgentJSONValue]
    ) throws -> String {
        guard let value = optionalString(name, in: arguments) else {
            throw BrowserMCPToolError.missingArgument(name)
        }
        return value
    }

    private static func optionalString(
        _ name: String,
        in arguments: [String: AgentJSONValue]
    ) -> String? {
        arguments[name]?.stringValue
    }

    private static func jsonObject(from values: [String: String]) -> [String: AgentJSONValue] {
        values.reduce(into: [String: AgentJSONValue]()) { result, entry in
            result[entry.key] = .string(entry.value)
        }
    }

    private static func errorMessage(from error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

actor BrowserMCPToolManager: MCPManaging {
    private let provider: BrowserMCPToolProvider

    init(provider: BrowserMCPToolProvider) {
        self.provider = provider
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        BrowserMCPToolProvider.tools
            .map { MCPToolBridge.descriptor(for: $0, serverID: BrowserMCPToolProvider.serverID) }
            .sorted { $0.id < $1.id }
    }

    func executeTool(
        agentToolID: String,
        arguments: [String: AgentJSONValue]
    ) async throws -> AgentJSONValue {
        let normalizedToolID = AgentToolDescriptor.normalizedID(agentToolID)
        guard let tool = BrowserMCPToolProvider.tools.first(where: {
            MCPToolBridge.descriptor(for: $0, serverID: BrowserMCPToolProvider.serverID).id == normalizedToolID
        }) else {
            throw MCPManagerError.unknownTool(agentToolID)
        }

        let result = await provider.callTool(name: tool.name, arguments: arguments)
        return MCPToolBridge.agentJSONValue(from: result)
    }
}

enum BrowserMCPToolError: Error, Sendable, Equatable {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
}

extension BrowserMCPToolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknownTool(let tool):
            return "Unknown browser MCP tool: \(tool)"
        case .missingArgument(let argument):
            return "Missing required argument: \(argument)"
        case .invalidArgument(_, let message):
            return message
        }
    }
}

enum BrowserMCPCommandExecutionError: Error, Sendable, Equatable {
    case failed(String)
}

extension BrowserMCPCommandExecutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
