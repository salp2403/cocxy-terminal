// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SpotlightIndexerSwiftTestingTests.swift - Local Spotlight indexing contract tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cocxy Spotlight indexer")
struct SpotlightIndexerSwiftTestingTests {

    @Test("command history documents omit output and working directory by default")
    func commandDocumentsOmitSensitiveFieldsByDefault() {
        let block = commandBlock(
            command: "git status --short",
            output: "M Sources/App.swift\n",
            pwd: "/Users/example/private-project"
        )
        let documents = SpotlightIndexDocumentBuilder.commandHistoryDocuments(
            blocks: [block],
            sessionID: "tab/one",
            config: .defaults
        )

        #expect(documents.count == 1)
        let document = documents[0]
        #expect(document.uniqueIdentifier == "cocxy:command-history:tab-one:42")
        #expect(document.domainIdentifier == SpotlightIndexDomain.commandHistory)
        #expect(document.title == "$ git status --short")
        #expect(document.contentDescription.contains("git status --short"))
        #expect(document.contentDescription.contains("M Sources/App.swift") == false)
        #expect(document.contentDescription.contains("/Users/example") == false)
        #expect(document.keywords.contains("command-history"))
    }

    @Test("command history documents include explicit opt-in fields only when enabled")
    func commandDocumentsHonorExplicitSensitiveOptIns() {
        let config = SpotlightIndexConfig(
            enabled: true,
            indexCommandHistory: true,
            indexAgentConversations: true,
            includeCommandOutput: true,
            includeWorkingDirectories: true,
            includeToolMetadata: false
        )
        let block = commandBlock(
            command: "swift test",
            output: "Build complete\n",
            pwd: "/Users/example/project"
        )

        let documents = SpotlightIndexDocumentBuilder.commandHistoryDocuments(
            blocks: [block],
            sessionID: "session",
            config: config
        )

        #expect(documents[0].contentDescription.contains("Build complete"))
        #expect(documents[0].contentDescription.contains("/Users/example/project"))
    }

