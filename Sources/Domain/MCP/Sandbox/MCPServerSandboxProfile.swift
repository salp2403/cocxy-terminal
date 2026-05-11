// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPServerSandboxProfile.swift - Sandbox profile planning for MCP servers.

import Foundation

struct MCPServerSandboxProfile: Sendable, Equatable {
    let server: MCPServer
    let additionalReadableURLs: [URL]

    init(server: MCPServer, additionalReadableURLs: [URL] = []) {
        self.server = server
        self.additionalReadableURLs = additionalReadableURLs
    }

    var capabilities: Set<SandboxCapability> {
        switch server.transport {
        case .stdio:
            return [.filesystemRead, .processExec]
        case .http:
            return [.network]
        }
    }

    func profile(builder: SandboxProfileBuilder = SandboxProfileBuilder()) -> String {
        builder.profile(
            capabilities: capabilities,
            readablePaths: readablePaths,
            writablePaths: [],
            executablePaths: executablePaths
        )
    }

    private var readablePaths: [URL] {
        switch server.transport {
        case .stdio(_, _, _, let workingDirectory):
            let configuredDirectory = workingDirectory.map { [Self.directoryURL(for: $0)] } ?? []
            return configuredDirectory + additionalReadableURLs
        case .http:
            return additionalReadableURLs
        }
    }

    private var executablePaths: [URL] {
        switch server.transport {
        case .stdio(let command, _, _, _):
            return [Self.executableURL(for: command)]
        case .http:
            return []
        }
    }

    private static func executableURL(for command: String) -> URL {
        let expanded = (command as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private static func directoryURL(for path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(expanded, isDirectory: true)
    }
}
