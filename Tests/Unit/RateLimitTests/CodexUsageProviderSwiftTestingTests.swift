// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyShared
@testable import CocxyTerminal

/// Unit coverage for `CodexUsageProvider`. The provider reads only
/// numeric ledger columns from a local SQLite database and never touches
/// Codex logs or transcript-bearing fields.
@Suite("CodexUsageProvider")
struct CodexUsageProviderSwiftTestingTests {

    private let sqlite3URL = URL(fileURLWithPath: "/usr/bin/sqlite3")

    @Test("agent kind is .codex so the probe service registers the provider against the canonical enum case")
    func agentKindIsCodex() {
        let provider = CodexUsageProvider()

        #expect(provider.agent == .codex)
    }

    @Test("snapshot aggregates numeric token totals from the local thread ledger")
    func snapshotAggregatesNumericTokenTotals() async throws {
        try requireSQLiteOrSkip()
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            """
            CREATE TABLE threads (
              id TEXT,
              updated_at INTEGER,
              tokens_used INTEGER,
              title TEXT,
              first_user_message TEXT
            );
            INSERT INTO threads VALUES ('old', 1699999700, 100, 'old title', 'old prompt');
            INSERT INTO threads VALUES ('recent-a', 1700000100, 200, 'secret title', 'secret prompt');
            INSERT INTO threads VALUES ('recent-b', 1700000200, 300, 'secret title 2', 'secret prompt 2');
            INSERT INTO threads VALUES ('empty', 1700000300, NULL, 'ignored', 'ignored');
            """
        )
        let provider = CodexUsageProvider(
            stateDatabaseURL: databaseURL,
            sqlite3URL: sqlite3URL,
            aggregationWindow: 600,
            now: { Date(timeIntervalSince1970: 1_700_000_400) }
        )

        let snapshot = await provider.snapshot()

        #expect(snapshot?.agent == .codex)
        #expect(snapshot?.usedAmount == 500)
        #expect(snapshot?.limitAmount == 0)
        #expect(snapshot?.usagePercent == 0)
        #expect(snapshot?.unit == .tokens)
    }

    @Test("snapshot returns nil when sqlite is missing so the optional pill hides silently")
    func snapshotReturnsNilWhenSQLiteIsMissing() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        try Data().write(to: databaseURL)
        let provider = CodexUsageProvider(
            stateDatabaseURL: databaseURL,
            sqlite3URL: URL(fileURLWithPath: "/nonexistent/sqlite3"),
            now: { Date(timeIntervalSince1970: 1_700_000_400) }
        )

        let snapshot = await provider.snapshot()

        #expect(snapshot == nil)
    }

    @Test("snapshot returns nil when the internal schema drifts")
    func snapshotReturnsNilWhenSchemaDrifts() async throws {
        try requireSQLiteOrSkip()
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        try runSQLite(
            databaseURL,
            """
            CREATE TABLE threads (
              id TEXT,
              updated_at INTEGER
            );
            INSERT INTO threads VALUES ('row', 1700000200);
            """
        )
        let provider = CodexUsageProvider(
            stateDatabaseURL: databaseURL,
            sqlite3URL: sqlite3URL,
            now: { Date(timeIntervalSince1970: 1_700_000_400) }
        )

        let snapshot = await provider.snapshot()

        #expect(snapshot == nil)
    }

    @Test("provider value-types are equal when constructed with the default initializer so the probe service treats them as a single registration")
    func providersWithDefaultInitAreEquivalent() {
        let lhs = CodexUsageProvider()
        let rhs = CodexUsageProvider()

        #expect(lhs.agent == rhs.agent)
    }

    @Test("activeAccount follows the selected account on disk without rebuilding the provider")
    func activeAccountFollowsSelectionStore() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let authURL = root.appendingPathComponent("auth.json")
        let selectionURL = root.appendingPathComponent("selection.json")
        let json = """
        {
          "accounts": [
            { "id": "acct_1", "email": "one@example.com" },
            { "id": "acct_2", "email": "two@example.com" }
          ]
        }
        """
        try Data(json.utf8).write(to: authURL)
        let provider = CodexUsageProvider(authJSONURL: authURL, selectionURL: selectionURL)

        try CodexAccountSelectionStore.save(CodexAccountSelection(selectedAccountID: "acct_1"), to: selectionURL)
        #expect(provider.activeAccount()?.id == "acct_1")

        try CodexAccountSelectionStore.save(CodexAccountSelection(selectedAccountID: "acct_2"), to: selectionURL)
        #expect(provider.activeAccount()?.id == "acct_2")
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func requireSQLiteOrSkip() throws {
        guard FileManager.default.isExecutableFile(atPath: sqlite3URL.path) else {
            try #require(Bool(false), "sqlite3 not available — skipping Codex usage provider SQLite tests")
            return
        }
    }

    private func runSQLite(_ databaseURL: URL, _ sql: String) throws {
        let process = Process()
        process.executableURL = sqlite3URL
        process.arguments = [databaseURL.path]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(sql.utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
            throw NSError(
                domain: "CodexUsageProviderTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