    @Test("agent conversation documents index user and assistant text without tools or attachments")
    func agentDocumentsSkipToolAndAttachmentMetadataByDefault() {
        let user = AgentMessage(
            id: "user-1",
            role: .user,
            content: "Summarize the failing test",
            threadID: "main"
        )
        let assistant = AgentMessage(
            id: "assistant-1",
            role: .assistant,
            content: "The failure is in the parser.",
            toolName: "read_file",
            toolCalls: [
                AgentToolCall(id: "tool-1", toolID: "read_file", arguments: ["path": .string("/private/file")]),
            ],
            imageAttachments: [
                AgentImageAttachment(
                    id: "image-1",
                    displayName: "screenshot.png",
                    mimeType: "image/png",
                    filePath: "/Users/example/private/screenshot.png",
                    byteCount: 12,
                    pixelWidth: 1,
                    pixelHeight: 1
                ),
            ],
            threadID: "main"
        )
        let tool = AgentMessage(
            id: "tool-1",
            role: .tool,
            content: "{\"path\":\"/private/file\"}",
            toolName: "read_file"
        )

        let documents = SpotlightIndexDocumentBuilder.agentConversationDocuments(
            messages: [user, assistant, tool],
            conversationID: "conversation/one",
            config: .defaults
        )

        #expect(documents.map(\.uniqueIdentifier) == [
            "cocxy:agent-conversation:conversation-one:user-1",
            "cocxy:agent-conversation:conversation-one:assistant-1",
        ])
        #expect(documents.allSatisfy { $0.domainIdentifier == SpotlightIndexDomain.agentConversation })
        #expect(documents[0].contentDescription.contains("Summarize the failing test"))
        #expect(documents[1].contentDescription.contains("The failure is in the parser."))
        #expect(documents[1].contentDescription.contains("read_file") == false)
        #expect(documents[1].contentDescription.contains("/private/file") == false)
        #expect(documents[1].contentDescription.contains("screenshot.png") == false)
    }

    @Test(".cocxy-spotlight-ignore disables broad local indexing for that workspace root")
    func ignoreMarkerDisablesBroadIndexing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = SpotlightIndexScopePolicy()

        #expect(policy.allowsIndexing(in: root) == true)

        try Data().write(to: root.appendingPathComponent(SpotlightIndexScopePolicy.ignoreFileName))

        #expect(policy.allowsIndexing(in: root) == false)
    }

    @Test(".cocxy-spotlight-ignore applies to nested command directories")
    func ignoreMarkerAppliesToNestedCommandDirectories() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(SpotlightIndexScopePolicy.ignoreFileName))

        #expect(SpotlightIndexScopePolicy().allowsIndexing(in: nested) == false)
    }

    @Test("local reindex is a no-op while Spotlight is disabled")
    func disabledReindexDoesNotWriteDocuments() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let commandStore = TerminalBlockStore(rootDirectory: root.appendingPathComponent("blocks"))
        let conversationStore = AgentConversationStore(rootDirectory: root.appendingPathComponent("conversations"))
        try commandStore.append(commandBlock(command: "pwd"), sessionID: "tab-1")
        try conversationStore.append(
            AgentMessage(id: "user-1", role: .user, content: "Hello"),
            conversationID: "conv-1"
        )
        let writer = RecordingSpotlightIndexWriter()
        let indexer = CocxySpotlightIndexer(
            commandStore: commandStore,
            conversationStore: conversationStore,
            writer: writer
        )

        let report = try await indexer.reindexAll(config: .defaults, workspaceRoot: root)

        #expect(report.status == .disabled)
        #expect(report.documentsIndexed == 0)
        #expect(await writer.documents.isEmpty)
    }

    @Test("local reindex writes command and conversation documents when explicitly enabled")
    func enabledReindexWritesCommandAndConversationDocuments() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let commandStore = TerminalBlockStore(rootDirectory: root.appendingPathComponent("blocks"))
        let conversationStore = AgentConversationStore(rootDirectory: root.appendingPathComponent("conversations"))
        try commandStore.append(commandBlock(command: "git log --oneline"), sessionID: "tab-1")
        try conversationStore.append(
            AgentMessage(id: "user-1", role: .user, content: "Review this"),
            conversationID: "conv-1"
        )
        let writer = RecordingSpotlightIndexWriter()
        let indexer = CocxySpotlightIndexer(
            commandStore: commandStore,
            conversationStore: conversationStore,
            writer: writer
        )

        let report = try await indexer.reindexAll(
            config: SpotlightIndexConfig(enabled: true),
            workspaceRoot: root
        )
        let documents = await writer.documents

        #expect(report.status == .indexed)
        #expect(report.documentsIndexed == 2)
        #expect(Set(documents.map(\.domainIdentifier)) == [
            SpotlightIndexDomain.commandHistory,
            SpotlightIndexDomain.agentConversation,
        ])
    }

    @Test("incremental command indexing respects the disabled master switch")
    func incrementalCommandIndexingRespectsDisabledConfig() async throws {
        let writer = RecordingSpotlightIndexWriter()

        let report = try await SpotlightIncrementalIndexer.indexCommandBlock(
            commandBlock(command: "pwd"),
            sessionID: "tab-1",
            config: .defaults,
            writer: writer
        )

        #expect(report.status == .disabled)
        #expect(await writer.documents.isEmpty)
    }

    @Test("incremental command indexing honors workspace ignore markers")
    func incrementalCommandIndexingHonorsWorkspaceIgnore() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent(SpotlightIndexScopePolicy.ignoreFileName))
        let writer = RecordingSpotlightIndexWriter()

        let report = try await SpotlightIncrementalIndexer.indexCommandBlock(
            commandBlock(command: "pwd", pwd: root.path),
            sessionID: "tab-1",
            config: SpotlightIndexConfig(enabled: true),
            writer: writer
        )

        #expect(report.status == .blockedByWorkspace)
        #expect(await writer.documents.isEmpty)
    }

    @Test("incremental agent indexing writes only conversation documents")
    func incrementalAgentIndexingWritesConversationDocuments() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = RecordingSpotlightIndexWriter()

        let report = try await SpotlightIncrementalIndexer.indexAgentMessage(
            AgentMessage(id: "user-1", role: .user, content: "Searchable local prompt"),
            conversationID: "conv-1",
            workspaceRoot: root,
            config: SpotlightIndexConfig(enabled: true),
            writer: writer
        )
        let documents = await writer.documents

        #expect(report.status == .indexed)
        #expect(report.documentsIndexed == 1)
        #expect(documents.map(\.domainIdentifier) == [SpotlightIndexDomain.agentConversation])
    }

    private func commandBlock(
        id: UInt64 = 42,
        command: String,
        output: String = "",
        pwd: String? = nil
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            command: command,
            output: output,
            exitCode: 0,
            pwd: pwd,
            startTimeNs: 100,
            endTimeNs: 200,
            durationNs: 100,
            startRow: 1,
            endRow: 2,
            streamID: 0,
            blockType: 1
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-spotlight-indexer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor RecordingSpotlightIndexWriter: SpotlightIndexWriting {
    private(set) var documents: [SpotlightIndexDocument] = []

    func index(_ documents: [SpotlightIndexDocument]) async throws {
        self.documents.append(contentsOf: documents)
    }
}
