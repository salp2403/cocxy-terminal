// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityExporter.swift - Manual JSON/CSV export for local activity data.

import Foundation

struct ActivityExportSnapshot: Codable, Sendable, Equatable {
    let exportedAt: Date
    let events: [ActivityEvent]
    let tokenUsage: [TokenUsageRecord]

    init(
        exportedAt: Date = Date(),
        events: [ActivityEvent],
        tokenUsage: [TokenUsageRecord]
    ) {
        self.exportedAt = exportedAt
        self.events = events
        self.tokenUsage = tokenUsage
    }
}

enum ActivityExporter {
    static func exportJSON(_ snapshot: ActivityExportSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func exportEventsCSV(_ events: [ActivityEvent]) -> String {
        var rows = ["timestamp,id,kind,session_id,project_id,project_name,summary"]
        rows.append(contentsOf: events.sorted { $0.timestamp < $1.timestamp }.map { event in
            [
                iso8601(event.timestamp),
                event.id.uuidString,
                event.kind.rawValue,
                event.sessionID ?? "",
                event.project?.id ?? "",
                event.project?.name ?? "",
                event.summary,
            ].map(csvField).joined(separator: ",")
        })
        return rows.joined(separator: "\n") + "\n"
    }

    static func exportTokenUsageCSV(_ records: [TokenUsageRecord]) -> String {
        var rows = [
            "timestamp,id,provider,model,session_id,project_id,project_name,input_tokens,output_tokens,total_tokens,cost_micros",
        ]
        rows.append(contentsOf: records.sorted { $0.timestamp < $1.timestamp }.map { record in
            [
                iso8601(record.timestamp),
                record.id.uuidString,
                record.provider,
                record.model,
                record.sessionID ?? "",
                record.project?.id ?? "",
                record.project?.name ?? "",
                "\(record.inputTokens)",
                "\(record.outputTokens)",
                "\(record.totalTokens)",
                "\(record.estimatedCostMicros)",
            ].map(csvField).joined(separator: ",")
        })
        return rows.joined(separator: "\n") + "\n"
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
