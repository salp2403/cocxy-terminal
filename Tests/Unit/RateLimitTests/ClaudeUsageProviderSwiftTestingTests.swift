// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `ClaudeUsageProvider`, the local-only provider
/// that aggregates `~/.claude/metrics/costs.jsonl` into a snapshot the
/// status-bar pill can render.
///
/// Three families of tests pin the contract:
///
///   1. The pure `parseEntry(_:)` parser that turns one JSONL line
///      into a typed cost entry — tolerates blanks, malformed JSON,
///      and missing keys without crashing the caller.
///   2. The pure `aggregate(entries:now:window:)` helper that filters
///      entries to the polling window and sums the token columns.
///   3. The end-to-end `snapshot()` method that reads a fixture file,
///      delegates to the helpers, and returns a typed
///      `RateLimitSnapshot` (or `nil` for missing files).
///
/// Tests deliberately inject the fixture file path so they stay
/// deterministic and never touch the user's real `~/.claude/`
/// directory.
@Suite("ClaudeUsageProvider")
struct ClaudeUsageProviderSwiftTestingTests {

    // MARK: - parseEntry

    @Test("a fully populated cost entry parses every numeric field through")
    func parseEntryProducesTypedEntry() {
        let line = #"{"timestamp":"2026-04-27T10:00:00.000Z","session_id":"abc","model":"claude-opus-4-7","input_tokens":1234,"output_tokens":567,"estimated_cost_usd":0.42}"#

        let entry = ClaudeUsageProvider.parseEntry(line)

        #expect(entry != nil)
        #expect(entry?.inputTokens == 1234)
        #expect(entry?.outputTokens == 567)
        #expect(entry?.timestamp == ISO8601DateFormatter().date(from: "2026-04-27T10:00:00Z"))
    }

    @Test("a blank line returns nil so empty separators in the JSONL file do not crash the parser")
    func parseEntryBlankLineIsNil() {
        #expect(ClaudeUsageProvider.parseEntry("") == nil)
        #expect(ClaudeUsageProvider.parseEntry("   ") == nil)
    }

    @Test("a malformed JSON line returns nil instead of throwing")
    func parseEntryMalformedJSONIsNil() {
        #expect(ClaudeUsageProvider.parseEntry("{not json}") == nil)
        #expect(ClaudeUsageProvider.parseEntry("{\"timestamp\":") == nil)
    }

    @Test("a JSON object missing required fields returns nil — the decoder is tolerant, not lenient")
    func parseEntryMissingFieldsIsNil() {
        // No timestamp:
        #expect(ClaudeUsageProvider.parseEntry(#"{"input_tokens":1,"output_tokens":2}"#) == nil)
        // No tokens at all:
        #expect(ClaudeUsageProvider.parseEntry(#"{"timestamp":"2026-04-27T10:00:00Z"}"#) == nil)
    }

    @Test("a malformed timestamp returns nil so the aggregator never sees an invalid Date")
    func parseEntryMalformedTimestampIsNil() {
        let line = #"{"timestamp":"not-a-date","input_tokens":1,"output_tokens":2}"#

        #expect(ClaudeUsageProvider.parseEntry(line) == nil)
    }

    // MARK: - aggregate

    @Test("aggregate returns zero when the entry list is empty")
    func aggregateEmptyArrayIsZero() {
        let total = ClaudeUsageProvider.aggregate(
            entries: [],
            now: Date(timeIntervalSince1970: 1_750_000_000),
            window: 3600
        )
        #expect(total == 0)
    }

    @Test("aggregate sums input and output tokens for entries inside the window")
    func aggregateInsideWindowSumsTokens() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let entries = [
            ClaudeUsageProvider.CostEntry(
                timestamp: now.addingTimeInterval(-300), // 5 min ago
                inputTokens: 100,
                outputTokens: 50
            ),
            ClaudeUsageProvider.CostEntry(
                timestamp: now.addingTimeInterval(-1800), // 30 min ago
                inputTokens: 200,
                outputTokens: 75
            ),
        ]

        let total = ClaudeUsageProvider.aggregate(
            entries: entries,
            now: now,
            window: 3600 // 1 hour
        )

