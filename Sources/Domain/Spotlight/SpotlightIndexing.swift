// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SpotlightIndexing.swift - Local macOS Spotlight indexing primitives.

import Foundation

#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

enum SpotlightIndexDomain {
    static let commandHistory = "dev.cocxy.terminal.command-history"
    static let agentConversation = "dev.cocxy.terminal.agent-conversation"
}

struct SpotlightIndexDocument: Equatable, Sendable {
    let uniqueIdentifier: String
    let domainIdentifier: String
    let title: String
    let contentDescription: String
    let keywords: [String]
    let createdAt: Date?
}

protocol SpotlightIndexWriting: Sendable {
    func index(_ documents: [SpotlightIndexDocument]) async throws
}

struct SpotlightIndexScopePolicy: Sendable {
    static let ignoreFileName = ".cocxy-spotlight-ignore"

    private let fileExists: @Sendable (URL) -> Bool

    init(fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.fileExists = fileExists
    }

    func allowsIndexing(in workspaceRoot: URL) -> Bool {
        var current = workspaceRoot.standardizedFileURL
        while true {
            if fileExists(current.appendingPathComponent(Self.ignoreFileName)) {
                return false
            }
            guard current.path != "/" else { break }

            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return true
    }
}

enum SpotlightIndexDocumentBuilder {
    private static let maxCommandCharacters = 512
    private static let maxOutputCharacters = 2_000
    private static let maxMessageCharacters = 2_000

    static func commandHistoryDocuments(
        blocks: [TerminalCommandBlock],
        sessionID: String,
        config: SpotlightIndexConfig
    ) -> [SpotlightIndexDocument] {
        guard config.indexCommandHistory else { return [] }
        let sanitizedSessionID = TerminalBlockStore.sanitizedSessionID(sessionID)

        return blocks.compactMap { block in
            let command = normalized(block.command, limit: maxCommandCharacters)
            guard !command.isEmpty else { return nil }

            var lines = [
                "Command: \(command)",
            ]
            if let exitCode = block.exitCode {
                lines.append("Exit code: \(exitCode)")
            }
            if block.isBookmarked {
                lines.append("Bookmarked: true")
            }
            if config.includeWorkingDirectories, let pwd = normalizedOptional(block.pwd) {
                lines.append("Working directory: \(pwd)")
            }
            if config.includeCommandOutput {
                let output = normalized(block.output, limit: maxOutputCharacters)
                if !output.isEmpty {
                    lines.append("Output: \(output)")
                }
            }

            var keywords = ["cocxy", "terminal", "command-history", "command"]
            if let exitCode = block.exitCode {
                keywords.append("exit-\(exitCode)")
            }
            if block.isBookmarked {
                keywords.append("bookmarked")
            }

            return SpotlightIndexDocument(
                uniqueIdentifier: "cocxy:command-history:\(sanitizedSessionID):\(block.id)",
                domainIdentifier: SpotlightIndexDomain.commandHistory,
                title: "$ \(singleLine(command))",
                contentDescription: lines.joined(separator: "\n"),
                keywords: keywords,
                createdAt: nil
            )
        }
    }

