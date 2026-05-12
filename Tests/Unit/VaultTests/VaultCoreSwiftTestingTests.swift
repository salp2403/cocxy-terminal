// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultCoreSwiftTestingTests.swift - External agent session vault coverage.

import Foundation
import Testing
@testable import CocxyVault

@Suite("Vault core")
struct VaultCoreSwiftTestingTests {

    @Test("built-in registry covers supported external agents")
    func builtInRegistryCoversSupportedExternalAgents() throws {
        let registry = VaultAgentRegistry.builtIn
        let ids = Set(registry.agents.map(\.id.rawValue))

        #expect(ids == [
            "claude",
            "codex",
            "opencode",
            "pi",
            "cursor",
            "gemini",
            "rovo",
            "copilot",
            "codebuddy",
            "factory",
            "qoder",
        ])
    }

    @Test("detector extracts session id and redacts sensitive argv")
    func detectorExtractsSessionIDAndRedactsSensitiveArgv() throws {
        let detector = VaultSessionDetector(
            registry: .builtIn,
            clock: { Date(timeIntervalSince1970: 1_789_000_000) }
        )
        let snapshot = VaultProcessSnapshot(
            pid: 42,
            executableName: "codex",
            arguments: [
                "codex",
                "resume",
                "sess_123",
                "--api-key",
                "secret-value",
                "--prompt=private text",
            ],
            workingDirectory: "/tmp/workspace"
        )

        let session = try #require(detector.detect(from: snapshot))

        #expect(session.agentID.rawValue == "codex")
        #expect(session.sessionID == "sess_123")
        #expect(session.workingDirectory == "/tmp/workspace")
        #expect(!session.sanitizedArguments.contains("secret-value"))
        #expect(!session.sanitizedArguments.contains("--prompt=private text"))
        #expect(session.sanitizedArguments.contains("<redacted>"))
    }

    @Test("store persists encrypted sessions without clear text leakage")
    func storePersistsEncryptedSessionsWithoutClearTextLeakage() throws {
        let directory = try temporaryDirectory()
        let storageURL = directory.appendingPathComponent("vault.enc")
        let store = VaultSessionStore(
            storageURL: storageURL,
            keyProvider: StaticVaultKeyProvider(keyData: Data(repeating: 7, count: 32))
        )
        let session = VaultSession(
            id: "codex:sess-secret",
            agentID: VaultAgentID("codex"),
            agentDisplayName: "Codex",
            sessionID: "sess-secret",
            workingDirectory: "/tmp/workspace",
            capturedAt: Date(timeIntervalSince1970: 1_789_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_789_000_100),
            source: .processSnapshot,
            sanitizedArguments: ["codex", "resume", "sess-secret"]
        )

        try store.upsert(session)

        let raw = try Data(contentsOf: storageURL)
        #expect(!String(decoding: raw, as: UTF8.self).contains("sess-secret"))

        let loaded = try store.loadSessions()
        #expect(loaded == [session])
    }

    @Test("resumer plans argv without shell interpolation")
    func resumerPlansArgvWithoutShellInterpolation() throws {
        let registry = VaultAgentRegistry.builtIn
        let agent = try #require(registry.agent(matching: "codex"))
        let session = VaultSession(
            id: "codex:sess-123",
            agentID: agent.id,
            agentDisplayName: agent.displayName,
            sessionID: "sess-123; rm -rf /",
            workingDirectory: "/tmp/workspace",
            capturedAt: Date(timeIntervalSince1970: 1_789_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_789_000_100),
            source: .manual,
            sanitizedArguments: []
        )

        let invocation = try VaultSessionResumer.plan(agent: agent, session: session)

        #expect(invocation.executable == "codex")
        #expect(invocation.arguments == ["resume", "sess-123; rm -rf /"])
        #expect(invocation.workingDirectory == "/tmp/workspace")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
