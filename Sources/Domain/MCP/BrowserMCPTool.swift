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
    static let tools: [MCPTool] = toolSpecs.map(\.tool)

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
        guard let spec = toolSpecs.first(where: { $0.name == toolName }) else {
            throw BrowserMCPToolError.unknownTool(toolName)
        }

        var params: [String: String] = [:]
        for argument in spec.required {
            let value = try requiredScalar(argument.name, in: arguments)
            try validate(argument: argument.name, value: value, toolName: toolName)
            params[argument.name] = value
        }
        for argument in spec.optional {
            guard let value = optionalScalar(argument.name, in: arguments), !value.isEmpty else {
                continue
            }
            try validate(argument: argument.name, value: value, toolName: toolName)
            params[argument.name] = value
        }

        return BrowserMCPCommand(socketCommand: spec.socketCommand, params: params)
    }

    private static func requiredScalar(
        _ name: String,
        in arguments: [String: AgentJSONValue]
    ) throws -> String {
        guard let value = optionalScalar(name, in: arguments) else {
            throw BrowserMCPToolError.missingArgument(name)
        }
        return value
    }

    private static func optionalScalar(
        _ name: String,
        in arguments: [String: AgentJSONValue]
    ) -> String? {
        guard let value = arguments[name] else { return nil }
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            if number.rounded() == number {
                return String(Int64(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null, .array, .object:
            return nil
        }
    }

    private static func validate(argument: String, value: String, toolName: String) throws {
        guard argument == "script" || argument == "css" || argument == "value" else { return }
        guard value.count <= maxEvalScriptLength else {
            throw BrowserMCPToolError.invalidArgument(
                argument,
                "\(toolName) \(argument) length \(value.count) exceeds maximum \(maxEvalScriptLength) characters"
            )
        }
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

    private struct ToolSpec: Sendable, Equatable {
        let name: String
        let socketCommand: CLICommandName
        let description: String
        let required: [Argument]
        let optional: [Argument]

        var tool: MCPTool {
            let allArguments = required + optional
            let properties = allArguments.reduce(into: [String: MCPToolInputProperty]()) { result, argument in
                result[argument.name] = MCPToolInputProperty(
                    type: argument.type.rawValue,
                    description: argument.description
                )
            }
            return MCPTool(
                name: name,
                description: description,
                inputSchema: MCPToolInputSchema(
                    properties: properties,
                    required: required.map(\.name)
                )
            )
        }
    }

    private struct Argument: Sendable, Equatable {
        let name: String
        let type: ArgumentType
        let description: String
    }

    private enum ArgumentType: String, Sendable {
        case string
        case number
        case boolean
    }

    private static func arg(
        _ name: String,
        _ description: String,
        type: ArgumentType = .string
    ) -> Argument {
        Argument(name: name, type: type, description: description)
    }

    private static func spec(
        _ name: String,
        _ socketCommand: CLICommandName,
        _ description: String,
        required: [Argument] = [],
        optional: [Argument] = []
    ) -> ToolSpec {
        ToolSpec(
            name: name,
            socketCommand: socketCommand,
            description: description,
            required: required,
            optional: optional
        )
    }

    private static let refArg = arg("ref", "Stable element ref from browser_snapshot.")
    private static let timeoutArg = arg("timeout", "Optional timeout in milliseconds.", type: .number)

    private static let toolSpecs: [ToolSpec] = [
        spec("browser_navigate", .browserNavigate, "Navigate the embedded browser to a URL.", required: [
            arg("url", "URL to open in the active browser tab.")
        ]),
        spec("browser_back", .browserBack, "Go back in browser history."),
        spec("browser_forward", .browserForward, "Go forward in browser history."),
        spec("browser_reload", .browserReload, "Reload the current page."),
        spec("browser_get_state", .browserGetState, "Get current browser state as JSON."),
        spec("browser_state_save", .browserStateSave, "Save cookies and storage state to a local JSON file.", required: [
            arg("path", "Local JSON file path.")
        ]),
        spec("browser_state_load", .browserStateLoad, "Load cookies and storage state from a local JSON file.", required: [
            arg("path", "Local JSON file path.")
        ]),
        spec("browser_eval", .browserEval, "Evaluate JavaScript in the active embedded browser tab.", required: [
            arg("script", "JavaScript source, up to 10000 characters.")
        ]),
        spec("browser_add_script", .browserAddScript, "Inject and execute an inline script in the active page.", required: [
            arg("script", "JavaScript source, up to 10000 characters.")
        ]),
        spec("browser_add_style", .browserAddStyle, "Inject an inline stylesheet in the active page.", required: [
            arg("css", "CSS source, up to 10000 characters.")
        ]),
        spec("browser_init_script_add", .browserInitScriptAdd, "Register a document-start init script for future page loads.", required: [
            arg("script", "JavaScript source, up to 10000 characters.")
        ]),
        spec("browser_init_scripts_list", .browserInitScriptsList, "List registered document-start init scripts."),
        spec("browser_dialogs", .browserDialogs, "List pending and recently handled JavaScript dialogs."),
        spec("browser_dialog_accept", .browserDialogAccept, "Accept a pending JavaScript dialog.", optional: [
            arg("id", "Optional dialog id."),
            arg("promptText", "Optional prompt text.")
        ]),
        spec("browser_dialog_dismiss", .browserDialogDismiss, "Dismiss a pending JavaScript dialog.", optional: [
            arg("id", "Optional dialog id.")
        ]),
        spec("browser_get_text", .browserGetText, "Get text content from the active page."),
        spec("browser_list_tabs", .browserListTabs, "List open browser tabs."),
        spec("browser_snapshot", .browserSnapshot, "Capture the current browser snapshot with stable element refs."),
        spec("browser_context", .browserContext, "Capture an agent-ready browser context pack.", optional: [
            arg("target", "Optional target ref."),
            arg("around", "Context lines around the target.", type: .number),
            arg("console", "Console tail count.", type: .number),
            arg("network", "Network tail count.", type: .number)
        ]),
        spec("browser_click", .browserClick, "Click a browser element by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_dblclick", .browserDblClick, "Double-click a browser element by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_hover", .browserHover, "Hover a browser element by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_focus", .browserFocus, "Focus a browser element by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_fill", .browserFill, "Fill a browser input element by snapshot ref.", required: [
            refArg,
            arg("text", "Text to place in the input.")
        ], optional: [timeoutArg]),
        spec("browser_upload", .browserUpload, "Upload a local file into a browser file input by snapshot ref.", required: [
            refArg,
            arg("path", "Local file path to upload.")
        ], optional: [timeoutArg]),
        spec("browser_type", .browserType, "Type text into an element or the focused page.", required: [
            arg("text", "Text to type.")
        ], optional: [refArg, timeoutArg]),
        spec("browser_press", .browserPress, "Press a key in the active browser tab.", required: [
            arg("key", "Key name to press.")
        ], optional: [timeoutArg]),
        spec("browser_keydown", .browserKeyDown, "Dispatch keydown in the active browser tab.", required: [
            arg("key", "Key name.")
        ], optional: [timeoutArg]),
        spec("browser_keyup", .browserKeyUp, "Dispatch keyup in the active browser tab.", required: [
            arg("key", "Key name.")
        ], optional: [timeoutArg]),
        spec("browser_check", .browserCheck, "Check a checkbox or radio by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_uncheck", .browserUncheck, "Uncheck a checkbox by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_select", .browserSelect, "Select an option by value, label, or index.", required: [
            refArg,
            arg("value", "Option value, label, or index.")
        ], optional: [timeoutArg]),
        spec("browser_scroll", .browserScroll, "Scroll the active browser page by pixel deltas.", required: [
            arg("x", "Horizontal pixel delta.", type: .number),
            arg("y", "Vertical pixel delta.", type: .number)
        ], optional: [timeoutArg]),
        spec("browser_scroll_into_view", .browserScrollIntoView, "Scroll an element into view by snapshot ref.", required: [refArg], optional: [timeoutArg]),
        spec("browser_get_html", .browserGetHTML, "Get page or element HTML.", optional: [refArg]),
        spec("browser_get_value", .browserGetValue, "Get a form/control value by snapshot ref.", required: [refArg]),
        spec("browser_get_attr", .browserGetAttr, "Get an element attribute by snapshot ref.", required: [
            refArg,
            arg("name", "Attribute name.")
        ]),
        spec("browser_get_title", .browserGetTitle, "Get the active document title."),
        spec("browser_get_count", .browserGetCount, "Count elements matching a CSS selector.", required: [
            arg("selector", "CSS selector.")
        ]),
        spec("browser_get_box", .browserGetBox, "Get an element bounding box by snapshot ref.", required: [refArg]),
        spec("browser_get_styles", .browserGetStyles, "Get computed styles for an element.", required: [refArg], optional: [
            arg("names", "Optional comma-separated CSS property names.")
        ]),
        spec("browser_is_visible", .browserIsVisible, "Check whether an element is visible.", required: [refArg]),
        spec("browser_is_enabled", .browserIsEnabled, "Check whether an element is enabled.", required: [refArg]),
        spec("browser_is_checked", .browserIsChecked, "Check whether an element is checked.", required: [refArg]),
        spec("browser_find_role", .browserFindRole, "Find elements by role and optional accessible name.", required: [
            arg("role", "ARIA/accessibility role.")
        ], optional: [
            arg("name", "Optional accessible name.")
        ]),
        spec("browser_find_text", .browserFindText, "Find elements by visible text.", required: [
            arg("text", "Visible text.")
        ]),
        spec("browser_find_label", .browserFindLabel, "Find form controls by label text.", required: [
            arg("text", "Label text.")
        ]),
        spec("browser_find_placeholder", .browserFindPlaceholder, "Find form controls by placeholder text.", required: [
            arg("text", "Placeholder text.")
        ]),
        spec("browser_find_alt", .browserFindAlt, "Find elements by alt text.", required: [
            arg("text", "Alt text.")
        ]),
        spec("browser_find_title", .browserFindTitle, "Find elements by title attribute.", required: [
            arg("text", "Title text.")
        ]),
        spec("browser_find_testid", .browserFindTestID, "Find elements by test id attributes.", required: [
            arg("id", "Test id.")
        ]),
        spec("browser_find_first", .browserFindFirst, "Find the first element matching a CSS selector.", required: [
            arg("selector", "CSS selector.")
        ]),
        spec("browser_find_last", .browserFindLast, "Find the last element matching a CSS selector.", required: [
            arg("selector", "CSS selector.")
        ]),
        spec("browser_find_nth", .browserFindNth, "Find the nth element matching a CSS selector.", required: [
            arg("index", "Zero-based index.", type: .number),
            arg("selector", "CSS selector.")
        ]),
        spec("browser_screenshot", .browserScreenshot, "Capture a PNG screenshot of the active browser tab.", optional: [
            arg("output", "Optional local output path for the PNG.")
        ]),
        spec("browser_console", .browserConsole, "List captured browser console entries."),
        spec("browser_wait", .browserWait, "Wait for a CSS selector in the active browser tab.", required: [
            arg("selector", "CSS selector.")
        ], optional: [timeoutArg]),
        spec("browser_cookies_list", .browserCookiesList, "List script-visible cookies.", optional: [
            arg("domain", "Optional cookie domain filter.")
        ]),
        spec("browser_cookies_set", .browserCookiesSet, "Set a script-visible cookie.", required: [
            arg("name", "Cookie name."),
            arg("value", "Cookie value.")
        ], optional: [
            arg("path", "Optional cookie path."),
            arg("domain", "Optional cookie domain."),
            arg("secure", "Whether to set Secure.", type: .boolean),
            arg("same-site", "Optional SameSite value."),
            arg("max-age", "Optional max age in seconds.", type: .number)
        ]),
        spec("browser_cookies_delete", .browserCookiesDelete, "Delete a script-visible cookie.", required: [
            arg("name", "Cookie name.")
        ], optional: [
            arg("path", "Optional cookie path."),
            arg("domain", "Optional cookie domain.")
        ]),
        spec("browser_network", .browserNetwork, "List recent resource timing entries.", optional: [
            arg("filter", "Optional URL/name filter."),
            arg("tail", "Optional result tail count.", type: .number)
        ]),
        spec("browser_frames", .browserFrames, "List frame metadata for the current page."),
        spec("browser_downloads", .browserDownloads, "List active and completed browser downloads."),
        spec("browser_storage_list", .browserStorageList, "List localStorage or sessionStorage entries.", optional: [
            arg("area", "Storage area: local or session.")
        ]),
        spec("browser_storage_get", .browserStorageGet, "Get a localStorage or sessionStorage value.", required: [
            arg("key", "Storage key.")
        ], optional: [
            arg("area", "Storage area: local or session.")
        ]),
        spec("browser_storage_set", .browserStorageSet, "Set a localStorage or sessionStorage value.", required: [
            arg("key", "Storage key."),
            arg("value", "Storage value.")
        ], optional: [
            arg("area", "Storage area: local or session.")
        ]),
        spec("browser_storage_delete", .browserStorageDelete, "Delete a localStorage or sessionStorage value.", required: [
            arg("key", "Storage key.")
        ], optional: [
            arg("area", "Storage area: local or session.")
        ]),
    ]
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