    static func agentConversationDocuments(
        messages: [AgentMessage],
        conversationID: String,
        config: SpotlightIndexConfig
    ) -> [SpotlightIndexDocument] {
        guard config.indexAgentConversations else { return [] }
        let sanitizedConversationID = AgentConversationStore.sanitizedConversationID(conversationID)

        return messages.compactMap { message in
            guard message.role == .user || message.role == .assistant else { return nil }
            let content = normalized(message.content, limit: maxMessageCharacters)
            guard !content.isEmpty else { return nil }

            var lines = [
                "Role: \(message.role.rawValue)",
                "Message: \(content)",
            ]
            if let threadID = normalizedOptional(message.threadID) {
                lines.append("Thread: \(threadID)")
            }
            if config.includeToolMetadata {
                if let toolName = normalizedOptional(message.toolName) {
                    lines.append("Tool: \(toolName)")
                }
                if !message.toolCalls.isEmpty {
                    lines.append("Tool calls: \(message.toolCalls.map(\.toolID).joined(separator: ", "))")
                }
            }

            var keywords = ["cocxy", "agent", "conversation", message.role.rawValue]
            if let threadID = normalizedOptional(message.threadID) {
                keywords.append("thread-\(threadID)")
            }

            return SpotlightIndexDocument(
                uniqueIdentifier: "cocxy:agent-conversation:\(sanitizedConversationID):\(message.id)",
                domainIdentifier: SpotlightIndexDomain.agentConversation,
                title: "Agent \(message.role.rawValue) message",
                contentDescription: lines.joined(separator: "\n"),
                keywords: keywords,
                createdAt: message.createdAt
            )
        }
    }

    private static func normalized(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

enum SpotlightReindexStatus: Sendable, Equatable {
    case disabled
    case blockedByWorkspace
    case indexed
}

struct SpotlightReindexReport: Sendable, Equatable {
    let status: SpotlightReindexStatus
    let documentsIndexed: Int
}

struct CocxySpotlightIndexer {
    let commandStore: TerminalBlockStore
    let conversationStore: AgentConversationStore
    let writer: any SpotlightIndexWriting
    let scopePolicy: SpotlightIndexScopePolicy

    init(
        commandStore: TerminalBlockStore = TerminalBlockStore(),
        conversationStore: AgentConversationStore = AgentConversationStore(),
        writer: any SpotlightIndexWriting = CoreSpotlightIndexWriter(),
        scopePolicy: SpotlightIndexScopePolicy = SpotlightIndexScopePolicy()
    ) {
        self.commandStore = commandStore
        self.conversationStore = conversationStore
        self.writer = writer
        self.scopePolicy = scopePolicy
    }

    func reindexAll(
        config: SpotlightIndexConfig,
        workspaceRoot: URL?
    ) async throws -> SpotlightReindexReport {
        guard config.enabled else {
            return SpotlightReindexReport(status: .disabled, documentsIndexed: 0)
        }
        if let workspaceRoot, !scopePolicy.allowsIndexing(in: workspaceRoot) {
            return SpotlightReindexReport(status: .blockedByWorkspace, documentsIndexed: 0)
        }

        var documents: [SpotlightIndexDocument] = []
        if config.indexCommandHistory {
            for sessionID in try commandStore.sessionIDs() {
                documents.append(contentsOf: SpotlightIndexDocumentBuilder.commandHistoryDocuments(
                    blocks: try commandStore.load(sessionID: sessionID),
                    sessionID: sessionID,
                    config: config
                ))
            }
        }
        if config.indexAgentConversations {
            for conversationID in try conversationStore.conversationIDs() {
                documents.append(contentsOf: SpotlightIndexDocumentBuilder.agentConversationDocuments(
                    messages: try conversationStore.load(conversationID: conversationID),
                    conversationID: conversationID,
                    config: config
                ))
            }
        }

        if !documents.isEmpty {
            try await writer.index(documents)
        }
        return SpotlightReindexReport(status: .indexed, documentsIndexed: documents.count)
    }
}

enum SpotlightIncrementalIndexer {
    static func indexCommandBlock(
        _ block: TerminalCommandBlock,
        sessionID: String,
        config: SpotlightIndexConfig,
        writer: any SpotlightIndexWriting = CoreSpotlightIndexWriter(),
        scopePolicy: SpotlightIndexScopePolicy = SpotlightIndexScopePolicy()
    ) async throws -> SpotlightReindexReport {
        guard config.enabled else {
            return SpotlightReindexReport(status: .disabled, documentsIndexed: 0)
        }
        if let pwd = block.pwd, !pwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let workspaceRoot = URL(fileURLWithPath: pwd)
            guard scopePolicy.allowsIndexing(in: workspaceRoot) else {
                return SpotlightReindexReport(status: .blockedByWorkspace, documentsIndexed: 0)
            }
        }

        let documents = SpotlightIndexDocumentBuilder.commandHistoryDocuments(
            blocks: [block],
            sessionID: sessionID,
            config: config
        )
        if !documents.isEmpty {
            try await writer.index(documents)
        }
        return SpotlightReindexReport(status: .indexed, documentsIndexed: documents.count)
    }

    static func indexAgentMessage(
        _ message: AgentMessage,
        conversationID: String,
        workspaceRoot: URL?,
        config: SpotlightIndexConfig,
        writer: any SpotlightIndexWriting = CoreSpotlightIndexWriter(),
        scopePolicy: SpotlightIndexScopePolicy = SpotlightIndexScopePolicy()
    ) async throws -> SpotlightReindexReport {
        guard config.enabled else {
            return SpotlightReindexReport(status: .disabled, documentsIndexed: 0)
        }
        if let workspaceRoot, !scopePolicy.allowsIndexing(in: workspaceRoot) {
            return SpotlightReindexReport(status: .blockedByWorkspace, documentsIndexed: 0)
        }

        let documents = SpotlightIndexDocumentBuilder.agentConversationDocuments(
            messages: [message],
            conversationID: conversationID,
            config: config
        )
        if !documents.isEmpty {
            try await writer.index(documents)
        }
        return SpotlightReindexReport(status: .indexed, documentsIndexed: documents.count)
    }
}

struct SpotlightIndexingAgentConversationRecorder: AgentConversationRecording {
    let base: any AgentConversationRecording
    let conversationID: String
    let workspaceRoot: URL?
    let config: SpotlightIndexConfig
    let writer: any SpotlightIndexWriting
    let scopePolicy: SpotlightIndexScopePolicy

