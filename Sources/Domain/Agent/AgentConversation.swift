// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConversation.swift - Local Agent Mode conversation records.

import Foundation

enum AgentMessageRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

/// Append-only message record for a built-in Agent Mode conversation.
struct AgentMessage: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let role: AgentMessageRole
    let content: String
    let createdAt: Date
    let toolName: String?
    let toolCallID: String?

    init(
        id: String,
        role: AgentMessageRole,
        content: String,
        createdAt: Date = Date(),
        toolName: String? = nil,
        toolCallID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolName = toolName
        self.toolCallID = toolCallID
    }
}

enum AgentMessageSerializer {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func encodeLine(_ message: AgentMessage) throws -> String {
        let data = try encoder.encode(message)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return json + "\n"
    }

    static func decodeLine(_ line: String) throws -> AgentMessage {
        try decoder.decode(AgentMessage.self, from: Data(line.utf8))
    }
}

/// Append-only JSONL persistence for local Agent Mode conversations.
struct AgentConversationStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = AgentConversationStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent/conversations", isDirectory: true)
    }

    func append(_ message: AgentMessage, conversationID: String) throws {
        try ensureRootDirectory()
        let line = try AgentMessageSerializer.encodeLine(message)
        let fileURL = fileURL(forConversationID: conversationID)
        let data = Data(line.utf8)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }

        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func load(conversationID: String) throws -> [AgentMessage] {
        let fileURL = fileURL(forConversationID: conversationID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? AgentMessageSerializer.decodeLine(String(line))
            }
    }

    func fileURL(forConversationID conversationID: String) -> URL {
        rootDirectory.appendingPathComponent("\(Self.sanitizedConversationID(conversationID)).jsonl")
    }

    static func sanitizedConversationID(_ conversationID: String) -> String {
        var output = ""
        var previousWasSeparator = false

        for scalar in conversationID.unicodeScalars {
            let value = scalar.value
            let isAllowed = (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || scalar == "-"
                || scalar == "_"

            if isAllowed {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func ensureRootDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }

        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )
    }
}
