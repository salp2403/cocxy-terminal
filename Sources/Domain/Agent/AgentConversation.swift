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
    let toolCalls: [AgentToolCall]
    let imageAttachments: [AgentImageAttachment]
    let threadID: String?
    let parentMessageID: String?

    init(
        id: String,
        role: AgentMessageRole,
        content: String,
        createdAt: Date = Date(),
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [AgentToolCall] = [],
        imageAttachments: [AgentImageAttachment] = [],
        threadID: String? = nil,
        parentMessageID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.imageAttachments = imageAttachments
        self.threadID = Self.normalizedOptionalString(threadID)
        self.parentMessageID = Self.normalizedOptionalString(parentMessageID)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case toolName
        case toolCallID
        case toolCalls
        case imageAttachments
        case threadID
        case parentMessageID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.role = try container.decode(AgentMessageRole.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        self.toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        self.toolCalls = try container.decodeIfPresent([AgentToolCall].self, forKey: .toolCalls) ?? []
        self.imageAttachments = try container.decodeIfPresent(
            [AgentImageAttachment].self,
            forKey: .imageAttachments
        ) ?? []
        self.threadID = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .threadID)
        )
        self.parentMessageID = Self.normalizedOptionalString(
            try container.decodeIfPresent(String.self, forKey: .parentMessageID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        if !toolCalls.isEmpty {
            try container.encode(toolCalls, forKey: .toolCalls)
        }
        if !imageAttachments.isEmpty {
            try container.encode(imageAttachments, forKey: .imageAttachments)
        }
        try container.encodeIfPresent(threadID, forKey: .threadID)
        try container.encodeIfPresent(parentMessageID, forKey: .parentMessageID)
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

extension JSONEncoder {
    static var agentConversation: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var agentConversation: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

enum AgentConversationExportFormat: Sendable, Equatable {
    case json
    case markdown
}

enum AgentConversationExporter {
    static func export(_ messages: [AgentMessage], format: AgentConversationExportFormat) throws -> Data {
        switch format {
        case .json:
            return try JSONEncoder.agentConversation.encode(messages)
        case .markdown:
            return Data(markdown(from: messages).utf8)
        }
    }

    static func export(
        conversationID: String,
        from store: AgentConversationStore,
        format: AgentConversationExportFormat
    ) throws -> Data {
        try export(try store.load(conversationID: conversationID), format: format)
    }

    private static func markdown(from messages: [AgentMessage]) -> String {
        var lines = ["# Agent Conversation", ""]
        let grouped = Dictionary(grouping: messages) { message in
            message.threadID ?? "default"
        }

        for threadID in grouped.keys.sorted() {
            lines.append("## Thread: \(threadID)")
            lines.append("")
            let threadMessages = grouped[threadID, default: []].sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
            for message in threadMessages {
                lines.append("### \(message.role.rawValue.capitalized)")
                lines.append("")
                lines.append("- ID: \(message.id)")
                lines.append("- Created: \(iso8601String(from: message.createdAt))")
                if let parentMessageID = message.parentMessageID {
                    lines.append("- Parent: \(parentMessageID)")
                }
                if let toolName = message.toolName {
                    lines.append("- Tool: \(toolName)")
                }
                if let toolCallID = message.toolCallID {
                    lines.append("- Tool call: \(toolCallID)")
                }
                lines.append("")
                lines.append(message.content)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Append-only JSONL persistence for local Agent Mode conversations.
struct AgentConversationStore {
    let rootDirectory: URL
    private let fileManager: FileManager
    private let lineCodec: AgentConversationLineCodec

    init(
        rootDirectory: URL = AgentConversationStore.defaultRootDirectory(),
        fileManager: FileManager = .default,
        lineCodec: AgentConversationLineCodec = .plaintext
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.lineCodec = lineCodec
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent/conversations", isDirectory: true)
    }

    func append(_ message: AgentMessage, conversationID: String) throws {
        try ensureRootDirectory()
        let fileURL = fileURL(forConversationID: conversationID)
        let data = try lineCodec.encodeLine(message)

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
                try? lineCodec.decodeLine(String(line))
            }
    }

    func load(conversationID: String, threadID: String) throws -> [AgentMessage] {
        try load(conversationID: conversationID).filter { $0.threadID == threadID }
    }

    func threadIDs(conversationID: String) throws -> [String] {
        Array(Set(try load(conversationID: conversationID).compactMap(\.threadID))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func conversationIDs() throws -> [String] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            guard url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
        .sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
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
