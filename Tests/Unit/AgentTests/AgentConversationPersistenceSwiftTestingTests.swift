// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConversationPersistenceSwiftTestingTests.swift - Local JSONL conversation persistence.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent conversation persistence")
struct AgentConversationPersistenceSwiftTestingTests {

    @Test("JSONL serializer round-trips an agent message")
    func jsonlSerializerRoundTripsAgentMessage() throws {
        let message = sampleMessage(
            id: "msg-1",
            role: .assistant,
            content: "Use `swift test` next.",
            toolName: "grep",
            toolCallID: "tool-1",
            toolCalls: [
                AgentToolCall(
                    id: "tool-1",
                    toolID: "grep",
                    arguments: ["pattern": .string("AgentLoop")]
                ),
            ]
        )

        let line = try AgentMessageSerializer.encodeLine(message)
        let decoded = try AgentMessageSerializer.decodeLine(line)

        #expect(line.hasSuffix("\n"))
        #expect(decoded == message)
    }

    @Test("JSONL serializer round-trips thread metadata")
    func jsonlSerializerRoundTripsThreadMetadata() throws {
        let message = AgentMessage(
            id: "msg-2",
            role: .assistant,
            content: "Continuing the focused thread.",
            createdAt: Date(timeIntervalSince1970: 1_776_000_010),
            threadID: "review-thread",
            parentMessageID: "msg-1"
        )

        let line = try AgentMessageSerializer.encodeLine(message)
        let decoded = try AgentMessageSerializer.decodeLine(line)

        #expect(decoded.threadID == "review-thread")
        #expect(decoded.parentMessageID == "msg-1")
        #expect(decoded == message)
    }

    @Test("legacy JSONL messages decode with empty tool calls")
    func legacyJSONLMessagesDecodeWithEmptyToolCalls() throws {
        let decoded = try AgentMessageSerializer.decodeLine("""
        {"content":"Hello","createdAt":1776000000,"id":"legacy","role":"assistant"}
        """)

        #expect(decoded.toolCalls.isEmpty)
        #expect(decoded.content == "Hello")
        #expect(decoded.threadID == nil)
        #expect(decoded.parentMessageID == nil)
    }

    @Test("legacy JSONL empty thread metadata decodes as nil")
    func legacyJSONLEmptyThreadMetadataDecodesAsNil() throws {
        let decoded = try AgentMessageSerializer.decodeLine("""
        {"content":"Hello","createdAt":1776000000,"id":"legacy","parentMessageID":" ","role":"assistant","threadID":""}
        """)

        #expect(decoded.threadID == nil)
        #expect(decoded.parentMessageID == nil)
    }

    @Test("store appends and loads messages for one conversation")
    func storeAppendsAndLoadsMessages() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentConversationStore(rootDirectory: root)

        try store.append(sampleMessage(id: "msg-1", role: .user, content: "Review this file"), conversationID: "conv-1")
        try store.append(sampleMessage(id: "msg-2", role: .assistant, content: "I will inspect it"), conversationID: "conv-1")

