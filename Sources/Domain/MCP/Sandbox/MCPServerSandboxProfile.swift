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
            var capabilities: Set<SandboxCapability> = [.filesystemRead, .processExec]
            if !argumentWritableLiterals.isEmpty {
                capabilities.insert(.filesystemWrite)
            }
            return capabilities
        case .http:
            return [.network]
        }
    }

    func profile(
        builder: SandboxProfileBuilder = SandboxProfileBuilder(),
        commandURL: URL? = nil
    ) -> String {
        let readableLiteralPaths = readableLiteralPaths(commandURL: commandURL)
        return builder.profile(
            capabilities: capabilities,
            readablePaths: readablePaths + runtimeReadablePaths(commandURL: commandURL),
            writablePaths: [],
            executablePaths: commandURL.map { [$0] } ?? executablePaths,
            readableLiteralPaths: readableLiteralPaths,
            writableLiteralPaths: argumentWritableLiterals,
            executableSubpaths: executableSubpaths(commandURL: commandURL),
            includeSystemReadBaseline: true
        )
    }

    private var readablePaths: [URL] {
        switch server.transport {
        case .stdio(_, _, _, let workingDirectory):
            let configuredDirectory = workingDirectory.map { [Self.directoryURL(for: $0)] } ?? []
            return configuredDirectory + argumentReadableParentDirectories + additionalReadableURLs
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

    private func executableSubpaths(commandURL: URL?) -> [URL] {
        guard let commandURL else { return [] }
        let path = commandURL.path
        if path == "/usr/bin/python3" || path.contains("/Python3.framework/") {
            return [
                URL(fileURLWithPath: "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework", isDirectory: true),
                URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework", isDirectory: true),
            ]
        }
        return []
    }

    private func runtimeReadablePaths(commandURL: URL?) -> [URL] {
        guard let path = commandURL?.path,
              path == "/usr/bin/python3" || path.contains("/Python3.framework/")
        else {
            return []
        }
        return [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/com.apple.python", isDirectory: true),
        ]
    }

    private func readableLiteralPaths(commandURL: URL?) -> [URL] {
        let literals = ([commandURL].compactMap { $0 } + argumentReadableLiterals)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
        let parents = literals.flatMap { SandboxProfileBuilder.parentDirectoryLiterals(for: $0) }
        return parents + literals
    }

    private var argumentReadableLiterals: [URL] {
        switch server.transport {
        case .stdio(_, let arguments, _, let workingDirectory):
            return arguments.compactMap { Self.argumentURL(for: $0, workingDirectory: workingDirectory) }
        case .http:
            return []
        }
    }

    private var argumentReadableParentDirectories: [URL] {
        argumentReadableLiterals.map { url in
            var directoryURL = url
            directoryURL.deleteLastPathComponent()
            return directoryURL
        }
    }

    private var argumentWritableLiterals: [URL] {
        switch server.transport {
        case .stdio(_, let arguments, _, let workingDirectory):
            return arguments.enumerated().compactMap { index, argument in
                guard index > 0,
                      let url = Self.argumentURL(for: argument, workingDirectory: workingDirectory),
                      Self.parentDirectoryExists(for: url),
                      !FileManager.default.fileExists(atPath: url.path)
                else {
                    return nil
                }
                return url
            }
        case .http:
            return []
        }
    }

    private static func argumentURL(for argument: String, workingDirectory: String?) -> URL? {
        let expanded = (argument as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        guard argument.hasPrefix("./") || argument.hasPrefix("../"),
              let workingDirectory
        else {
            return nil
        }
        return directoryURL(for: workingDirectory).appendingPathComponent(argument)
    }

    private static func parentDirectoryExists(for url: URL) -> Bool {
        var parentURL = url
        parentURL.deleteLastPathComponent()
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
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
