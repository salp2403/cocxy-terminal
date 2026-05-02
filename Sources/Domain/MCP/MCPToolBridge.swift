// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPToolBridge.swift - Converts MCP tools into Agent Mode tool descriptors.

import Foundation

struct MCPToolRoute: Sendable, Equatable {
    let serverID: String
    let toolName: String
}

enum MCPToolBridge {
    private static let prefix = "mcp__"

    static func descriptor(for tool: MCPTool, serverID: String) -> AgentToolDescriptor {
        AgentToolDescriptor(
            id: agentToolID(serverID: serverID, toolName: tool.name),
            displayName: "\(serverID): \(tool.name)",
            description: tool.description,
            capability: .external,
            inputSchema: agentInputSchema(from: tool.inputSchema)
        )
    }

    static func parseToolID(_ rawID: String) -> MCPToolRoute? {
        let normalized = AgentToolDescriptor.normalizedID(rawID)
        guard normalized.hasPrefix(prefix) else { return nil }
        let remainder = String(normalized.dropFirst(prefix.count))
        guard let separator = remainder.range(of: "__") else { return nil }
        let serverID = String(remainder[..<separator.lowerBound])
        let toolPart = String(remainder[separator.upperBound...])
        guard !serverID.isEmpty, !toolPart.isEmpty else { return nil }
        return MCPToolRoute(serverID: serverID, toolName: toolPart)
    }

    static func agentJSONValue(from result: MCPToolCallResult) -> AgentJSONValue {
        .object([
            "isError": .bool(result.isError),
            "content": .array(result.content.map(agentJSONValue(from:))),
        ])
    }

    private static func agentToolID(serverID: String, toolName: String) -> String {
        "mcp__\(sanitize(serverID))__\(sanitize(toolName))"
    }

    private static func sanitize(_ value: String) -> String {
        let lowercased = value.lowercased()
        var scalars: [UnicodeScalar] = []
        var previousWasSeparator = false

        for scalar in lowercased.unicodeScalars {
            let isAllowed = (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57)
            if isAllowed {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append("_")
                previousWasSeparator = true
            }
        }

        let result = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "tool" : result
    }

    private static func agentInputSchema(from schema: MCPToolInputSchema) -> AgentToolInputSchema {
        AgentToolInputSchema(
            properties: schema.properties.reduce(into: [:]) { result, entry in
                guard let type = agentValueType(from: entry.value.type) else {
                    return
                }
                result[entry.key] = AgentToolInputProperty(
                    type,
                    description: entry.value.description
                )
            },
            required: schema.required,
            additionalProperties: schema.additionalProperties
        )
    }

    private static func agentValueType(from rawType: String) -> AgentToolInputProperty.ValueType? {
        switch rawType.lowercased() {
        case "boolean":
            return .boolean
        case "integer", "number":
            return .number
        case "string":
            return .string
        default:
            return nil
        }
    }

    private static func agentJSONValue(from content: MCPContent) -> AgentJSONValue {
        switch content {
        case .text(let text):
            return .string(text)
        case .json(let value):
            return value
        }
    }
}
