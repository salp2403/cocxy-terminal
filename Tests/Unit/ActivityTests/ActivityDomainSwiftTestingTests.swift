// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDomainSwiftTestingTests.swift - Local activity and usage foundation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Activity domain")
struct ActivityDomainSwiftTestingTests {

    @Test("recorder is disabled by default and only writes when policy allows it")
    func recorderIsDisabledByDefaultAndOnlyWritesWhenPolicyAllowsIt() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let event = ActivityEvent(
            timestamp: date(hour: 9),
            kind: .commandExecuted,
            sessionID: "s1",
            summary: "git status"
        )

        try ActivityRecorder(store: store).record(event)
        #expect(try store.events().isEmpty)

        let recorder = ActivityRecorder(store: store, policyProvider: { .enabled })
        try recorder.record(event)

        #expect(try store.events().map(\.summary) == ["git status"])
    }

    @Test("SQLite store persists events and token usage with local project identifiers")
    func sqliteStorePersistsEventsAndTokenUsageWithLocalProjectIdentifiers() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let project = ActivityProjectRef.workingDirectory(URL(fileURLWithPath: "/Users/local/private/project-a"))
        let event = ActivityEvent(
            timestamp: date(hour: 10),
            kind: .blockFinished,
            sessionID: "s1",
            project: project,
            summary: "Build finished",
            metadata: ["exit": "0"]
        )
        let usage = TokenUsageRecord(
            timestamp: date(hour: 11),
            provider: "local-provider",
            model: "local-model",
            sessionID: "s1",
            project: project,
            inputTokens: 120,
            outputTokens: 80,
            estimatedCostMicros: 44
        )

        try store.recordEvent(event)
        try store.recordTokenUsage(usage)

        let events = try store.events(matching: ActivityStoreQuery(projectID: project.id))
        let records = try store.tokenUsage(matching: ActivityStoreQuery(sessionID: "s1"))

        #expect(project.name == "project-a")
        #expect(!project.id.contains("/Users/local/private"))
        #expect(events == [event])
        #expect(records == [usage])

        try store.deleteAll()
        #expect(try store.events().isEmpty)
        #expect(try store.tokenUsage().isEmpty)
    }

    @Test("cost tracker uses caller supplied rates and rounds to micro units")
    func costTrackerUsesCallerSuppliedRatesAndRoundsToMicroUnits() {
        let rate = TokenCostRate(
            provider: "local-provider",
            model: "local-model",
            inputMicrosPerMillionTokens: 1_250_000,
            outputMicrosPerMillionTokens: 10_000_000
        )

        let cost = CostTracker.estimatedCostMicros(
            inputTokens: 1_000,
            outputTokens: 250,
            rate: rate
        )

        #expect(cost == 3_750)
        let usage = CostTracker.usageRecord(
            provider: "local-provider",
            model: "local-model",
            sessionID: "s1",
            project: nil,
            inputTokens: 1_000,
            outputTokens: 250,
            rate: rate,
            timestamp: date(hour: 12)
        )
        #expect(usage.estimatedCostMicros == 3_750)
        #expect(usage.totalTokens == 1_250)
    }

    @Test("query service aggregates counts usage costs and productivity insights")
    func queryServiceAggregatesCountsUsageCostsAndProductivityInsights() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let calendar = utcCalendar()
        let project = ActivityProjectRef(id: "project-1", name: "Project One")
        try [
            ActivityEvent(timestamp: date(hour: 8), kind: .commandExecuted, project: project, summary: "git status"),
            ActivityEvent(timestamp: date(hour: 8, minute: 10), kind: .commandExecuted, project: project, summary: "git status"),
            ActivityEvent(timestamp: date(hour: 9), kind: .commandExecuted, project: project, summary: "swift test"),
            ActivityEvent(timestamp: date(hour: 9, minute: 15), kind: .projectSwitched, project: project, summary: "Project One"),
        ].forEach { try store.recordEvent($0) }
        try [
            TokenUsageRecord(
                timestamp: date(day: 1, hour: 10),
                provider: "local-provider",
                model: "small",
                project: project,
                inputTokens: 100,
                outputTokens: 50,
                estimatedCostMicros: 10
            ),
            TokenUsageRecord(
                timestamp: date(day: 2, hour: 10),
                provider: "local-provider",
                model: "small",
                project: project,
                inputTokens: 200,
                outputTokens: 100,
                estimatedCostMicros: 20
            ),
            TokenUsageRecord(
                timestamp: date(day: 2, hour: 11),
                provider: "local-provider",
                model: "large",
                project: project,
                inputTokens: 300,
                outputTokens: 150,
                estimatedCostMicros: 60
            ),
        ].forEach { try store.recordTokenUsage($0) }

        let query = ActivityQueryService(store: store, calendar: calendar)

        #expect(try query.eventCounts().first { $0.kind == .commandExecuted }?.count == 3)
        #expect(try query.tokenUsageByDay().map(\.inputTokens) == [100, 500])
        #expect(try query.costBreakdown().map(\.totalCostMicros) == [60, 30])
        #expect(try query.productivityInsights().mostUsedCommands == ["git status", "swift test"])
        #expect(try query.productivityInsights().peakHour == 8)
        #expect(try query.productivityInsights().projectSwitches == 1)
    }

    @Test("manual exporters produce deterministic JSON and escaped CSV")
    func manualExportersProduceDeterministicJSONAndEscapedCSV() throws {
        let event = ActivityEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: date(hour: 7),
            kind: .errorEncountered,
            summary: "failed, needs \"quote\""
        )
        let usage = TokenUsageRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: date(hour: 8),
            provider: "local-provider",
            model: "local-model",
            inputTokens: 10,
            outputTokens: 5,
            estimatedCostMicros: 2
        )
        let snapshot = ActivityExportSnapshot(
            exportedAt: date(hour: 9),
            events: [event],
            tokenUsage: [usage]
        )

        let json = try String(data: ActivityExporter.exportJSON(snapshot), encoding: .utf8)
        let eventCSV = ActivityExporter.exportEventsCSV([event])
        let usageCSV = ActivityExporter.exportTokenUsageCSV([usage])

        #expect(json?.contains("\"events\"") == true)
        #expect(eventCSV.contains("\"failed, needs \"\"quote\"\"\""))
        #expect(usageCSV.contains("local-provider,local-model"))
        #expect(usageCSV.contains(",10,5,15,2"))
    }

    private func date(day: Int = 1, hour: Int, minute: Int = 0) -> Date {
        DateComponents(
            calendar: utcCalendar(),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
