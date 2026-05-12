// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultModels.swift - External agent session vault domain models.

import Foundation

public struct VaultAgentID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct VaultAgent: Codable, Equatable, Sendable {
    public let id: VaultAgentID
    public let displayName: String
    public let binaryNames: [String]
    public let resumeArgumentsTemplate: [String]

    public init(
        id: VaultAgentID,
        displayName: String,
        binaryNames: [String],
        resumeArgumentsTemplate: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.binaryNames = binaryNames
        self.resumeArgumentsTemplate = resumeArgumentsTemplate
    }

    public var primaryBinaryName: String {
        binaryNames.first ?? id.rawValue
    }
}

public enum VaultSessionSource: String, Codable, Equatable, Sendable {
    case manual
    case processSnapshot
    case fileSnapshot
}

public struct VaultSession: Codable, Equatable, Sendable {
    public let id: String
    public let agentID: VaultAgentID
    public let agentDisplayName: String
    public let sessionID: String
    public let workingDirectory: String?
    public let capturedAt: Date
    public let lastSeenAt: Date
    public let source: VaultSessionSource
    public let sanitizedArguments: [String]

    public init(
        id: String,
        agentID: VaultAgentID,
        agentDisplayName: String,
        sessionID: String,
        workingDirectory: String?,
        capturedAt: Date,
        lastSeenAt: Date,
        source: VaultSessionSource,
        sanitizedArguments: [String]
    ) {
        self.id = id
        self.agentID = agentID
        self.agentDisplayName = agentDisplayName
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.capturedAt = capturedAt
        self.lastSeenAt = lastSeenAt
        self.source = source
        self.sanitizedArguments = sanitizedArguments
    }
}

public struct VaultProcessSnapshot: Codable, Equatable, Sendable {
    public let pid: Int32
    public let executableName: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(
        pid: Int32,
        executableName: String,
        arguments: [String],
        workingDirectory: String?
    ) {
        self.pid = pid
        self.executableName = executableName
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct VaultResumeInvocation: Codable, Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executable: String, arguments: [String], workingDirectory: String?) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct VaultResumeResult: Codable, Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum VaultError: LocalizedError, Equatable {
    case unknownAgent(String)
    case emptySessionID
    case invalidKeyLength(Int)
    case corruptStore
    case invalidResumeTemplate(String)

    public var errorDescription: String? {
        switch self {
        case .unknownAgent(let agent):
            return "Unknown vault agent: \(agent)"
        case .emptySessionID:
            return "Session id cannot be empty"
        case .invalidKeyLength(let length):
            return "Vault key must be 32 bytes, got \(length)"
        case .corruptStore:
            return "Vault store is corrupt or cannot be decrypted"
        case .invalidResumeTemplate(let agent):
            return "Agent \(agent) has an invalid resume template"
        }
    }
}
