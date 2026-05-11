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
        executablePaths: [URL]
    ) -> String {
        var lines = [
            "(version 1)",
            "(deny default)",
            "(allow process-fork)",
        ]

        if capabilities.contains(.processExec) {
            for path in Self.sortedPaths(executablePaths) {
                lines.append(#"(allow process-exec (literal "\#(Self.schemeString(path))"))"#)
            }
        }

        if capabilities.contains(.filesystemRead) {
            for path in Self.sortedPaths(readablePaths) {
                lines.append(#"(allow file-read* (subpath "\#(Self.schemeString(path))"))"#)
            }
        }

        if capabilities.contains(.filesystemWrite) {
            for path in Self.sortedPaths(writablePaths) {
                lines.append(#"(allow file-write* (subpath "\#(Self.schemeString(path))"))"#)
            }
        }

        if capabilities.contains(.network) {
            lines.append("(allow network-outbound)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func sortedPaths(_ urls: [URL]) -> [String] {
        urls
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
    }

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
