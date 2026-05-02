// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPProtocol.swift - Minimal Model Context Protocol JSON-RPC contracts.

import Foundation

struct MCPJSONRPCRequest: Codable, Sendable, Equatable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: [String: AgentJSONValue]?

    init(
        id: String,
        method: String,
        params: [String: AgentJSONValue]? = nil,
        jsonrpc: String = "2.0"
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

struct MCPJSONRPCResponse: Codable, Sendable, Equatable {
    let jsonrpc: String
    let id: String
    let result: AgentJSONValue?
    let error: MCPJSONRPCError?

    init(
        id: String,
        result: AgentJSONValue? = nil,
        error: MCPJSONRPCError? = nil,
        jsonrpc: String = "2.0"
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

struct MCPJSONRPCError: Codable, Sendable, Equatable, Error {
    let code: Int
    let message: String
}

enum MCPProtocolError: Error, Sendable, Equatable {
    case rpcError(code: Int, message: String)
    case missingResult(method: String)
    case invalidResult(method: String)
    case unsupportedContentType(String)
}

struct MCPCapabilities: Sendable, Equatable {
    let supportsTools: Bool
    let supportsResources: Bool

    static func parse(from value: AgentJSONValue) throws -> MCPCapabilities {
        let root = try value.mcpObject(method: "initialize")
        let capabilities = root["capabilities"]?.mcpObjectValue ?? [:]
        return MCPCapabilities(
            supportsTools: capabilities["tools"] != nil,
            supportsResources: capabilities["resources"] != nil
        )
    }
}

struct MCPTool: Sendable, Equatable {
    let name: String
    let description: String
    let inputSchema: MCPToolInputSchema

    init(
        name: String,
        description: String = "",
        inputSchema: MCPToolInputSchema = MCPToolInputSchema()
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    static func parse(from value: AgentJSONValue) throws -> MCPTool {
        let object = try value.mcpObject(method: "tools/list")
        guard let name = object["name"]?.stringValue else {
            throw MCPProtocolError.invalidResult(method: "tools/list")
        }
        return MCPTool(
            name: name,
            description: object["description"]?.stringValue ?? "",
            inputSchema: try object["inputSchema"].map(MCPToolInputSchema.parse) ?? MCPToolInputSchema()
        )
    }
}

struct MCPToolInputSchema: Sendable, Equatable {
    let properties: [String: MCPToolInputProperty]
    let required: [String]
    let additionalProperties: Bool

    init(
        properties: [String: MCPToolInputProperty] = [:],
        required: [String] = [],
        additionalProperties: Bool = false
    ) {
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    static func parse(from value: AgentJSONValue) throws -> MCPToolInputSchema {
        let object = try value.mcpObject(method: "tools/list")
        let rawProperties = object["properties"]?.mcpObjectValue ?? [:]
        let properties = rawProperties.reduce(into: [String: MCPToolInputProperty]()) { result, entry in
            guard let property = try? MCPToolInputProperty.parse(from: entry.value) else {
                return
            }
            result[entry.key] = property
        }
        let required = object["required"]?.mcpArrayValue?.compactMap(\.stringValue) ?? []
        let additionalProperties = object["additionalProperties"]?.mcpBoolValue ?? false

        return MCPToolInputSchema(
            properties: properties,
            required: required,
            additionalProperties: additionalProperties
        )
    }
}

struct MCPToolInputProperty: Sendable, Equatable {
    let type: String
    let description: String

    init(type: String, description: String = "") {
        self.type = type
        self.description = description
    }

    static func parse(from value: AgentJSONValue) throws -> MCPToolInputProperty {
        let object = try value.mcpObject(method: "tools/list")
        guard let type = object["type"]?.stringValue else {
            throw MCPProtocolError.invalidResult(method: "tools/list")
        }
        return MCPToolInputProperty(
            type: type,
            description: object["description"]?.stringValue ?? ""
        )
    }
}

struct MCPToolCallResult: Sendable, Equatable {
    let content: [MCPContent]
    let isError: Bool

    init(content: [MCPContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    static func parse(from value: AgentJSONValue) throws -> MCPToolCallResult {
        let object = try value.mcpObject(method: "tools/call")
        let content = try (object["content"]?.mcpArrayValue ?? []).map(MCPContent.parse)
        return MCPToolCallResult(
            content: content,
            isError: object["isError"]?.mcpBoolValue ?? false
        )
    }
}

enum MCPContent: Sendable, Equatable {
    case text(String)
    case json(AgentJSONValue)

    static func parse(from value: AgentJSONValue) throws -> MCPContent {
        let object = try value.mcpObject(method: "tools/call")
        guard let type = object["type"]?.stringValue else {
            throw MCPProtocolError.invalidResult(method: "tools/call")
        }
        switch type {
        case "text":
            return .text(object["text"]?.stringValue ?? "")
        case "json":
            return .json(object["json"] ?? .null)
        default:
            throw MCPProtocolError.unsupportedContentType(type)
        }
    }
}

struct MCPResource: Sendable, Equatable {
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?

    static func parse(from value: AgentJSONValue) throws -> MCPResource {
        let object = try value.mcpObject(method: "resources/list")
        guard let uri = object["uri"]?.stringValue,
              let name = object["name"]?.stringValue
        else {
            throw MCPProtocolError.invalidResult(method: "resources/list")
        }
        return MCPResource(
            uri: uri,
            name: name,
            description: object["description"]?.stringValue,
            mimeType: object["mimeType"]?.stringValue
        )
    }
}

struct MCPResourceReadResult: Sendable, Equatable {
    let contents: [MCPResourceContent]

    static func parse(from value: AgentJSONValue) throws -> MCPResourceReadResult {
        let object = try value.mcpObject(method: "resources/read")
        return MCPResourceReadResult(
            contents: try (object["contents"]?.mcpArrayValue ?? []).map(MCPResourceContent.parse)
        )
    }
}

struct MCPResourceContent: Sendable, Equatable {
    let uri: String
    let mimeType: String?
    let text: String?

    static func parse(from value: AgentJSONValue) throws -> MCPResourceContent {
        let object = try value.mcpObject(method: "resources/read")
        guard let uri = object["uri"]?.stringValue else {
            throw MCPProtocolError.invalidResult(method: "resources/read")
        }
        return MCPResourceContent(
            uri: uri,
            mimeType: object["mimeType"]?.stringValue,
            text: object["text"]?.stringValue
        )
    }
}

extension AgentJSONValue {
    var mcpObjectValue: [String: AgentJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var mcpArrayValue: [AgentJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var mcpBoolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    func mcpObject(method: String) throws -> [String: AgentJSONValue] {
        guard let object = mcpObjectValue else {
            throw MCPProtocolError.invalidResult(method: method)
        }
        return object
    }
}
