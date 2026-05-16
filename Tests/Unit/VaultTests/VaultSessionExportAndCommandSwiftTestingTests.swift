// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionExportAndCommandSwiftTestingTests.swift - Export and resume command coverage.

import Foundation
import Testing
@testable import CocxyVault

@Suite("Vault export and command rendering")
struct VaultSessionExportAndCommandSwiftTestingTests {
    @Test("export formatter emits JSON with stable fields")
    func exportFormatterEmitsJSON() throws {
        let session = makeSession()

        let data = try VaultSessionExportFormatter.data(for: session, format: .json)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["id"] as? String == "codex:sess-quote")
        #expect(object["agentID"] as? String == "codex")
        #expect(object["workingDirectory"] as? String == "/tmp/cocxy")
    }

    @Test("export formatter emits markdown text and bulk JSON")
    func exportFormatterEmitsMarkdownTextAndBulkJSON() throws {
        let first = makeSession(id: "codex:sess-quote", sessionID: "sess-quote")
        let second = makeSession(id: "claude:sess-456", sessionID: "sess-456")

        let markdown = String(
            decoding: try VaultSessionExportFormatter.data(for: first, format: .markdown),
            as: UTF8.self
        )
        let text = String(
            decoding: try VaultSessionExportFormatter.data(for: first, format: .text),
            as: UTF8.self
        )
        let bulk = try VaultSessionExportFormatter.data(for: [first, second], format: .json)
        let objects = try #require(JSONSerialization.jsonObject(with: bulk) as? [[String: Any]])

        #expect(markdown.contains("# Vault Session"))
        #expect(text.contains("Vault Session"))
        #expect(VaultSessionExportFormatter.suggestedFilename(for: first, format: .text).hasSuffix(".txt"))
        #expect(VaultSessionExportFormatter.suggestedFilename(for: [first, second], format: .markdown).hasSuffix(".md"))
        #expect(objects.count == 2)
    }

    @Test("shell renderer single-quotes every component")
    func shellRendererQuotesEveryComponent() {
        let invocation = VaultResumeInvocation(
            executable: "codex",
            arguments: ["resume", "sess ' quoted"],
            workingDirectory: nil
        )

        #expect(VaultShellCommandRenderer.command(for: invocation) == "'codex' 'resume' 'sess '\\'' quoted'")
        #expect(VaultShellCommandRenderer.commandLine(for: invocation).hasSuffix("\r"))
    }

    private func makeSession(
        id: String = "codex:sess-quote",
        sessionID: String = "sess-quote"
    ) -> VaultSession {
        VaultSession(
            id: id,
            agentID: VaultAgentID("codex"),
            agentDisplayName: "Codex",
            sessionID: sessionID,
            workingDirectory: "/tmp/cocxy",
            capturedAt: Date(timeIntervalSince1970: 100),
            lastSeenAt: Date(timeIntervalSince1970: 200),
            source: .manual,
            sanitizedArguments: ["codex", "resume", "sess-quote"]
        )
    }
}
