// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSearchIndexSwiftTestingTests.swift - Full-text search coverage for Vault.

import Foundation
import Testing
@testable import CocxyVault

@Suite("Vault search index")
struct VaultSearchIndexSwiftTestingTests {

    @Test("indexSession and search return ranked highlighted matches")
    func indexSessionAndSearchReturnRankedHighlightedMatches() throws {
        let index = try makeIndex()
        let session = makeSession(
            id: "codex:paste-fix",
            agentID: "codex",
            displayName: "Codex",
            sessionID: "paste-fix",
            workingDirectory: "/tmp/cocxy-terminal",
            arguments: ["codex", "resume", "paste-fix", "bracketed", "paste", "ordering"],
            lastSeenAt: Date(timeIntervalSince1970: 200)
        )

        try index.indexSession(session)
        let results = try index.search(query: "bracketed paste", filters: .init())

        #expect(results.map(\.session.id) == ["codex:paste-fix"])
        #expect(results[0].relevanceScore > 0)
        #expect(results[0].highlights.contains { highlight in
            highlight.snippet.localizedCaseInsensitiveContains("bracketed")
                && highlight.length > 0
        })
    }

    @Test("removeSession deletes indexed content")
    func removeSessionDeletesIndexedContent() throws {
        let index = try makeIndex()
        let session = makeSession(
            id: "claude:delete-me",
            agentID: "claude",
            displayName: "Claude",
            sessionID: "delete-me",
            arguments: ["claude", "--resume", "delete-me", "temporary", "draft"]
        )

        try index.indexSession(session)
        #expect(try index.search(query: "temporary", filters: .init()).count == 1)

        try index.removeSession(id: session.id)

        #expect(try index.search(query: "temporary", filters: .init()).isEmpty)
    }

    @Test("search applies agent date pinned and workspace filters")
    func searchAppliesFilters() throws {
        let index = try makeIndex()
        let oldCodex = makeSession(
            id: "codex:old",
            agentID: "codex",
            displayName: "Codex",
            sessionID: "old",
            workingDirectory: "/tmp/cocxy-terminal",
            arguments: ["codex", "resume", "old", "vault", "visual"],
            lastSeenAt: Date(timeIntervalSince1970: 100)
        )
        let freshClaude = makeSession(
            id: "claude:fresh",
            agentID: "claude",
            displayName: "Claude",
            sessionID: "fresh",
            workingDirectory: "/tmp/other-project",
            arguments: ["claude", "--resume", "fresh", "vault", "visual"],
            lastSeenAt: Date(timeIntervalSince1970: 300)
        )
        let freshCodex = makeSession(
            id: "codex:fresh",
            agentID: "codex",
            displayName: "Codex",
            sessionID: "fresh",
            workingDirectory: "/tmp/cocxy-terminal",
            arguments: ["codex", "resume", "fresh", "vault", "visual"],
            lastSeenAt: Date(timeIntervalSince1970: 400)
        )
        try index.rebuild(sessions: [oldCodex, freshClaude, freshCodex])

        let results = try index.search(
            query: "vault",
            filters: VaultSearchFilters(
                agentIDs: [VaultAgentID("codex")],
                since: Date(timeIntervalSince1970: 150),
                pinnedOnly: true,
                pinnedSessionIDs: ["codex:fresh"],
                workspacePath: "/tmp/cocxy-terminal"
            )
        )

        #expect(results.map(\.session.id) == ["codex:fresh"])
    }

    @Test("rebuild reloads encrypted content from disk")
    func rebuildReloadsEncryptedContentFromDisk() throws {
        let directory = try temporaryDirectory()
        let indexURL = directory.appendingPathComponent("vault-search.sqlite")
        let keyProvider = StaticVaultKeyProvider(keyData: Data(repeating: 5, count: 32))
        let first = try VaultSearchIndex(indexURL: indexURL, keyProvider: keyProvider)
        let session = makeSession(
            id: "qoder:reload",
            agentID: "qoder",
            displayName: "Qoder",
            sessionID: "reload",
            arguments: ["qoder", "resume", "reload", "persistent", "search"]
        )

        try first.indexSession(session)
        let second = try VaultSearchIndex(indexURL: indexURL, keyProvider: keyProvider)
        try second.rebuild()

        #expect(try second.search(query: "persistent", filters: .init()).map(\.session.id) == ["qoder:reload"])
    }

    @Test("index file is encrypted at rest and mode 0600")
    func indexFileIsEncryptedAtRestAndMode0600() throws {
        let directory = try temporaryDirectory()
        let indexURL = directory.appendingPathComponent("vault-search.sqlite")
        let index = try VaultSearchIndex(
            indexURL: indexURL,
            keyProvider: StaticVaultKeyProvider(keyData: Data(repeating: 6, count: 32))
        )
        let session = makeSession(
            id: "codex:secret",
            agentID: "codex",
            displayName: "Codex",
            sessionID: "secret-session",
            workingDirectory: "/tmp/private-project",
            arguments: ["codex", "resume", "secret-session", "confidential", "token"]
        )

        try index.indexSession(session)

        let raw = try Data(contentsOf: indexURL)
        let rawText = String(decoding: raw, as: UTF8.self)
        #expect(!rawText.contains("secret-session"))
        #expect(!rawText.contains("confidential"))

        let attrs = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        let mode = try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o777
        #expect(mode == 0o600)
    }

    @Test("search handles 1000 sessions within an interactive budget")
    func searchHandlesThousandSessionsWithinInteractiveBudget() throws {
        let index = try makeIndex()
        let sessions = (0..<1_000).map { value in
            makeSession(
                id: "codex:bulk-\(value)",
                agentID: "codex",
                displayName: "Codex",
                sessionID: "bulk-\(value)",
                workingDirectory: value.isMultiple(of: 2) ? "/tmp/cocxy-terminal" : "/tmp/other",
                arguments: ["codex", "resume", "bulk-\(value)", value == 777 ? "needle" : "haystack"],
                lastSeenAt: Date(timeIntervalSince1970: TimeInterval(value))
            )
        }

        let start = Date()
        try index.rebuild(sessions: sessions)
        let results = try index.search(query: "needle", filters: .init())
        let elapsed = Date().timeIntervalSince(start)

        #expect(results.map(\.session.id) == ["codex:bulk-777"])
        #expect(elapsed < 5)
    }

    private func makeIndex() throws -> VaultSearchIndex {
        try VaultSearchIndex(
            indexURL: temporaryDirectory().appendingPathComponent("vault-search.sqlite"),
            keyProvider: StaticVaultKeyProvider(keyData: Data(repeating: 4, count: 32))
        )
    }

    private func makeSession(
        id: String,
        agentID: VaultAgentID,
        displayName: String,
        sessionID: String,
        workingDirectory: String? = nil,
        arguments: [String] = [],
        lastSeenAt: Date = Date(timeIntervalSince1970: 100)
    ) -> VaultSession {
        VaultSession(
            id: id,
            agentID: agentID,
            agentDisplayName: displayName,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            capturedAt: Date(timeIntervalSince1970: 50),
            lastSeenAt: lastSeenAt,
            source: .manual,
            sanitizedArguments: arguments
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-vault-search-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
