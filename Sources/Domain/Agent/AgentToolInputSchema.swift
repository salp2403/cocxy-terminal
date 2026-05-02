// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolInputSchema.swift - Local Agent tool argument schema contracts.

import Foundation

struct AgentToolInputSchema: Codable, Sendable, Equatable {
    let properties: [String: AgentToolInputProperty]
    let required: [String]
    let additionalProperties: Bool

    init(
        properties: [String: AgentToolInputProperty] = [:],
        required: [String] = [],
        additionalProperties: Bool = false
    ) {
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    static let empty = AgentToolInputSchema()
}

struct AgentToolInputProperty: Codable, Sendable, Equatable {
    enum ValueType: String, Codable, Sendable, Equatable {
        case boolean
        case number
        case string
    }

    let type: ValueType
    let description: String

    init(_ type: ValueType, description: String) {
        self.type = type
        self.description = description
    }
}
