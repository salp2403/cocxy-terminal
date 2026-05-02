// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPServer.swift - User-managed MCP server configuration.

import Foundation

struct MCPServer: Identifiable, Sendable, Equatable {
    enum Transport: Sendable, Equatable {
        case stdio(
            command: String,
            arguments: [String] = [],
            environment: [String: String] = [:],
            workingDirectory: String? = nil
        )
        case http(url: URL, headers: [String: String] = [:])
    }

    let id: String
    let displayName: String
    let enabled: Bool
    let transport: Transport

    init(
        id: String,
        displayName: String? = nil,
        enabled: Bool = true,
        transport: Transport
    ) {
        self.id = id.lowercased()
        self.displayName = displayName ?? id
        self.enabled = enabled
        self.transport = transport
    }
}

enum MCPServerConfigError: Error, Sendable, Equatable {
    case invalidRoot
    case missingServers
    case invalidServerID(String)
    case invalidServerConfig(String)
    case missingTransport(String)
    case invalidURL(String)
}

extension MCPServerConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            return "MCP config must be a JSON object."
        case .missingServers:
            return "MCP config does not contain an mcpServers object."
        case .invalidServerID(let id):
            return "Invalid MCP server identifier: \(id)"
        case .invalidServerConfig(let id):
            return "Invalid MCP server config for \(id)."
        case .missingTransport(let id):
            return "MCP server \(id) must define either command or url."
        case .invalidURL(let id):
            return "MCP server \(id) has an invalid url."
        }
    }
}

struct MCPServerConfigLoader: Sendable {
    static let defaultConfigText = """
    {
      "mcpServers": {}
    }
    """

    func loadServers(from configURL: URL) throws -> [MCPServer] {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return []
        }

        let data = try Data(contentsOf: configURL)
        return try loadServers(from: data)
    }

    func loadConfigText(from configURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return Self.defaultConfigText
        }
        return try String(contentsOf: configURL, encoding: .utf8)
    }

    func validateConfigText(_ text: String) throws -> [MCPServer] {
        try loadServers(from: Data(text.utf8))
    }

    @discardableResult
    func writeConfigText(_ text: String, to configURL: URL) throws -> [MCPServer] {
        let servers = try validateConfigText(text)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: configURL, atomically: true, encoding: .utf8)
        return servers
    }

    func defaultConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".cocxy", isDirectory: true)
            .appendingPathComponent("mcp.json")
    }

    private func loadServers(from data: Data) throws -> [MCPServer] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServerConfigError.invalidRoot
        }
        guard let rawServers = root["mcpServers"] as? [String: Any] else {
            throw MCPServerConfigError.missingServers
        }

        let servers = try rawServers.map { id, rawConfig -> MCPServer in
            guard SkillLoader.isValidIdentifier(id.lowercased()) else {
                throw MCPServerConfigError.invalidServerID(id)
            }
            guard let config = rawConfig as? [String: Any] else {
                throw MCPServerConfigError.invalidServerConfig(id)
            }
            return try server(id: id.lowercased(), config: config)
        }

        return servers.sorted { $0.id < $1.id }
    }

    private func server(id: String, config: [String: Any]) throws -> MCPServer {
        let displayName = config["name"] as? String
        let enabled = (config["enabled"] as? Bool) ?? true

        if let command = nonEmptyString(config["command"]) {
            return MCPServer(
                id: id,
                displayName: displayName,
                enabled: enabled,
                transport: .stdio(
                    command: command,
                    arguments: stringArray(config["args"] ?? config["arguments"]),
                    environment: stringDictionary(config["env"] ?? config["environment"]),
                    workingDirectory: nonEmptyString(config["cwd"] ?? config["workingDirectory"])
                )
            )
        }

        if let rawURL = nonEmptyString(config["url"]) {
            guard let url = URL(string: rawURL), url.scheme != nil else {
                throw MCPServerConfigError.invalidURL(id)
            }
            return MCPServer(
                id: id,
                displayName: displayName,
                enabled: enabled,
                transport: .http(url: url, headers: stringDictionary(config["headers"]))
            )
        }

        throw MCPServerConfigError.missingTransport(id)
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private func stringDictionary(_ value: Any?) -> [String: String] {
        (value as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
    }
}
