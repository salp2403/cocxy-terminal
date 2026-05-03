// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDashboardSwiftTestingTests.swift - Local Activity dashboard UI model coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Activity dashboard")
struct ActivityDashboardSwiftTestingTests {

    @Test("dashboard model summarizes local activity and cost data")
    func dashboardModelSummarizesLocalActivityAndCostData() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let project = ActivityProjectRef(id: "project-1", name: "Project One")
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 8),
            kind: .commandExecuted,
            project: project,
            summary: "git status"
        ))
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 8, minute: 10),
            kind: .commandExecuted,
            project: project,
            summary: "git status"
        ))
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 9),
            kind: .projectSwitched,
            project: project,
            summary: "Project One"
        ))
        try store.recordTokenUsage(TokenUsageRecord(
            timestamp: date(hour: 10),
            provider: "local-provider",
            model: "small",
            project: project,
            inputTokens: 100,
            outputTokens: 50,
            estimatedCostMicros: 25
        ))
        try store.recordTokenUsage(TokenUsageRecord(
            timestamp: date(hour: 11),
            provider: "local-provider",
            model: "large",
            project: project,
            inputTokens: 200,
            outputTokens: 80,
            estimatedCostMicros: 70
        ))

        let viewModel = ActivityDashboardViewModel(
            store: store,
            privacyPolicy: .enabled,
            calendar: utcCalendar()
        )

        #expect(viewModel.snapshot.totalEvents == 3)
        #expect(viewModel.snapshot.totalTokens == 430)
        #expect(viewModel.snapshot.totalCostMicros == 95)
        #expect(viewModel.snapshot.eventRows.first { $0.kind == .commandExecuted }?.count == 2)
        #expect(viewModel.snapshot.costRows.map(\.model) == ["large", "small"])
        #expect(viewModel.snapshot.insights.mostUsedCommands == ["git status"])
        #expect(viewModel.snapshot.insights.peakHourLabel == "08:00")
        #expect(viewModel.trackingState == .enabled)
    }

    @Test("dashboard model keeps tracking disabled explicit and can clear local data")
    func dashboardModelKeepsTrackingDisabledExplicitAndCanClearLocalData() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        try store.recordEvent(ActivityEvent(kind: .tabOpened, summary: "New tab"))
        let viewModel = ActivityDashboardViewModel(store: store, privacyPolicy: .disabled)

        #expect(viewModel.trackingState == .disabled)
        #expect(viewModel.snapshot.totalEvents == 1)

        try viewModel.deleteAllLocalData()

        #expect(viewModel.snapshot == .empty)
        #expect(try store.events().isEmpty)
    }

    @Test("dashboard model exports the currently loaded local snapshot on demand")
    func dashboardModelExportsCurrentLocalSnapshotOnDemand() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        try store.recordEvent(ActivityEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            timestamp: date(hour: 12),
            kind: .errorEncountered,
            summary: "Build failed"
        ))
        let viewModel = ActivityDashboardViewModel(
            store: store,
            privacyPolicy: .enabled,
            now: { date(hour: 13) }
        )

        let json = try String(data: viewModel.exportData(format: .json), encoding: .utf8)
        let eventCSV = try String(data: viewModel.exportData(format: .eventsCSV), encoding: .utf8)

        #expect(json?.contains("\"Build failed\"") == true)
        #expect(eventCSV?.contains("error_encountered") == true)
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
