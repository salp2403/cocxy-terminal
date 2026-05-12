// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIVaultCommandSwiftTestingTests.swift - CLI coverage for external agent vault.

import Foundation
import Testing
@testable import CocxyCLILib
@testable import CocxyVault

@Suite("CLI vault commands")
struct CLIVaultCommandSwiftTestingTests {

    @Test("vault commands parse without app socket")
    func vaultCommandsParseWithoutAppSocket() throws {
        #expect(try CLIArgumentParser.parse(["vault", "list"]) == .vaultList)
        #expect(try CLIArgumentParser.parse(["vault", "clear"]) == .vaultClear)
        #expect(
            try CLIArgumentParser.parse(["vault", "resume", "codex", "sess-123", "--dry-run"])
                == .vaultResume(agent: "codex", sessionID: "sess-123", dryRun: true)
        )
    }

    @Test("vault list returns encrypted store sessions without app socket")
    func vaultListReturnsEncryptedStoreSessionsWithoutAppSocket() throws {
        let directory = try temporaryDirectory()
        let store = VaultSessionStore(
            storageURL: directory.appendingPathComponent("vault.enc"),
            keyProvider: StaticVaultKeyProvider(keyData: Data(repeating: 8, count: 32))
        )
        try store.upsert(
            VaultSession(
                id: "codex:sess-123",
                agentID: VaultAgentID("codex"),
                agentDisplayName: "Codex",
                sessionID: "sess-123",
                workingDirectory: "/tmp/workspace",
                capturedAt: Date(timeIntervalSince1970: 1_789_000_000),
                lastSeenAt: Date(timeIntervalSince1970: 1_789_000_100),
                source: .manual,
                sanitizedArguments: ["codex", "resume", "sess-123"]
            )
        )
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/missing-cocxy.sock"),
            vaultStore: store
        )

        let result = runner.run(arguments: ["vault", "list"])

        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        let object = try jsonObject(from: result.stdout)
        let sessions = try #require(object["sessions"] as? [[String: Any]])
        #expect(sessions.count == 1)
        #expect(sessions[0]["agentID"] as? String == "codex")
        #expect(sessions[0]["sessionID"] as? String == "sess-123")
    }

    @Test("vault resume dry-run returns planned invocation")
    func vaultResumeDryRunReturnsPlannedInvocation() throws {
        let directory = try temporaryDirectory()
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/missing-cocxy.sock"),
            vaultStore: VaultSessionStore(
                storageURL: directory.appendingPathComponent("vault.enc"),
                keyProvider: StaticVaultKeyProvider(keyData: Data(repeating: 9, count: 32))
            )
        )

        let result = runner.run(arguments: ["vault", "resume", "codex", "sess-123", "--dry-run"])

        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        let object = try jsonObject(from: result.stdout)
        #expect(object["dryRun"] as? Bool == true)
        #expect(object["executable"] as? String == "codex")
        #expect(object["arguments"] as? [String] == ["resume", "sess-123"])
    }

    @Test("help advertises vault commands")
    func helpAdvertisesVaultCommands() {
        let help = CLIArgumentParser.helpText()

        #expect(help.contains("cocxy vault list"))
        #expect(help.contains("cocxy vault resume <agent> <session-id>"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cli-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func jsonObject(from text: String) throws -> [String: Any] {
        let data = Data(text.utf8)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
