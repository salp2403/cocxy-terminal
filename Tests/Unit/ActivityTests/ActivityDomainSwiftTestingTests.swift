// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDomainSwiftTestingTests.swift - Local activity and usage foundation.

import Foundation
import SQLite3
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

    @Test("canonical project identity unifies activity from nested directories")
    func canonicalProjectIdentityUnifiesNestedDirectories() throws {
        let root = URL(fileURLWithPath: "/Users/local/private/project-a", isDirectory: true)
        let descriptor = ProjectDescriptor(
            id: ProjectID(rootURL: root),
            rootURL: root,
            automaticName: "project-a",
            displayName: "Project A",
            parent: nil
        )
        let rootRef = ActivityProjectRef.resolvedProject(descriptor, workingDirectory: root)
        let nestedRef = ActivityProjectRef.resolvedProject(
            descriptor,
            workingDirectory: root.appendingPathComponent("Sources", isDirectory: true)
        )

        #expect(rootRef.id == descriptor.id.rawValue)
        #expect(nestedRef.id == descriptor.id.rawValue)
        #expect(rootRef.legacyID != nestedRef.legacyID)
        #expect(rootRef.projectIdentity == descriptor.id)

        let store = try SQLiteActivityStore(databasePath: ":memory:")
        try store.recordEvent(ActivityEvent(
            kind: .commandExecuted,
            project: rootRef,
            summary: "root",
            metadata: ["duration_ms": "1000"]
        ))
        try store.recordEvent(ActivityEvent(
            kind: .commandExecuted,
            project: nestedRef,
            summary: "nested",
            metadata: ["duration_ms": "2000"]
        ))
        let query = ActivityStoreQuery(projectID: descriptor.id.rawValue)
        #expect(try store.events(matching: query).count == 2)
        #expect(try ActivityQueryService(store: store)
            .projectTimeBreakdown(matching: query)
            .map(\.durationMilliseconds) == [3_000])

        let legacy = try JSONDecoder().decode(
            ActivityProjectRef.self,
            from: Data(#"{"id":"legacy-id","name":"Legacy"}"#.utf8)
        )
        #expect(legacy.legacyID == nil)
        #expect(legacy.projectIdentity == nil)
    }

    @Test("dual writes backfill legacy activity and token aliases")
    func dualWritesBackfillLegacyActivityAndTokenAliases() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let root = URL(fileURLWithPath: "/tmp/project-a", isDirectory: true)
        let nested = root.appendingPathComponent("Sources", isDirectory: true)
        let legacy = ActivityProjectRef.workingDirectory(nested)
        try store.recordEvent(ActivityEvent(
            kind: .commandExecuted,
            project: legacy,
            summary: "legacy",
            metadata: ["duration_ms": "1000"]
        ))
        try store.recordTokenUsage(TokenUsageRecord(
            provider: "local",
            model: "model",
            project: legacy,
            inputTokens: 2,
            outputTokens: 3,
            estimatedCostMicros: 4
        ))

        let identity = ProjectID(rootURL: root)
        let canonical = ActivityProjectRef(
            id: identity.rawValue,
            name: "Project A",
            legacyID: legacy.id,
            projectIdentity: identity
        )
        try store.recordEvent(ActivityEvent(
            kind: .commandExecuted,
            project: canonical,
            summary: "current",
            metadata: ["duration_ms": "2000"]
        ))

        let query = ActivityStoreQuery(projectID: identity.rawValue)
        let events = try store.events(matching: query)
        let usage = try store.tokenUsage(matching: query)
        #expect(events.map(\.summary) == ["legacy", "current"])
        #expect(events.allSatisfy { $0.project?.projectIdentity == identity })
        #expect(usage.count == 1)
        #expect(usage.first?.project?.projectIdentity == identity)
        #expect(try ActivityQueryService(store: store)
            .projectTimeBreakdown(matching: query)
            .map(\.durationMilliseconds) == [3_000])
    }

    @Test("legacy SQLite schema migrates before canonical dual writes")
    func legacySQLiteSchemaMigratesBeforeCanonicalDualWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-activity-legacy-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("activity.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try createLegacyActivityDatabase(at: databaseURL)

        let store = try SQLiteActivityStore(databasePath: databaseURL.path)
        let root = URL(fileURLWithPath: "/tmp/legacy-project", isDirectory: true)
        let identity = ProjectID(rootURL: root)
        let project = ActivityProjectRef(
            id: identity.rawValue,
            name: "Legacy Project",
            legacyID: "legacy-project",
            projectIdentity: identity
        )
        try store.recordEvent(ActivityEvent(kind: .tabOpened, project: project, summary: "migrated"))
        try store.recordTokenUsage(TokenUsageRecord(
            provider: "local",
            model: "model",
            project: project,
            inputTokens: 1,
            outputTokens: 1,
            estimatedCostMicros: 1
        ))

        #expect(try store.events(matching: ActivityStoreQuery(projectID: identity.rawValue)).count == 1)
        #expect(try store.tokenUsage(matching: ActivityStoreQuery(projectID: identity.rawValue)).count == 1)
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

    @Test("query service aggregates command runtime by project")
    func queryServiceAggregatesCommandRuntimeByProject() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let projectOne = ActivityProjectRef(id: "project-1", name: "Project One")
        let projectTwo = ActivityProjectRef(id: "project-2", name: "Project Two")
        try [
            ActivityEvent(
                timestamp: date(hour: 8),
                kind: .commandExecuted,
                project: projectOne,
                summary: "swift build",
                metadata: ["duration_ms": "60000"]
            ),
            ActivityEvent(
                timestamp: date(hour: 8, minute: 10),
                kind: .commandExecuted,
                project: projectTwo,
                summary: "swift test",
                metadata: ["duration_ms": "30000"]
            ),
            ActivityEvent(
                timestamp: date(hour: 8, minute: 20),
                kind: .commandExecuted,
                project: projectOne,
                summary: "swift test",
                metadata: ["duration_ms": "30000"]
            ),
            ActivityEvent(
                timestamp: date(hour: 8, minute: 30),
                kind: .commandExecuted,
                project: projectTwo,
                summary: "bad duration",
                metadata: ["duration_ms": "not-a-number"]
            ),
            ActivityEvent(
                timestamp: date(hour: 8, minute: 40),
                kind: .projectSwitched,
                project: projectTwo,
                summary: "Project Two",
                metadata: ["duration_ms": "99999"]
            ),
        ].forEach { try store.recordEvent($0) }

        let rows = try ActivityQueryService(store: store).projectTimeBreakdown()

        #expect(rows.map(\.project.name) == ["Project One", "Project Two"])
        #expect(rows.map(\.durationMilliseconds) == [90_000, 30_000])
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

    private func createLegacyActivityDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw ActivityStoreError.databaseOpenFailed("Legacy test database")
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE activity_events (
            id TEXT PRIMARY KEY, timestamp REAL NOT NULL, kind TEXT NOT NULL,
            session_id TEXT, project_id TEXT, project_name TEXT,
            summary TEXT NOT NULL, metadata_json TEXT NOT NULL
        );
        CREATE TABLE token_usage (
            id TEXT PRIMARY KEY, timestamp REAL NOT NULL, provider TEXT NOT NULL,
            model TEXT NOT NULL, session_id TEXT, project_id TEXT, project_name TEXT,
            input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
            cost_micros INTEGER NOT NULL
        );
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ActivityStoreError.executionFailed("Legacy test schema")
        }
    }
}
