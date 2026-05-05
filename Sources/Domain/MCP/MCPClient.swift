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
    let authorizationResolver: any MCPAuthorizationResolving

    init(
        httpTransport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        authorizationResolver: any MCPAuthorizationResolving = MCPAuthorizationResolver()
    ) {
        self.httpTransport = httpTransport
        self.authorizationResolver = authorizationResolver
    }

    func send(_ request: MCPJSONRPCRequest, to server: MCPServer) async throws -> MCPJSONRPCResponse {
        guard case .http(let url, let headers) = server.transport else {
            throw MCPProtocolError.invalidResult(method: request.method)
        }

        let body = try AgentToolProtocolCodec.encode(request)
        var requestHeaders = [
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        ].merging(headers) { _, override in override }
        if let authorization = server.authorization {
            requestHeaders["Authorization"] = try authorizationResolver.authorizationHeader(for: authorization)
        }

        let response = try await httpTransport.send(AgentHTTPRequest(
            url: url,
            headers: requestHeaders,
            body: body
        ))
        guard (200..<300).contains(response.statusCode) else {
            let rawMessage = String(data: response.data, encoding: .utf8) ?? "MCP HTTP request failed"
            throw AgentProviderClientError.httpStatus(
                response.statusCode,
                AgentErrorPresentation.redacted(rawMessage)
            )
        }
        return try JSONDecoder().decode(MCPJSONRPCResponse.self, from: response.data)
    }
}

protocol MCPAuthorizationResolving: Sendable {
    func authorizationHeader(for authorization: MCPAuthorization) throws -> String
}

enum MCPAuthorizationError: Error, Sendable, Equatable {
    case missingEnvironmentVariable(String)
    case emptyEnvironmentVariable(String)
}

extension MCPAuthorizationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingEnvironmentVariable(let key):
            return "MCP authorization environment variable is missing: \(key)"
        case .emptyEnvironmentVariable(let key):
            return "MCP authorization environment variable is empty: \(key)"
        }
    }
}

struct MCPAuthorizationResolver: MCPAuthorizationResolving {
    let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func authorizationHeader(for authorization: MCPAuthorization) throws -> String {
        switch authorization.tokenSource {
        case .environment(let key):
            guard let value = environment[key] else {
                throw MCPAuthorizationError.missingEnvironmentVariable(key)
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw MCPAuthorizationError.emptyEnvironmentVariable(key)
            }

            switch authorization.scheme {
            case .bearer:
                return "Bearer \(trimmed)"
            }
        }
    }
}
