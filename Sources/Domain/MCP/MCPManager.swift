// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPManager.swift - Coordinates configured MCP clients for Agent Mode.

import Foundation

protocol MCPManaging: Sendable {
    func listToolDescriptors() async throws -> [AgentToolDescriptor]
    func executeTool(agentToolID: String, arguments: [String: AgentJSONValue]) async throws -> AgentJSONValue
}

actor MCPCompositeManager: MCPManaging {
    private let managers: [any MCPManaging]

    init(managers: [any MCPManaging]) {
        self.managers = managers
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        var descriptors: [AgentToolDescriptor] = []
        for manager in managers {
            descriptors.append(contentsOf: try await manager.listToolDescriptors())
        }
        return descriptors.sorted { $0.id < $1.id }
    }

    func executeTool(
        agentToolID: String,
        arguments: [String: AgentJSONValue]
    ) async throws -> AgentJSONValue {
        let normalizedToolID = AgentToolDescriptor.normalizedID(agentToolID)
        for manager in managers {
            let descriptors = try await manager.listToolDescriptors()
            guard descriptors.contains(where: { $0.id == normalizedToolID }) else {
                continue
            }
            return try await manager.executeTool(agentToolID: normalizedToolID, arguments: arguments)
        }
        throw MCPManagerError.unknownTool(agentToolID)
    }
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

struct MCPClientTransportFactory: Sendable {
    let httpTransport: any AgentHTTPTransport
    let stdioTransport: any MCPTransport

    init(
        httpTransport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        stdioTransport: any MCPTransport = MCPStdioTransport()
    ) {
        self.httpTransport = httpTransport
        self.stdioTransport = stdioTransport
    }

    static func localDefault(securitySandbox: SecuritySandboxConfig = .defaults) -> MCPClientTransportFactory {
        let auditLog = securitySandbox.auditLogEnabled
            ? SandboxAuditLog(fileURL: .defaultSandboxAuditLog)
            : nil
        return MCPClientTransportFactory(
            stdioTransport: MCPStdioTransport(processLauncher: MCPStdioProcessLauncher(
                isolateServers: securitySandbox.mcpIsolated,
                auditLog: auditLog
            ))
        )
    }

    func transport(for server: MCPServer) -> any MCPTransport {
        switch server.transport {
        case .stdio:
            return stdioTransport
        case .http:
            return MCPHTTPTransport(httpTransport: httpTransport)
        }
    }
}

actor MCPConfiguredManager: MCPManaging {
    private let configURL: URL
    private let configLoader: MCPServerConfigLoader
    private let transportFactory: MCPClientTransportFactory
    private var cachedManager: MCPManager?

    init(
        configURL: URL = MCPServerConfigLoader().defaultConfigURL(),
        configLoader: MCPServerConfigLoader = MCPServerConfigLoader(),
        transportFactory: MCPClientTransportFactory = MCPClientTransportFactory()
    ) {
        self.configURL = configURL
        self.configLoader = configLoader
        self.transportFactory = transportFactory
    }

    func listToolDescriptors() async throws -> [AgentToolDescriptor] {
        try await manager().listToolDescriptors()
    }

    func executeTool(
        agentToolID: String,
        arguments: [String: AgentJSONValue]
    ) async throws -> AgentJSONValue {
        try await manager().executeTool(agentToolID: agentToolID, arguments: arguments)
    }

    func reload() {
        cachedManager = nil
    }

    private func manager() async throws -> MCPManager {
        if let cachedManager {
            return cachedManager
        }

        let servers = try configLoader
            .loadServers(from: configURL)
            .filter(\.enabled)
        let clients = servers.map { server in
            MCPClient(
                server: server,
                transport: transportFactory.transport(for: server)
            )
        }
        let manager = await MCPManager(clients: clients)
        cachedManager = manager
        return manager
    }
}
