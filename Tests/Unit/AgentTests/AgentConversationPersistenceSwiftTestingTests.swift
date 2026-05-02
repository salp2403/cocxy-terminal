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
            toolCallID: "tool-1"
        )

        let line = try AgentMessageSerializer.encodeLine(message)
        let decoded = try AgentMessageSerializer.decodeLine(line)

        #expect(line.hasSuffix("\n"))
        #expect(decoded == message)
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

    private func sampleMessage(
        id: String,
        role: AgentMessageRole,
        content: String,
        toolName: String? = nil,
        toolCallID: String? = nil
    ) -> AgentMessage {
        AgentMessage(
            id: id,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_776_000_000),
            toolName: toolName,
            toolCallID: toolCallID
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
}