    init(
        base: any AgentConversationRecording,
        conversationID: String,
        workspaceRoot: URL?,
        config: SpotlightIndexConfig,
        writer: any SpotlightIndexWriting = CoreSpotlightIndexWriter(),
        scopePolicy: SpotlightIndexScopePolicy = SpotlightIndexScopePolicy()
    ) {
        self.base = base
        self.conversationID = conversationID
        self.workspaceRoot = workspaceRoot
        self.config = config
        self.writer = writer
        self.scopePolicy = scopePolicy
    }

    func append(_ message: AgentMessage, conversationID: String) throws {
        try base.append(message, conversationID: conversationID)
        guard config.enabled, conversationID == self.conversationID else { return }

        let workspaceRoot = self.workspaceRoot
        let config = self.config
        let writer = self.writer
        let scopePolicy = self.scopePolicy
        Task.detached(priority: .utility) {
            _ = try? await SpotlightIncrementalIndexer.indexAgentMessage(
                message,
                conversationID: conversationID,
                workspaceRoot: workspaceRoot,
                config: config,
                writer: writer,
                scopePolicy: scopePolicy
            )
        }
    }
}

#if canImport(CoreSpotlight)
final class CoreSpotlightIndexWriter: SpotlightIndexWriting, @unchecked Sendable {
    private let index: CSSearchableIndex

    init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    func index(_ documents: [SpotlightIndexDocument]) async throws {
        let items = documents.map(Self.searchableItem)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func searchableItem(from document: SpotlightIndexDocument) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)
        attributeSet.title = document.title
        attributeSet.contentDescription = document.contentDescription
        attributeSet.keywords = document.keywords
        attributeSet.contentCreationDate = document.createdAt
        return CSSearchableItem(
            uniqueIdentifier: document.uniqueIdentifier,
            domainIdentifier: document.domainIdentifier,
            attributeSet: attributeSet
        )
    }
}
#else
struct CoreSpotlightIndexWriter: SpotlightIndexWriting {
    func index(_ documents: [SpotlightIndexDocument]) async throws {}
}
#endif
