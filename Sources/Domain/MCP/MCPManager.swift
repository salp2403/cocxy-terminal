// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPManager.swift - Coordinates configured MCP clients for Agent Mode.

import Foundation

protocol MCPManaging: Sendable {
    func listToolDescriptors() async throws -> [AgentToolDescriptor]
    func executeTool(agentToolID: String, arguments: [String: AgentJSONValue]) async throws -> AgentJSONValue
}

enum MCPManagerError: Error, Sendable, Equatable {
    case unknownTool(String)
    case serverUnavailable(String)
}

extension MCPManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknownTool(let toolID):
            return "Unknown MCP tool: \(toolID)"
        case .serverUnavailable(let serverID):
            return "MCP server is unavailable: \(serverID)"
        }
    }
}

actor MCPManager: MCPManaging {
    private let clientsByServerID: [String: MCPClient]

    init(clients: [MCPClient]) async {
        var clientsByServerID: [String: MCPClient] = [:]
        for client in clients {
            let server = client.server
            clientsByServerID[server.id] = client
        }
        self.clientsByServerID = clientsByServerID
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        var descriptors: [AgentToolDescriptor] = []

        for serverID in clientsByServerID.keys.sorted() {
            guard let client = clientsByServerID[serverID] else { continue }
            let server = client.server
            guard server.enabled else { continue }
            let tools = try await client.listTools()
            descriptors.append(contentsOf: tools.map {
                MCPToolBridge.descriptor(for: $0, serverID: serverID)
            })
        }

        return descriptors.sorted { $0.id < $1.id }
    }

    func executeTool(
        agentToolID: String,
        arguments: [String: AgentJSONValue]
    ) async throws -> AgentJSONValue {
        guard let route = MCPToolBridge.parseToolID(agentToolID) else {
            throw MCPManagerError.unknownTool(agentToolID)
        }
        guard let client = clientsByServerID[route.serverID] else {
            throw MCPManagerError.serverUnavailable(route.serverID)
        }

        let normalizedToolID = AgentToolDescriptor.normalizedID(agentToolID)
        let tools = try await client.listTools()
        guard let originalTool = tools.first(where: {
            MCPToolBridge.descriptor(for: $0, serverID: route.serverID).id == normalizedToolID
        }) else {
            throw MCPManagerError.unknownTool(agentToolID)
        }

        let result = try await client.callTool(name: originalTool.name, arguments: arguments)
        return MCPToolBridge.agentJSONValue(from: result)
    }
}
