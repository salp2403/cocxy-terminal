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
            summary: "git status",
            metadata: ["duration_ms": "60000"]
        ))
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 8, minute: 10),
            kind: .commandExecuted,
            project: project,
            summary: "git status",
            metadata: ["duration_ms": "30000"]
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
        #expect(viewModel.snapshot.projectTimeRows.map(\.projectName) == ["Project One"])
        #expect(viewModel.snapshot.projectTimeRows.map(\.durationText) == ["1m 30s"])
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

    @Test("file actions export selected format to explicit user destination")
    func fileActionsExportSelectedFormatToExplicitUserDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-activity-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("activity.json")
        let presenter = ActivityDashboardTestPresenter(destinationURL: destination)
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        try store.recordEvent(ActivityEvent(kind: .errorEncountered, summary: "Build failed"))
        let viewModel = ActivityDashboardViewModel(store: store, privacyPolicy: .enabled)
        let actions = ActivityDashboardFileActions(viewModel: viewModel, presenter: presenter)

        actions.export(.json)

        let exported = try String(contentsOf: destination, encoding: .utf8)
        #expect(exported.contains("\"Build failed\""))
        #expect(actions.errorMessage == nil)
        #expect(actions.lastExportedURL == destination)
        #expect(presenter.requestedDefaultFilename == "cocxy-activity.json")
    }

    @Test("dashboard export smoke writes every format and preserves local insights")
    func dashboardExportSmokeWritesEveryFormatAndPreservesLocalInsights() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-activity-export-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let project = ActivityProjectRef(id: "project-1", name: "Project One")
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 8),
            kind: .commandExecuted,
            project: project,
            summary: "swift test",
            metadata: ["duration_ms": "42000"]
        ))
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 8, minute: 30),
            kind: .commandExecuted,
            project: project,
            summary: "swift test",
            metadata: ["duration_ms": "18000"]
        ))
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 9),
            kind: .commandExecuted,
            project: project,
            summary: "swift build",
            metadata: ["duration_ms": "30000"]
        ))
        try store.recordEvent(ActivityEvent(
            timestamp: date(hour: 10),
            kind: .projectSwitched,
            project: project,
            summary: "Project One"
        ))
        try store.recordTokenUsage(TokenUsageRecord(
            timestamp: date(hour: 11),
            provider: "local-provider",
            model: "small",
            project: project,
            inputTokens: 120,
            outputTokens: 80,
            estimatedCostMicros: 44
        ))
        let viewModel = ActivityDashboardViewModel(
            store: store,
            privacyPolicy: .enabled,
            calendar: utcCalendar(),
            now: { date(hour: 12) }
        )

        #expect(viewModel.snapshot.insights.mostUsedCommands == ["swift test", "swift build"])
        #expect(viewModel.snapshot.insights.peakHourLabel == "08:00")
        #expect(viewModel.snapshot.insights.projectSwitches == 1)
        #expect(viewModel.snapshot.projectTimeRows.map(\.durationText) == ["1m 30s"])

        let cases: [(ActivityDashboardExportFormat, String, String, String)] = [
            (.json, "activity.json", "cocxy-activity.json", "\"swift test\""),
            (.eventsCSV, "events.csv", "cocxy-activity-events.csv", "command_executed"),
            (.tokenUsageCSV, "token-usage.csv", "cocxy-activity-token-usage.csv", "local-provider,small"),
        ]

        for (format, filename, defaultFilename, expectedText) in cases {
            let destination = root.appendingPathComponent(filename)
            let presenter = ActivityDashboardTestPresenter(destinationURL: destination)
            let actions = ActivityDashboardFileActions(viewModel: viewModel, presenter: presenter)

            actions.export(format)

            let exported = try String(contentsOf: destination, encoding: .utf8)
            #expect(exported.contains(expectedText))
            #expect(actions.errorMessage == nil)
            #expect(actions.lastExportedURL == destination)
            #expect(presenter.requestedDefaultFilename == defaultFilename)
        }
    }

    @Test("file actions clear local data only after destructive confirmation")
    func fileActionsClearLocalDataOnlyAfterDestructiveConfirmation() throws {
        let presenter = ActivityDashboardTestPresenter(confirmedDelete: false)
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        try store.recordEvent(ActivityEvent(kind: .tabOpened, summary: "New tab"))
        let viewModel = ActivityDashboardViewModel(store: store, privacyPolicy: .enabled)
        let actions = ActivityDashboardFileActions(viewModel: viewModel, presenter: presenter)

        actions.confirmAndDeleteAllLocalData()
        #expect(viewModel.snapshot.totalEvents == 1)

        presenter.confirmedDelete = true
        actions.confirmAndDeleteAllLocalData()

        #expect(viewModel.snapshot == .empty)
        #expect(actions.errorMessage == nil)
    }

    @Test("delete-all Activity confirmation copy follows configured app language")
    func deleteAllActivityConfirmationCopyFollowsConfiguredAppLanguage() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        let copy = SystemActivityDashboardFilePresenter.localizedDeleteAllCopy(localizer: localizer)

        #expect(copy.messageText == "¿Eliminar todos los datos de Activity?")
        #expect(copy.informativeText == "Esto elimina los registros locales de Activity y tokens de esta Mac.")
        #expect(copy.primaryButton == "Eliminar")
        #expect(copy.secondaryButton == "Cancelar")
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

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}

@MainActor
private final class ActivityDashboardTestPresenter: ActivityDashboardFilePresenting {
    var destinationURL: URL?
    var confirmedDelete: Bool
    private(set) var requestedDefaultFilename: String?

    init(destinationURL: URL? = nil, confirmedDelete: Bool = false) {
        self.destinationURL = destinationURL
        self.confirmedDelete = confirmedDelete
    }

    func destination(
        for format: ActivityDashboardExportFormat,
        defaultFilename: String,
        completion: @escaping (URL?) -> Void
    ) {
        requestedDefaultFilename = defaultFilename
        completion(destinationURL)
    }

    func confirmDeleteAll(completion: @escaping (Bool) -> Void) {
        completion(confirmedDelete)
    }
}