        #expect(total == 100 + 50 + 200 + 75)
    }

    @Test("aggregate skips entries older than the window so stale data does not pollute the pill")
    func aggregateOutsideWindowIsExcluded() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let entries = [
            // Inside:
            ClaudeUsageProvider.CostEntry(
                timestamp: now.addingTimeInterval(-300),
                inputTokens: 100,
                outputTokens: 50
            ),
            // Outside (older than the window):
            ClaudeUsageProvider.CostEntry(
                timestamp: now.addingTimeInterval(-7200), // 2 hours ago
                inputTokens: 999,
                outputTokens: 999
            ),
        ]

        let total = ClaudeUsageProvider.aggregate(
            entries: entries,
            now: now,
            window: 3600
        )

        #expect(total == 100 + 50)
    }

    @Test("aggregate skips entries timestamped in the future so a clock-skewed CLI cannot inflate usage")
    func aggregateFutureEntriesAreExcluded() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let entries = [
            ClaudeUsageProvider.CostEntry(
                timestamp: now.addingTimeInterval(60),
                inputTokens: 999,
                outputTokens: 999
            ),
            ClaudeUsageProvider.CostEntry(
                timestamp: now.addingTimeInterval(-300),
                inputTokens: 10,
                outputTokens: 5
            ),
        ]

        let total = ClaudeUsageProvider.aggregate(
            entries: entries,
            now: now,
            window: 3600
        )

        #expect(total == 10 + 5)
    }

    // MARK: - snapshot (integration with a fixture file)

    @Test("snapshot returns nil when the costs file is missing — the pill must hide silently")
    func snapshotReturnsNilWhenFileMissing() async {
        let path = URL(fileURLWithPath: "/tmp/cocxy-rate-limit-tests/non-existent-\(UUID().uuidString).jsonl")
        let provider = ClaudeUsageProvider(
            costsFile: path,
            aggregationWindow: 3600,
            softTokenBudget: 1_000_000
        )

        let snapshot = await provider.snapshot()

        #expect(snapshot == nil)
    }

    @Test("snapshot aggregates a real-shaped fixture and exposes the typed values for the tooltip")
    func snapshotAggregatesFixtureAndProducesTypedValues() async throws {
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        let recentISO = isoFormatter.string(from: now.addingTimeInterval(-60))
        let staleISO = isoFormatter.string(from: now.addingTimeInterval(-7200))
        let lines = [
            #"{"timestamp":"\#(recentISO)","session_id":"a","model":"opus","input_tokens":1000,"output_tokens":500,"estimated_cost_usd":0.1}"#,
            "  ",
            "{not json}",
            #"{"timestamp":"\#(staleISO)","session_id":"b","model":"opus","input_tokens":9999,"output_tokens":9999,"estimated_cost_usd":1.0}"#,
            #"{"timestamp":"\#(recentISO)","session_id":"c","model":"sonnet","input_tokens":250,"output_tokens":125,"estimated_cost_usd":0.05}"#,
        ]
        let fixture = try writeFixture(lines: lines)

        let provider = ClaudeUsageProvider(
            costsFile: fixture,
            aggregationWindow: 3600,
            softTokenBudget: 10_000
        )

        let snapshot = try #require(await provider.snapshot())
        #expect(snapshot.agent == .claude)
        #expect(snapshot.unit == .tokens)
        #expect(snapshot.usedAmount == 1000 + 500 + 250 + 125) // 1875
        #expect(snapshot.limitAmount == 10_000)
        #expect(abs(snapshot.usagePercent - 0.1875) < 0.0001)
    }

    @Test("snapshot returns a zero-percent snapshot when the file exists but has no entries in window")
    func snapshotReturnsZeroForEmptyButValidFile() async throws {
        let fixture = try writeFixture(lines: [])

        let provider = ClaudeUsageProvider(
            costsFile: fixture,
            aggregationWindow: 3600,
            softTokenBudget: 10_000
        )

        let snapshot = try #require(await provider.snapshot())
        #expect(snapshot.usedAmount == 0)
        #expect(snapshot.usagePercent == 0.0)
    }

    // MARK: - Fixture helpers

    private func writeFixture(lines: [String]) throws -> URL {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cocxy-rate-limit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        let fixture = tmpDir.appendingPathComponent("costs.jsonl")
        try lines.joined(separator: "\n").write(
            to: fixture,
            atomically: true,
            encoding: .utf8
        )
        return fixture
    }
}
