// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClaudeUsageProvider.swift - Local-only provider that aggregates
// `~/.claude/metrics/costs.jsonl` into a `RateLimitSnapshot`.

import Foundation
import os.log

/// Local-only provider that aggregates Claude Code's cost ledger into
/// a snapshot the rate-limit pill can render.
///
/// ## Data source
///
/// Claude Code persists a JSONL ledger at
/// `~/.claude/metrics/costs.jsonl` with one line per assistant turn:
///
/// ```json
/// {"timestamp":"...","session_id":"...","model":"...",
///  "input_tokens":N,"output_tokens":N,"estimated_cost_usd":N}
/// ```
///
/// The provider reads the file, parses each line tolerantly (blanks
/// and malformed lines are skipped, never raised), filters entries to
/// the polling window, and sums input + output tokens.
///
/// ## Cero telemetría
///
/// Nothing leaves the user's machine. The provider:
///   * reads a single local file the CLI already maintains;
///   * computes the snapshot in-process;
///   * returns `nil` when the file is absent — the pill hides
///     silently so a fresh install never surfaces an error banner.
///
/// ## Soft budget
///
/// Anthropic does not publish a programmatic rate-limit endpoint that
/// is reachable without sending data outbound, so the provider uses a
/// caller-supplied `softTokenBudget` as the denominator. The pill
/// renders the heat band against that value; the tooltip surfaces the
/// raw token count so the user can compare with their plan's actual
/// limits.
struct ClaudeUsageProvider: RateLimitProviding {

    let agent: RateLimitSnapshot.AgentKind = .claude

    /// Path to the JSONL ledger. Defaults to the canonical
    /// `~/.claude/metrics/costs.jsonl` location; tests inject a
    /// temporary fixture path so they never read the user's real data.
    let costsFile: URL

    /// Window over which to aggregate tokens. The pill's heat colour
    /// reflects how much was consumed inside this window. Defaults to
    /// 24 hours so a busy session today does not stay red for the rest
    /// of the week.
    let aggregationWindow: TimeInterval

    /// Caller-supplied soft budget the pill uses as the heat-band
    /// denominator. Tooltip surfaces the raw count so users can sanity
    /// check against their actual plan.
    let softTokenBudget: Int

    /// Default location of Claude Code's local cost ledger.
    static var defaultCostsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/metrics/costs.jsonl")
    }

    init(
        costsFile: URL = ClaudeUsageProvider.defaultCostsFile,
        aggregationWindow: TimeInterval = 60 * 60 * 24,
        softTokenBudget: Int = 1_000_000
    ) {
        self.costsFile = costsFile
        self.aggregationWindow = aggregationWindow
        self.softTokenBudget = softTokenBudget
    }

    // MARK: - RateLimitProviding

    func snapshot() async -> RateLimitSnapshot? {
        guard let contents = try? String(contentsOf: costsFile, encoding: .utf8) else {
            return nil
        }
        let entries = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { Self.parseEntry(String($0)) }
        let now = Date()
        let totalTokens = Self.aggregate(
            entries: entries,
            now: now,
            window: aggregationWindow
        )
        let percent = softTokenBudget > 0
            ? Double(totalTokens) / Double(softTokenBudget)
            : 0
        return RateLimitSnapshot(
            agent: agent,
            usagePercent: percent,
            usedAmount: totalTokens,
            limitAmount: softTokenBudget,
            unit: .tokens,
            updatedAt: now
        )
    }

    // MARK: - Pure helpers

    /// One row of Claude Code's cost ledger.
    struct CostEntry: Sendable, Equatable {
        let timestamp: Date
        let inputTokens: Int
        let outputTokens: Int
    }

    /// Parses one JSONL line into a `CostEntry`. Returns `nil` for
    /// blank lines, malformed JSON, malformed timestamps, or objects
    /// missing the required token fields. Never throws — the caller
    /// can `compactMap` the parser over the file's lines.
    static func parseEntry(_ line: String) -> CostEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        guard let timestampString = object["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampString),
              let inputTokens = object["input_tokens"] as? Int,
              let outputTokens = object["output_tokens"] as? Int
        else {
            return nil
        }
        return CostEntry(
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    /// Sums `inputTokens + outputTokens` across the entries that fall
    /// inside `[now - window, now]`. Entries outside the window are
    /// excluded; entries timestamped in the future are also excluded
    /// so a clock-skewed CLI cannot inflate the pill.
    static func aggregate(
        entries: [CostEntry],
        now: Date,
        window: TimeInterval
    ) -> Int {
        let cutoff = now.addingTimeInterval(-window)
        return entries.reduce(0) { acc, entry in
            guard entry.timestamp >= cutoff,
                  entry.timestamp <= now else {
                return acc
            }
            return acc + entry.inputTokens + entry.outputTokens
        }
    }

    /// Tolerant ISO 8601 parser that accepts the `.000Z` fractional
    /// suffix Claude Code uses, as well as the bare `2026-04-27T10:00:00Z`
    /// form.
    private static func parseTimestamp(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
