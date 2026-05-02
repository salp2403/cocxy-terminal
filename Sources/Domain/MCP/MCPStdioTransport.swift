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
        process.environment = resolvedEnvironment(overrides: environment)
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

    private func resolvedEnvironment(overrides: [String: String]) -> [String: String] {
        let base = ProcessInfo.processInfo.environment
        return overrides.reduce(into: base) { result, entry in
            result[entry.key] = expandEnvironmentReferences(entry.value, environment: base)
        }
    }

    private func expandEnvironmentReferences(
        _ value: String,
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
