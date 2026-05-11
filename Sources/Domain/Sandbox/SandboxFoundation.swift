// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SandboxFoundation.swift - Shared sandbox capability, profile, executor, and audit primitives.

import Foundation

// MARK: - Capabilities

enum SandboxCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case network
    case filesystemRead = "fs-read"
    case filesystemWrite = "fs-write"
    case processExec = "exec"
    case audio
    case screenCapture = "screen-capture"
}

extension PluginCapability {
    var sandboxCapabilities: Set<SandboxCapability> {
        switch self {
        case .filesystemRead:
            return [.filesystemRead]
        case .filesystemWrite:
            return [.filesystemRead, .filesystemWrite]
        case .environmentRead:
            return []
        case .processSpawn:
            return [.processExec]
        case .networkClient:
            return [.network]
        }
    }
}

// MARK: - Profile Builder

struct SandboxProfileBuilder: Sendable {
    func profile(
        capabilities: Set<SandboxCapability>,
        readablePaths: [URL],
        writablePaths: [URL],
        executablePaths: [URL],
        readableLiteralPaths: [URL] = [],
        executableSubpaths: [URL] = [],
        includeSystemReadBaseline: Bool = false
    ) -> String {
        var lines = [
            "(version 1)",
            "(deny default)",
            "(allow process-fork)",
        ]

        if includeSystemReadBaseline {
            lines.append("(allow sysctl-read)")
            lines.append(contentsOf: Self.schemeRules(
                operation: "file-read*",
                literals: Self.systemReadBaselineLiteralPaths,
                subpaths: Self.systemReadBaselineSubpaths
            ))
        }

        if capabilities.contains(.processExec) {
            lines.append(contentsOf: Self.schemeRules(
                operation: "process-exec",
                literals: Self.sortedPaths(executablePaths),
                subpaths: Self.sortedPaths(executableSubpaths)
            ))
        }

        if capabilities.contains(.filesystemRead) {
            lines.append(contentsOf: Self.schemeRules(
                operation: "file-read*",
                literals: Self.sortedPaths(readableLiteralPaths),
                subpaths: Self.sortedPaths(readablePaths)
            ))
        }

        if capabilities.contains(.filesystemWrite) {
            lines.append(contentsOf: Self.schemeRules(
                operation: "file-write*",
                literals: [],
                subpaths: Self.sortedPaths(writablePaths)
            ))
        }

        if capabilities.contains(.network) {
            lines.append("(allow network-outbound)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func parentDirectoryLiterals(for url: URL) -> [URL] {
        var paths: [String] = []
        var current = url.resolvingSymlinksInPath().standardizedFileURL
        if !current.hasDirectoryPath {
            current.deleteLastPathComponent()
        }

        while true {
            let path = current.path
            paths.append(path)
            if path == "/" { break }
            current.deleteLastPathComponent()
        }

        return paths
            .reversed()
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func sortedPaths(_ urls: [URL]) -> [String] {
        urls
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
    }

    private static func schemeRules(
        operation: String,
        literals: [String],
        subpaths: [String]
    ) -> [String] {
        let literalRules = literals.map {
            #"(allow \#(operation) (literal "\#(schemeString($0))"))"#
        }
        let subpathRules = subpaths.map {
            #"(allow \#(operation) (subpath "\#(schemeString($0))"))"#
        }
        return literalRules + subpathRules
    }

    private static let systemReadBaselineLiteralPaths = [
        "/",
        "/bin",
        "/usr",
        "/System",
        "/Library",
        "/private",
        "/private/var",
        "/private/var/db",
        "/private/var/select",
        "/private/etc",
        "/dev/null",
    ]

    private static let systemReadBaselineSubpaths = [
        "/bin",
        "/usr",
        "/System",
        "/Library",
        "/private/var/db",
        "/private/var/select",
        "/private/etc",
    ]

    private static func schemeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Executor

enum SandboxExecutorError: Error, Equatable {
    case sandboxExecUnavailable(String)
}

struct SandboxExecutionPlan: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let currentDirectoryURL: URL
}

protocol SandboxFileManaging: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
}

extension FileManager: SandboxFileManaging {}

struct SandboxExecutor: Sendable {
    let sandboxExecURL: URL
    let fileManager: any SandboxFileManaging

    init(
        sandboxExecURL: URL = URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
        fileManager: any SandboxFileManaging = FileManager.default
    ) {
        self.sandboxExecURL = sandboxExecURL
        self.fileManager = fileManager
    }

    func launchPlan(
        commandURL: URL,
        arguments: [String],
        profile: String,
        environment: [String: String],
        currentDirectoryURL: URL
    ) throws -> SandboxExecutionPlan {
        guard fileManager.isExecutableFile(atPath: sandboxExecURL.path) else {
            throw SandboxExecutorError.sandboxExecUnavailable(sandboxExecURL.path)
        }

        return SandboxExecutionPlan(
            executableURL: sandboxExecURL,
            arguments: ["-p", profile, commandURL.path] + arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL
        )
    }
}

// MARK: - Audit Log

enum SandboxAuditSubjectKind: String, Codable, Sendable, Equatable {
    case plugin
    case agent
    case mcp
}

enum SandboxAuditDecision: String, Codable, Sendable, Equatable {
    case granted
    case denied
}

struct SandboxAuditEntry: Codable, Sendable, Equatable {
    let timestamp: Date
    let subjectID: String
    let subjectKind: SandboxAuditSubjectKind
    let operation: String
    let capability: SandboxCapability
    let decision: SandboxAuditDecision
    let detail: String
}

final class SandboxAuditLog: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func append(_ entry: SandboxAuditEntry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry) + Data([0x0A])

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }
    }

    func entries() throws -> [SandboxAuditEntry] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents
            .split(separator: "\n")
            .map { line in
                try decoder.decode(SandboxAuditEntry.self, from: Data(line.utf8))
            }
    }
}
