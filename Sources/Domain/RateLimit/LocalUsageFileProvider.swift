// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LocalUsageFileProvider.swift - Shared fail-soft parser for local
// usage ledgers exposed by optional agent CLIs.

import Foundation

struct LocalUsageFileProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind
    let usageFiles: [URL]
    let aggregationWindow: TimeInterval
    let now: @Sendable () -> Date

    init(
        agent: RateLimitSnapshot.AgentKind,
        usageFiles: [URL],
        aggregationWindow: TimeInterval = 60 * 60 * 24,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.agent = agent
        self.usageFiles = usageFiles
        self.aggregationWindow = aggregationWindow
        self.now = now
    }

    func snapshot() async -> RateLimitSnapshot? {
        let agent = agent
        let usageFiles = usageFiles
        let aggregationWindow = aggregationWindow
        let sampleInstant = now()

        return await Task.detached(priority: .utility) {
            for url in usageFiles {
                guard FileManager.default.isReadableFile(atPath: url.path),
                      let contents = try? String(contentsOf: url, encoding: .utf8)
                else {
                    continue
                }
                guard let summary = LocalUsageLedgerParser.summary(
                    from: contents,
                    now: sampleInstant,
                    aggregationWindow: aggregationWindow
                ) else {
                    continue
                }
                return RateLimitSnapshot(
                    agent: agent,
                    usagePercent: summary.limitAmount > 0
                        ? Double(summary.usedAmount) / Double(summary.limitAmount)
                        : 0,
                    usedAmount: summary.usedAmount,
                    limitAmount: summary.limitAmount,
                    unit: summary.unit,
                    updatedAt: sampleInstant
                )
            }
            return nil
        }.value
    }
}

private enum LocalUsageLedgerParser {
    struct Summary: Sendable, Equatable {
        let usedAmount: Int
        let limitAmount: Int
        let unit: RateLimitSnapshot.Unit
    }

    private struct Entry: Sendable, Equatable {
        let timestamp: Date
        let amount: Int
        let limit: Int
        let unit: RateLimitSnapshot.Unit
    }

    static func summary(
        from contents: String,
        now: Date,
        aggregationWindow: TimeInterval
    ) -> Summary? {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entries: [Entry]
        if let jsonEntries = parseJSONEntries(trimmed) {
            entries = jsonEntries
        } else {
            entries = trimmed
                .split(separator: "\n", omittingEmptySubsequences: false)
                .compactMap { parseJSONObjectLine(String($0)) }
        }

        guard !entries.isEmpty else { return nil }
        let cutoff = now.addingTimeInterval(-aggregationWindow)
        let windowEntries = entries.filter { entry in
            entry.timestamp >= cutoff && entry.timestamp <= now && entry.amount >= 0
        }
        guard !windowEntries.isEmpty else { return nil }

        let preferredUnit = preferredUnit(for: windowEntries)
        let matchingEntries = windowEntries.filter { $0.unit == preferredUnit }
        let used = matchingEntries.reduce(0) { $0 + $1.amount }
        guard used > 0 else { return nil }
        let limit = matchingEntries.map(\.limit).filter { $0 > 0 }.max() ?? 0

        return Summary(
            usedAmount: used,
            limitAmount: limit,
            unit: preferredUnit
        )
    }

    private static func parseJSONEntries(_ contents: String) -> [Entry]? {
        guard let data = contents.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if let array = object as? [[String: Any]] {
            return array.compactMap(parseEntry)
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        let nestedKeys = ["entries", "records", "events", "usage"]
        for key in nestedKeys {
            if let array = dictionary[key] as? [[String: Any]] {
                return array.compactMap(parseEntry)
            }
        }
        return parseEntry(dictionary).map { [$0] } ?? []
    }

    private static func parseJSONObjectLine(_ line: String) -> Entry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return parseEntry(object)
    }

    private static func parseEntry(_ object: [String: Any]) -> Entry? {
        guard let amountAndUnit = amountAndUnit(from: object),
              let timestamp = timestamp(from: object) else {
            return nil
        }
        return Entry(
            timestamp: timestamp,
            amount: amountAndUnit.amount,
            limit: limit(from: object, unit: amountAndUnit.unit),
            unit: amountAndUnit.unit
        )
    }

    private static func amountAndUnit(from object: [String: Any]) -> (amount: Int, unit: RateLimitSnapshot.Unit)? {
        if let input = intValue(object["input_tokens"]),
           let output = intValue(object["output_tokens"]) {
            return (input + output, .tokens)
        }
        for key in ["total_tokens", "tokens_used", "token_count", "tokens"] {
            if let value = intValue(object[key]) {
                return (value, .tokens)
            }
        }
        if let value = intValue(object["requests"]) {
            return (value, .requests)
        }
        if let value = intValue(object["messages"]) {
            return (value, .messages)
        }
        return nil
    }

    private static func limit(from object: [String: Any], unit: RateLimitSnapshot.Unit) -> Int {
        let keys: [String]
        switch unit {
        case .tokens:
            keys = ["token_limit", "tokens_limit", "limit", "quota"]
        case .requests:
            keys = ["request_limit", "requests_limit", "limit", "quota"]
        case .messages:
            keys = ["message_limit", "messages_limit", "limit", "quota"]
        }
        for key in keys {
            if let value = intValue(object[key]), value > 0 {
                return value
            }
        }
        return 0
    }

    private static func timestamp(from object: [String: Any]) -> Date? {
        for key in ["timestamp", "updated_at", "created_at", "time"] {
            guard let raw = object[key] else { continue }
            if let epoch = doubleValue(raw) {
                return Date(timeIntervalSince1970: epoch)
            }
            if let string = raw as? String {
                if let epoch = Double(string) {
                    return Date(timeIntervalSince1970: epoch)
                }
                if let date = parseISO8601(string) {
                    return date
                }
            }
        }
        return nil
    }

    private static func preferredUnit(for entries: [Entry]) -> RateLimitSnapshot.Unit {
        let units = Set(entries.map(\.unit))
        if units.contains(.tokens) { return .tokens }
        if units.contains(.requests) { return .requests }
        return .messages
    }

    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as Double where value.isFinite:
            return Int(value)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func doubleValue(_ raw: Any) -> Double? {
        switch raw {
        case let value as Int:
            return Double(value)
        case let value as Double where value.isFinite:
            return value
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
