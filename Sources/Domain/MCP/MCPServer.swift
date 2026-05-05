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
    let authorization: MCPAuthorization?
    let transport: Transport

    init(
        id: String,
        displayName: String? = nil,
        enabled: Bool = true,
        authorization: MCPAuthorization? = nil,
        transport: Transport
    ) {
        self.id = id.lowercased()
        self.displayName = displayName ?? id
        self.enabled = enabled
        self.authorization = authorization
        self.transport = transport
    }
}

struct MCPAuthorization: Sendable, Equatable {
    enum Scheme: String, Sendable, Equatable {
        case bearer
    }

    enum TokenSource: Sendable, Equatable {
        case environment(String)
    }

    let scheme: Scheme
    let tokenSource: TokenSource

    static func bearerToken(environmentKey: String) -> MCPAuthorization {
        MCPAuthorization(scheme: .bearer, tokenSource: .environment(environmentKey))
    }
}

enum MCPServerConfigError: Error, Sendable, Equatable {
    case invalidRoot
    case missingServers
    case invalidServerID(String)
    case invalidServerConfig(String)
    case missingTransport(String)
    case invalidURL(String)
    case invalidEnvironmentKey(String, String)
    case invalidAuthorization(String)
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
        case .invalidEnvironmentKey(let id, let key):
            return "MCP server \(id) has an invalid environment key: \(key)"
        case .invalidAuthorization(let id):
            return "MCP server \(id) has an invalid authorization config."
        }
    }
}

enum MCPEnvironment {
    static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }
        guard isLetter(first) || first == "_" else { return false }

        return key.unicodeScalars.allSatisfy { scalar in
            isLetter(scalar)
                || isDigit(scalar)
                || scalar == "_"
        }
    }

    static func expandReferences(
        in value: String,
        environment: [String: String]
    ) -> String {
        var output = ""
        var remaining = value[...]

        while let start = remaining.range(of: "${"),
              let end = remaining[start.upperBound...].firstIndex(of: "}") {
            output += String(remaining[..<start.lowerBound])
            let name = String(remaining[start.upperBound..<end])
            output += environment[name] ?? ""
            remaining = remaining[remaining.index(after: end)...]
        }

        output += String(remaining)
        return output
    }

    private static func isLetter(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func isDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
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
        let authorization = try authorization(config["authorization"] ?? config["auth"] ?? config["oauth"], serverID: id)

        if let command = nonEmptyString(config["command"]) {
            if authorization != nil {
                throw MCPServerConfigError.invalidAuthorization(id)
            }
            let environment = stringDictionary(config["env"] ?? config["environment"])
            try validateEnvironmentKeys(environment.keys, serverID: id)
            return MCPServer(
                id: id,
                displayName: displayName,
                enabled: enabled,
                transport: .stdio(
                    command: command,
                    arguments: stringArray(config["args"] ?? config["arguments"]),
                    environment: environment,
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
                authorization: authorization,
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

    private func authorization(_ value: Any?, serverID: String) throws -> MCPAuthorization? {
        guard let value else { return nil }
        guard let object = value as? [String: Any] else {
            throw MCPServerConfigError.invalidAuthorization(serverID)
        }

        guard let scheme = nonEmptyString(object["type"] ?? object["scheme"])?.lowercased(),
              scheme == "bearer"
        else {
            throw MCPServerConfigError.invalidAuthorization(serverID)
        }

        guard let tokenEnv = nonEmptyString(
            object["tokenEnv"] ?? object["token_env"] ?? object["env"]
        ) else {
            throw MCPServerConfigError.invalidAuthorization(serverID)
        }
        try validateEnvironmentKeys([tokenEnv], serverID: serverID)

        return .bearerToken(environmentKey: tokenEnv)
    }

    private func validateEnvironmentKeys(
        _ keys: some Sequence<String>,
        serverID: String
    ) throws {
        for key in keys where !MCPEnvironment.isValidKey(key) {
            throw MCPServerConfigError.invalidEnvironmentKey(serverID, key)
        }
    }
}
