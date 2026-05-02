// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPClient.swift - JSON-RPC MCP client over injectable transports.

import Foundation

protocol MCPTransport: Sendable {
    func send(_ request: MCPJSONRPCRequest, to server: MCPServer) async throws -> MCPJSONRPCResponse
}

actor MCPClient {
    let server: MCPServer
    private let transport: any MCPTransport
    private var nextID = 1

    init(server: MCPServer, transport: any MCPTransport) {
        self.server = server
        self.transport = transport
    }

    func initialize(
        protocolVersion: String = "2025-03-26",
        clientName: String = "Cocxy Terminal"
    ) async throws -> MCPCapabilities {
        let result = try await send(
            method: "initialize",
            params: [
                "protocolVersion": .string(protocolVersion),
                "clientInfo": .object([
                    "name": .string(clientName),
                    "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"),
                ]),
                "capabilities": .object([:]),
            ]
        )
        return try MCPCapabilities.parse(from: result)
    }

    func listTools() async throws -> [MCPTool] {
        let result = try await send(method: "tools/list")
        let object = try result.mcpObject(method: "tools/list")
        return try (object["tools"]?.mcpArrayValue ?? []).map(MCPTool.parse)
    }

    func callTool(name: String, arguments: [String: AgentJSONValue]) async throws -> MCPToolCallResult {
        let result = try await send(
            method: "tools/call",
            params: [
                "name": .string(name),
                "arguments": .object(arguments),
            ]
        )
        return try MCPToolCallResult.parse(from: result)
    }

    func listResources() async throws -> [MCPResource] {
        let result = try await send(method: "resources/list")
        let object = try result.mcpObject(method: "resources/list")
        return try (object["resources"]?.mcpArrayValue ?? []).map(MCPResource.parse)
    }

    func readResource(uri: String) async throws -> MCPResourceReadResult {
        let result = try await send(
            method: "resources/read",
            params: ["uri": .string(uri)]
        )
        return try MCPResourceReadResult.parse(from: result)
    }

    private func send(
        method: String,
        params: [String: AgentJSONValue]? = nil
    ) async throws -> AgentJSONValue {
        let request = MCPJSONRPCRequest(
            id: String(nextID),
            method: method,
            params: params
        )
        nextID += 1

        let response = try await transport.send(request, to: server)
        if let error = response.error {
            throw MCPProtocolError.rpcError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw MCPProtocolError.missingResult(method: method)
        }
        return result
    }
}

struct MCPHTTPTransport: MCPTransport {
    let httpTransport: any AgentHTTPTransport

    init(httpTransport: any AgentHTTPTransport = URLSessionAgentHTTPTransport()) {
        self.httpTransport = httpTransport
    }

    func send(_ request: MCPJSONRPCRequest, to server: MCPServer) async throws -> MCPJSONRPCResponse {
        guard case .http(let url, let headers) = server.transport else {
            throw MCPProtocolError.invalidResult(method: request.method)
        }

        let body = try AgentToolProtocolCodec.encode(request)
        let response = try await httpTransport.send(AgentHTTPRequest(
            url: url,
            headers: [
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            ].merging(headers) { _, override in override },
            body: body
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw AgentProviderClientError.httpStatus(
                response.statusCode,
                String(data: response.data, encoding: .utf8) ?? "MCP HTTP request failed"
            )
        }
        return try JSONDecoder().decode(MCPJSONRPCResponse.self, from: response.data)
    }
}
