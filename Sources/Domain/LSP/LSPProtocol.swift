// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPProtocol.swift - JSON-RPC primitives for the native LSP client.

import Foundation

enum LSPRequestID: Codable, Equatable, Hashable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                LSPRequestID.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected integer or string request id")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

enum LSPJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([LSPJSONValue])
    case object([String: LSPJSONValue])

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
        } else if let arrayValue = try? container.decode([LSPJSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: LSPJSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.typeMismatch(
                LSPJSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    var objectValue: [String: LSPJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [LSPJSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case let .number(value) = self else { return nil }
        return Int(value)
    }
}

struct LSPResponseError: Codable, Equatable, Sendable {
    let code: Int
    let message: String
    let data: LSPJSONValue?

    init(code: Int, message: String, data: LSPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}
