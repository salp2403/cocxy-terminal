// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityQuery.swift - Local aggregation over activity and usage records.

import Foundation

struct ActivityQueryService {
    private let store: ActivityStoring
    private let calendar: Calendar

    init(
        store: ActivityStoring,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.store = store
        self.calendar = calendar
    }

    func eventCounts(matching query: ActivityStoreQuery = ActivityStoreQuery()) throws -> [ActivityEventCount] {
        let events = try store.events(matching: query)
        let grouped = Dictionary(grouping: events, by: \.kind)
        return grouped
            .map { ActivityEventCount(kind: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in lhs.kind.rawValue < rhs.kind.rawValue }
    }

    func tokenUsageByDay(
        matching query: ActivityStoreQuery = ActivityStoreQuery()
    ) throws -> [TokenUsageBucket] {
        let records = try store.tokenUsage(matching: query)
        let grouped = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.timestamp)
        }
        return grouped
            .map { day, records in
                TokenUsageBucket(
                    day: day,
                    inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                    outputTokens: records.reduce(0) { $0 + $1.outputTokens },
                    totalCostMicros: records.reduce(0) { $0 + $1.estimatedCostMicros }
                )
            }
            .sorted { lhs, rhs in lhs.day < rhs.day }
    }

    func costBreakdown(
        matching query: ActivityStoreQuery = ActivityStoreQuery()
    ) throws -> [CostBreakdown] {
        let records = try store.tokenUsage(matching: query)
        let grouped = Dictionary(grouping: records) {
            CostBreakdownKey(provider: $0.provider, model: $0.model)
        }
        return grouped.values
            .compactMap { records in
                guard let first = records.first else { return nil }
                return CostBreakdown(
                    provider: first.provider,
                    model: first.model,
                    inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                    outputTokens: records.reduce(0) { $0 + $1.outputTokens },
                    totalCostMicros: records.reduce(0) { $0 + $1.estimatedCostMicros }
                )
            }
            .sorted { lhs, rhs in
                if lhs.provider == rhs.provider {
                    return lhs.model < rhs.model
                }
                return lhs.provider < rhs.provider
            }
    }

    func productivityInsights(
        matching query: ActivityStoreQuery = ActivityStoreQuery()
    ) throws -> ProductivityInsights {
        let events = try store.events(matching: query)
        let commands = events.filter { $0.kind == .commandExecuted }
        let commandCounts = Dictionary(grouping: commands, by: \.summary)
            .mapValues(\.count)
        let mostUsedCommands = commandCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(5)
            .map(\.key)

        let hourCounts = Dictionary(grouping: events) { event in
            calendar.component(.hour, from: event.timestamp)
        }.mapValues(\.count)
        let peakHour = hourCounts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }.first?.key

        return ProductivityInsights(
            mostUsedCommands: Array(mostUsedCommands),
            peakHour: peakHour,
            projectSwitches: events.filter { $0.kind == .projectSwitched }.count
        )
    }
}

private struct CostBreakdownKey: Hashable {
    let provider: String
    let model: String
}