        #expect(try store.load(conversationID: "conv-1").map(\.content) == [
            "Review this file",
            "I will inspect it",
        ])
    }

    @Test("store skips corrupt JSONL lines without losing valid messages")
    func storeSkipsCorruptJSONLLines() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentConversationStore(rootDirectory: root)
        let message = sampleMessage(id: "msg-good", role: .assistant, content: "Still valid")
        let fileURL = store.fileURL(forConversationID: "conv")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let content = "not-json\n" + (try AgentMessageSerializer.encodeLine(message))
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(try store.load(conversationID: "conv") == [message])
    }

    @Test("store filters messages by thread")
    func storeFiltersMessagesByThread() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentConversationStore(rootDirectory: root)
        let main = AgentMessage(
            id: "main-1",
            role: .user,
            content: "Main question",
            createdAt: Date(timeIntervalSince1970: 1_776_000_000),
            threadID: "main"
        )
        let review = AgentMessage(
            id: "review-1",
            role: .assistant,
            content: "Review detail",
            createdAt: Date(timeIntervalSince1970: 1_776_000_010),
            threadID: "review"
        )

        try store.append(main, conversationID: "conv")
        try store.append(review, conversationID: "conv")

        #expect(try store.load(conversationID: "conv", threadID: "main") == [main])
        #expect(try store.threadIDs(conversationID: "conv") == ["main", "review"])
    }

    @Test("conversation filenames are sanitized before persistence")
    func conversationFilenamesAreSanitized() {
        let root = URL(fileURLWithPath: "/tmp/cocxy-agent-conversation-test")
        let store = AgentConversationStore(rootDirectory: root)

        #expect(store.fileURL(forConversationID: "agent/one:danger uuid").lastPathComponent == "agent-one-danger-uuid.jsonl")
        #expect(store.fileURL(forConversationID: "").lastPathComponent == "default.jsonl")
    }

    @Test("store creates owner-only directory and file permissions")
    func storeCreatesOwnerOnlyPermissions() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentConversationStore(rootDirectory: root)

        try store.append(sampleMessage(id: "msg-1", role: .user, content: "secret prompt"), conversationID: "conv")

        let rootPermissions = try permissions(at: root)
        let filePermissions = try permissions(at: store.fileURL(forConversationID: "conv"))
        #expect(rootPermissions == 0o700)
        #expect(filePermissions == 0o600)
    }

    @Test("encrypted store round-trips messages without plaintext on disk")
    func encryptedStoreRoundTripsWithoutPlaintextOnDisk() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codec = try AgentConversationLineCodec.encrypted(
            passphrase: "local-master-password",
            saltGenerator: { Self.fixedSalt() }
        )
        let store = AgentConversationStore(rootDirectory: root, lineCodec: codec)
        let message = sampleMessage(
            id: "msg-secret",
            role: .user,
            content: "secret prompt with local context",
            toolCalls: [
                AgentToolCall(
                    id: "tool-1",
                    toolID: "read_file",
                    arguments: ["path": .string("Sources/App.swift")]
                ),
            ]
        )

        try store.append(message, conversationID: "encrypted")

        let raw = try String(contentsOf: store.fileURL(forConversationID: "encrypted"), encoding: .utf8)
        #expect(raw.hasPrefix(AgentConversationEncryptionCodec.linePrefix))
        #expect(!raw.contains("secret prompt"))
        #expect(!raw.contains("read_file"))
        #expect(try store.load(conversationID: "encrypted") == [message])
    }

    @Test("encrypted store skips unreadable lines without exposing other messages")
    func encryptedStoreSkipsUnreadableLines() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codec = try AgentConversationLineCodec.encrypted(
            passphrase: "local-master-password",
            saltGenerator: { Self.fixedSalt() }
        )
        let store = AgentConversationStore(rootDirectory: root, lineCodec: codec)
        let message = sampleMessage(id: "msg-good", role: .assistant, content: "Valid encrypted reply")

        try store.append(message, conversationID: "encrypted")
        let fileURL = store.fileURL(forConversationID: "encrypted")
        let validContent = try String(contentsOf: fileURL, encoding: .utf8)
        try "\(AgentConversationEncryptionCodec.linePrefix)not-base64\n\(validContent)"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(try store.load(conversationID: "encrypted") == [message])
    }

    @Test("encrypted store requires the same passphrase to load")
    func encryptedStoreRequiresSamePassphraseToLoad() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writeCodec = try AgentConversationLineCodec.encrypted(
            passphrase: "local-master-password",
            saltGenerator: { Self.fixedSalt() }
        )
        let readCodec = try AgentConversationLineCodec.encrypted(
            passphrase: "different-password",
            saltGenerator: { Self.fixedSalt() }
        )
        let writeStore = AgentConversationStore(rootDirectory: root, lineCodec: writeCodec)
        let readStore = AgentConversationStore(rootDirectory: root, lineCodec: readCodec)

        try writeStore.append(
            sampleMessage(id: "msg-1", role: .user, content: "private prompt"),
            conversationID: "encrypted"
        )

        #expect(try readStore.load(conversationID: "encrypted").isEmpty)
    }

    @Test("encrypted codec default salt generator round-trips unique envelopes")
    func encryptedCodecDefaultSaltGeneratorRoundTripsUniqueEnvelopes() throws {
        let codec = try AgentConversationLineCodec.encrypted(passphrase: "local-master-password")
        let message = sampleMessage(id: "msg-1", role: .assistant, content: "private reply")

        let firstLine = try #require(String(data: codec.encodeLine(message), encoding: .utf8))
        let secondLine = try #require(String(data: codec.encodeLine(message), encoding: .utf8))

        #expect(firstLine.hasPrefix(AgentConversationEncryptionCodec.linePrefix))
        #expect(secondLine.hasPrefix(AgentConversationEncryptionCodec.linePrefix))
        #expect(firstLine != secondLine)
        #expect(
            try codec.decodeLine(firstLine.trimmingCharacters(in: .newlines)) == message
        )
        #expect(
            try codec.decodeLine(secondLine.trimmingCharacters(in: .newlines)) == message
        )
    }

    @Test("encrypted codec rejects empty passphrases")
    func encryptedCodecRejectsEmptyPassphrases() {
        #expect(throws: AgentConversationEncryptionError.emptyPassphrase) {
            try AgentConversationLineCodec.encrypted(passphrase: "")
        }
    }

    @Test("encrypted codec rejects invalid salt generator output")
    func encryptedCodecRejectsInvalidSaltGeneratorOutput() throws {
        let codec = try AgentConversationLineCodec.encrypted(
            passphrase: "local-master-password",
            saltGenerator: { Data([0x01, 0x02]) }
        )

        #expect(throws: AgentConversationEncryptionError.invalidSaltLength) {
            try codec.encodeLine(sampleMessage(id: "msg-1", role: .user, content: "private prompt"))
        }
    }

    @Test("conversation exporter writes JSON and Markdown without remote services")
    func conversationExporterWritesJSONAndMarkdown() throws {
        let messages = [
            AgentMessage(
                id: "u1",
                role: .user,
                content: "Review this change",
                createdAt: Date(timeIntervalSince1970: 1_776_000_000),
                threadID: "review"
            ),
            AgentMessage(
                id: "a1",
                role: .assistant,
                content: "I found one risk.",
                createdAt: Date(timeIntervalSince1970: 1_776_000_060),
                threadID: "review",
                parentMessageID: "u1"
            ),
        ]

        let jsonData = try AgentConversationExporter.export(messages, format: .json)
        let decoded = try JSONDecoder.agentConversation.decode([AgentMessage].self, from: jsonData)
        let markdown = try #require(String(
            data: AgentConversationExporter.export(messages, format: .markdown),
            encoding: .utf8
        ))

        #expect(decoded == messages)
        #expect(markdown.contains("# Agent Conversation"))
        #expect(markdown.contains("## Thread: review"))
        #expect(markdown.contains("### User"))
        #expect(markdown.contains("Review this change"))
        #expect(markdown.contains("Parent: u1"))
    }

    private func sampleMessage(
        id: String,
        role: AgentMessageRole,
        content: String,
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [AgentToolCall] = []
    ) -> AgentMessage {
        AgentMessage(
            id: id,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_776_000_000),
            toolName: toolName,
            toolCallID: toolCallID,
            toolCalls: toolCalls
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-conversations-\(UUID().uuidString)", isDirectory: true)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }

    private static func fixedSalt() -> Data {
        Data((0..<AgentConversationEncryptionCodec.saltByteCount).map { UInt8($0) })
    }
}
