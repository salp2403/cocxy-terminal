// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPStdioTransport.swift - Newline-delimited JSON-RPC transport for local MCP servers.

import Foundation

protocol MCPStdioProcess: Sendable {
    var isRunning: Bool { get }
    func write(_ data: Data) throws
    func readLine() throws -> String
    func terminate()
}

protocol MCPStdioProcessLaunching: Sendable {
    func launch(server: MCPServer) throws -> any MCPStdioProcess
}

enum MCPStdioTransportError: Error, Sendable, Equatable {
    case unsupportedServer(serverID: String)
    case processUnavailable(serverID: String)
    case processExited(serverID: String)
    case invalidUTF8Response(serverID: String)
}

extension MCPStdioTransportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedServer(let serverID):
            return "MCP server \(serverID) is not configured for stdio transport."
        case .processUnavailable(let serverID):
            return "MCP stdio process is unavailable for server \(serverID)."
        case .processExited(let serverID):
            return "MCP stdio process exited for server \(serverID)."
        case .invalidUTF8Response(let serverID):
            return "MCP stdio process returned invalid UTF-8 for server \(serverID)."
        }
    }
}

actor MCPStdioTransport: MCPTransport {
    private let processLauncher: any MCPStdioProcessLaunching
    private var processesByServerID: [String: any MCPStdioProcess] = [:]

    init(processLauncher: any MCPStdioProcessLaunching = MCPStdioProcessLauncher()) {
        self.processLauncher = processLauncher
    }

    func send(_ request: MCPJSONRPCRequest, to server: MCPServer) async throws -> MCPJSONRPCResponse {
        guard case .stdio = server.transport else {
            throw MCPStdioTransportError.unsupportedServer(serverID: server.id)
        }

        let process = try process(for: server)
        let requestData = try AgentToolProtocolCodec.encode(request) + Data([0x0A])

        do {
            try process.write(requestData)
            return try readResponse(for: request, from: process, serverID: server.id)
        } catch {
            if !process.isRunning {
                processesByServerID[server.id] = nil
            }
            throw error
        }
    }

    func reset(serverID: String) {
        if let process = processesByServerID[serverID] {
            process.terminate()
        }
        processesByServerID[serverID] = nil
    }

    func shutdownAll() {
        for process in processesByServerID.values {
            process.terminate()
        }
        processesByServerID.removeAll()
    }

    private func process(for server: MCPServer) throws -> any MCPStdioProcess {
        if let process = processesByServerID[server.id], process.isRunning {
            return process
        }

        let process = try processLauncher.launch(server: server)
        processesByServerID[server.id] = process
        return process
    }

    private func readResponse(
        for request: MCPJSONRPCRequest,
        from process: any MCPStdioProcess,
        serverID: String
    ) throws -> MCPJSONRPCResponse {
        while true {
            let line = try process.readLine()
            guard let responseData = line.data(using: .utf8) else {
                throw MCPStdioTransportError.invalidUTF8Response(serverID: serverID)
            }

            let probe = try JSONDecoder().decode(MCPJSONRPCMessageProbe.self, from: responseData)
            guard probe.id == request.id, probe.isResponse else {
                continue
            }

            return try JSONDecoder().decode(MCPJSONRPCResponse.self, from: responseData)
        }
    }
}

private struct MCPJSONRPCMessageProbe: Decodable {
    let id: String?
    let result: AgentJSONValue?
    let error: MCPJSONRPCError?

    var isResponse: Bool {
        result != nil || error != nil
    }
}

struct MCPStdioProcessLauncher: MCPStdioProcessLaunching {
    private let sandboxPolicy: MCPStdioSandboxPolicy

    init(sandboxPolicy: MCPStdioSandboxPolicy = MCPStdioSandboxPolicy()) {
        self.sandboxPolicy = sandboxPolicy
    }

