// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolProtocol.swift - JSON protocol for Agent Mode tool calls.

import Foundation

enum AgentJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AgentJSONValue])
    case object([String: AgentJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([AgentJSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: AgentJSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.typeMismatch(
                AgentJSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported Agent JSON value"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

enum AgentToolProtocolError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
    case unknownToolID(String)
    case missingRequiredArgument(toolID: String, argument: String)
}

struct AgentToolCall: Codable, Sendable, Equatable {
    let id: String
    let toolID: String
    let arguments: [String: AgentJSONValue]

    init(id: String, toolID: String, arguments: [String: AgentJSONValue] = [:]) {
        self.id = id
        self.toolID = AgentToolDescriptor.normalizedID(toolID)
        self.arguments = arguments
    }

    func invocation(using registry: AgentToolRegistry) throws -> AgentToolInvocation {
        guard let descriptor = registry.descriptor(for: toolID) else {
            throw AgentToolProtocolError.unknownToolID(toolID)
        }

        if descriptor.capability == .command {
            guard let command = arguments["command"]?.stringValue,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw AgentToolProtocolError.missingRequiredArgument(
                    toolID: descriptor.id,
                    argument: "command"
                )
            }
            return AgentToolInvocation(
                toolID: descriptor.id,
                capability: descriptor.capability,
                command: command
            )
        }

        return AgentToolInvocation(toolID: descriptor.id, capability: descriptor.capability)
    }
}

struct AgentToolCallEnvelope: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let call: AgentToolCall

    init(version: Int = AgentToolCallEnvelope.currentVersion, call: AgentToolCall) {
        self.version = version
        self.call = call
    }
}

enum AgentToolResultStatus: String, Codable, Sendable, Equatable {
    case success
    case failure
}

struct AgentToolErrorPayload: Codable, Sendable, Equatable {
    let code: String
    let message: String
}

struct AgentToolResult: Codable, Sendable, Equatable {
    let callID: String
    let toolID: String
    let status: AgentToolResultStatus
    let content: AgentJSONValue?
    let error: AgentToolErrorPayload?

    static func success(
        callID: String,
        toolID: String,
        content: AgentJSONValue? = nil
    ) -> AgentToolResult {
        AgentToolResult(
            callID: callID,
            toolID: AgentToolDescriptor.normalizedID(toolID),
            status: .success,
            content: content,
            error: nil
        )
    }

    static func failure(
        callID: String,
        toolID: String,
        code: String,
        message: String
    ) -> AgentToolResult {
        AgentToolResult(
            callID: callID,
            toolID: AgentToolDescriptor.normalizedID(toolID),
            status: .failure,
            content: nil,
            error: AgentToolErrorPayload(code: code, message: message)
        )
    }
}

enum AgentToolProtocolCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decodeCallEnvelope(from data: Data) throws -> AgentToolCallEnvelope {
        let envelope = try JSONDecoder().decode(AgentToolCallEnvelope.self, from: data)
        guard envelope.version == AgentToolCallEnvelope.currentVersion else {
            throw AgentToolProtocolError.unsupportedVersion(envelope.version)
        }
        return envelope
    }
}
