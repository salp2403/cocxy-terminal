// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodexUsageProvider.swift - Local-only provider that aggregates the
// Codex CLI's local thread ledger without reading transcripts.

import CocxyShared
import Foundation

/// Local-only `RateLimitProviding` implementation for Codex CLI.
///
/// ## Data source
///
/// The Codex CLI keeps local runtime state in `~/.codex/state_5.sqlite`.
/// The database is not a documented quota API, so this provider uses it
/// only as a best-effort local activity estimate:
///
///   * reads only `threads.tokens_used` and `threads.updated_at`;
///   * never reads `title`, `first_user_message`, logs, or transcripts;
///   * filters to a rolling time window so stale sessions fade out;
///   * returns `nil` if the database or `sqlite3` CLI is missing, if the
///     schema changed, or if the query fails.
///
/// Because this is not an authoritative account quota surface, the
/// returned `RateLimitSnapshot` sets `limitAmount` to zero. The UI shows
/// it as a local usage estimate rather than a percent of a real plan
/// limit.
///
/// ## When to update this provider
///
/// When the CLI ships a documented, programmatic, locally-reachable
/// quota surface, the provider implementation can change in place
/// without touching the wiring in `MainWindowController`. The closed
/// `RateLimitSnapshot` value type is already shared across providers,
/// so a future implementation only needs to:
///
///   1. Read the new local surface (file or local socket).
///   2. Aggregate values inside the polling window.
///   3. Return a `RateLimitSnapshot(agent: .codex, ...)`.
struct CodexUsageProvider: RateLimitProviding {

    /// Agent the provider tracks. Always `.codex` so the probe service
    /// can dispatch by agent without inspecting the snapshot.
    let agent: RateLimitSnapshot.AgentKind = .codex

    private let authJSONURL: URL
    private let selectionURL: URL
    private let stateDatabaseURL: URL
    private let sqlite3URL: URL
    private let aggregationWindow: TimeInterval
    private let now: @Sendable () -> Date

    /// Default location of Codex CLI's local thread ledger.
    static var defaultStateDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
    }

    /// Reads the selected Codex account at refresh time so account
    /// switches made from the command palette are reflected without
    /// restarting Cocxy. The current local SQLite schema does not expose
    /// a stable account foreign key, so the snapshot is an all-local
    /// Codex activity estimate rather than account-scoped billing data.
    init(
        authJSONURL: URL = CodexAccountScanner.defaultAuthJSONURL(),
        selectionURL: URL = CodexAccountSelectionStore.defaultSelectionURL(),
        stateDatabaseURL: URL = CodexUsageProvider.defaultStateDatabaseURL,
        sqlite3URL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        aggregationWindow: TimeInterval = 60 * 60 * 24,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.authJSONURL = authJSONURL
        self.selectionURL = selectionURL
        self.stateDatabaseURL = stateDatabaseURL
        self.sqlite3URL = sqlite3URL
        self.aggregationWindow = aggregationWindow
        self.now = now
    }

    // MARK: - RateLimitProviding

    /// Returns a local usage estimate from Codex's thread ledger.
    /// Missing files, missing `sqlite3`, schema drift, or query failures
    /// all collapse to `nil` so the pill hides silently instead of
    /// surfacing a scary banner for an optional indicator.
    func snapshot() async -> RateLimitSnapshot? {
        _ = activeAccount()
        let stateDatabaseURL = stateDatabaseURL
        let sqlite3URL = sqlite3URL
        let aggregationWindow = aggregationWindow
        let sampleInstant = now()

        return await Task.detached(priority: .utility) {
            guard FileManager.default.isReadableFile(atPath: stateDatabaseURL.path),
                  FileManager.default.isExecutableFile(atPath: sqlite3URL.path)
            else {
                return nil
            }

            let cutoff = Int(sampleInstant.addingTimeInterval(-aggregationWindow).timeIntervalSince1970.rounded(.down))
            guard let totalTokens = Self.queryTokenTotal(
                sqlite3URL: sqlite3URL,
                databaseURL: stateDatabaseURL,
                cutoffEpochSeconds: cutoff
            ) else {
                return nil
            }

            return RateLimitSnapshot(
                agent: .codex,
                usagePercent: 0,
                usedAmount: totalTokens,
                limitAmount: 0,
                unit: .tokens,
                updatedAt: sampleInstant
            )
        }.value
    }

    /// Resolves the account Cocxy should scope future Codex usage data
    /// to. The lookup intentionally reads from disk every time so the
    /// command-palette hot-swap path takes effect in the next refresh
    /// without rebuilding providers or restarting the app.
    func activeAccount() -> CodexAccount? {
        let accounts = CodexAccountScanner.accounts(authJSONURL: authJSONURL)
        let selectedID = CodexAccountSelectionStore.load(from: selectionURL).selectedAccountID

        if let selectedID,
           let selected = accounts.first(where: { $0.id == selectedID }) {
            return selected
        }
        if accounts.count == 1 {
            return accounts[0]
        }
        return nil
    }

    // MARK: - SQLite ledger query

    /// Aggregates only numeric columns from the local thread ledger.
    /// The SQL intentionally avoids transcript-bearing columns so this
    /// provider never reads prompt text while computing the status-bar
    /// estimate.
    static func queryTokenTotal(
        sqlite3URL: URL,
        databaseURL: URL,
        cutoffEpochSeconds: Int,
        timeoutSeconds: TimeInterval = 1.5
    ) -> Int? {
        let query = """
        SELECT COALESCE(SUM(tokens_used), 0)
        FROM threads
        WHERE tokens_used IS NOT NULL
          AND updated_at >= \(cutoffEpochSeconds);
        """

        let process = Process()
        process.executableURL = sqlite3URL
        process.arguments = [
            "-readonly",
            "-batch",
            "-noheader",
            databaseURL.path,
            query,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let completion = DispatchGroup()
        completion.enter()
        process.terminationHandler = { _ in completion.leave() }

        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            return nil
        }

        if completion.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 0.2)
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let total = Int(value), total >= 0 else { return nil }
        return total
    }
}