    func launch(server: MCPServer) throws -> any MCPStdioProcess {
        guard case .stdio(let command, let arguments, let environment, let workingDirectory) = server.transport else {
            throw MCPStdioTransportError.unsupportedServer(serverID: server.id)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let commandURL = executableURL(for: command)

        process.executableURL = commandURL.url
        process.arguments = commandURL.argumentsPrefix + arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.environment = try sandboxPolicy.resolvedEnvironment(overrides: environment)
        if let workingDirectory {
            process.currentDirectoryURL = directoryURL(for: workingDirectory)
        }

        try process.run()

        return MCPStdioChildProcess(
            serverID: server.id,
            process: process,
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading,
            error: error.fileHandleForReading
        )
    }

    private func executableURL(for command: String) -> (url: URL, argumentsPrefix: [String]) {
        let expanded = (command as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return (URL(fileURLWithPath: expanded), [])
        }

        return (URL(fileURLWithPath: "/usr/bin/env"), [command])
    }

    private func directoryURL(for path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(expanded, isDirectory: true)
    }

}

enum MCPStdioSandboxError: Error, Sendable, Equatable {
    case invalidEnvironmentKey(String)
}

extension MCPStdioSandboxError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidEnvironmentKey(let key):
            return "Invalid MCP stdio environment key: \(key)"
        }
    }
}

struct MCPStdioSandboxPolicy: Sendable {
    private static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private static let allowedInheritedKeys: Set<String> = [
        "PATH",
        "HOME",
        "TMPDIR",
        "DEVELOPER_DIR",
        "SDKROOT",
        "TOOLCHAINS",
        "SHELL",
        "USER",
        "LOGNAME",
        "LANG",
        "XDG_CONFIG_HOME",
        "XDG_CACHE_HOME",
        "XDG_DATA_HOME",
        "JAVA_HOME",
        "GOPATH",
        "GOROOT",
        "CARGO_HOME",
        "RUSTUP_HOME",
        "NODE_PATH",
        "NPM_CONFIG_PREFIX",
        "PYENV_ROOT",
        "RBENV_ROOT",
        "GEM_HOME",
        "GEM_PATH",
        "COMPOSER_HOME",
    ]

    private static let blockedInheritedKeyFragments = [
        "secret",
        "token",
        "password",
        "credential",
        "private_key",
        "apikey",
        "api_key",
        "authorization",
    ]

    private let inheritedEnvironment: [String: String]

    init(inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.inheritedEnvironment = inheritedEnvironment
    }

    func resolvedEnvironment(overrides: [String: String]) throws -> [String: String] {
        var environment = inheritedEnvironment.reduce(into: [String: String]()) { result, pair in
            guard Self.shouldInherit(pair.key) else { return }
            result[pair.key] = pair.value
        }

        environment["PATH"] = Self.sandboxedSearchPath(environment["PATH"])

        for key in overrides.keys.sorted() {
            guard MCPEnvironment.isValidKey(key) else {
                throw MCPStdioSandboxError.invalidEnvironmentKey(key)
            }
            guard let value = overrides[key] else { continue }
            environment[key] = MCPEnvironment.expandReferences(in: value, environment: inheritedEnvironment)
        }

        return environment
    }

    private static func shouldInherit(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        guard allowedInheritedKeys.contains(key) || key.hasPrefix("LC_") else {
            return false
        }
        return !blockedInheritedKeyFragments.contains { lowercased.contains($0) }
    }

    private static func sandboxedSearchPath(_ inheritedPath: String?) -> String {
        let inheritedComponents = inheritedPath?
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        var components = inheritedComponents

        for fallback in defaultPath.split(separator: ":").map(String.init) where !components.contains(fallback) {
            components.append(fallback)
        }

        return components.joined(separator: ":")
    }
}

private final class MCPStdioChildProcess: MCPStdioProcess, @unchecked Sendable {
    private let serverID: String
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let error: FileHandle
    private let lock = NSLock()

    var isRunning: Bool {
        process.isRunning
    }

    init(
        serverID: String,
        process: Process,
        input: FileHandle,
        output: FileHandle,
        error: FileHandle
    ) {
        self.serverID = serverID
        self.process = process
        self.input = input
        self.output = output
        self.error = error
        drainStandardError()
    }

    deinit {
        error.readabilityHandler = nil
        terminate()
    }

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try input.write(contentsOf: data)
    }

    func readLine() throws -> String {
        var data = Data()

        while true {
            guard let next = try output.read(upToCount: 1), !next.isEmpty else {
                throw MCPStdioTransportError.processExited(serverID: serverID)
            }
            if next.first == 0x0A {
                if data.isEmpty {
                    continue
                }
                break
            }
            if next.first != 0x0D {
                data.append(next)
            }
        }

        guard let line = String(data: data, encoding: .utf8) else {
            throw MCPStdioTransportError.invalidUTF8Response(serverID: serverID)
        }
        return line
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
        try? input.close()
        try? output.close()
        try? error.close()
    }

    private func drainStandardError() {
        error.readabilityHandler = { handle in
            _ = handle.availableData
        }
    }
}
