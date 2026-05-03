// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDashboardViewModel.swift - Local Activity dashboard presentation model.

import Combine
import Foundation

enum ActivityDashboardTrackingState: Sendable, Equatable {
    case enabled
    case activityOnly
    case disabled
}

enum ActivityDashboardExportFormat: Sendable, Equatable {
    case json
    case eventsCSV
    case tokenUsageCSV
}

struct ActivityDashboardSnapshot: Sendable, Equatable {
    let totalEvents: Int
    let totalTokens: Int
    let totalCostMicros: Int64
    let eventRows: [ActivityDashboardEventRow]
    let tokenRows: [ActivityDashboardTokenRow]
    let costRows: [ActivityDashboardCostRow]
    let projectTimeRows: [ActivityDashboardProjectTimeRow]
    let insights: ActivityDashboardInsights

    static let empty = ActivityDashboardSnapshot(
        totalEvents: 0,
        totalTokens: 0,
        totalCostMicros: 0,
        eventRows: [],
        tokenRows: [],
        costRows: [],
        projectTimeRows: [],
        insights: .empty
    )

    var totalCostText: String {
        Self.costText(totalCostMicros)
    }

    static func costText(_ micros: Int64) -> String {
        String(format: "$%.4f", Double(max(0, micros)) / 1_000_000)
    }
}

struct ActivityDashboardEventRow: Identifiable, Sendable, Equatable {
    var id: ActivityEventKind { kind }
    let kind: ActivityEventKind
    let title: String
    let count: Int
}

struct ActivityDashboardTokenRow: Identifiable, Sendable, Equatable {
    let id: Date
    let day: Date
    let dayLabel: String
    let inputTokens: Int
    let outputTokens: Int
    let totalCostMicros: Int64

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

struct ActivityDashboardCostRow: Identifiable, Sendable, Equatable {
    var id: String { "\(provider)/\(model)" }
    let provider: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalCostMicros: Int64

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    var totalCostText: String {
        ActivityDashboardSnapshot.costText(totalCostMicros)
    }
}

struct ActivityDashboardProjectTimeRow: Identifiable, Sendable, Equatable {
    var id: String { projectID }
    let projectID: String
    let projectName: String
    let durationMilliseconds: Int64

    var durationText: String {
        Self.durationText(milliseconds: durationMilliseconds)
    }

    private static func durationText(milliseconds: Int64) -> String {
        let safeMilliseconds = max(0, milliseconds)
        guard safeMilliseconds > 0 else { return "0s" }
        let totalSeconds = max(1, (safeMilliseconds + 500) / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return seconds > 0
                ? "\(hours)h \(minutes)m \(seconds)s"
                : "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return seconds > 0
                ? "\(minutes)m \(seconds)s"
                : "\(minutes)m"
        }
        return "\(seconds)s"
    }
}

struct ActivityDashboardInsights: Sendable, Equatable {
    let mostUsedCommands: [String]
    let peakHour: Int?
    let peakHourLabel: String
    let projectSwitches: Int

    static let empty = ActivityDashboardInsights(
        mostUsedCommands: [],
        peakHour: nil,
        peakHourLabel: "None",
        projectSwitches: 0
    )
}

@MainActor
final class ActivityDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: ActivityDashboardSnapshot = .empty
    @Published private(set) var trackingState: ActivityDashboardTrackingState
    @Published private(set) var errorMessage: String?

    private let store: ActivityStoring
    private let queryService: ActivityQueryService
    private let calendar: Calendar
    private let now: () -> Date
    private var events: [ActivityEvent] = []
    private var tokenUsage: [TokenUsageRecord] = []

    init(
        store: ActivityStoring,
        privacyPolicy: ActivityPrivacyPolicy = .disabled,
        calendar: Calendar = Calendar(identifier: .gregorian),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.queryService = ActivityQueryService(store: store, calendar: calendar)
        self.calendar = calendar
        self.now = now
        self.trackingState = Self.trackingState(for: privacyPolicy)
        refresh()
    }

    func setPrivacyPolicy(_ policy: ActivityPrivacyPolicy) {
        trackingState = Self.trackingState(for: policy)
    }

    func refresh() {
        do {
            events = try store.events(matching: ActivityStoreQuery())
            tokenUsage = try store.tokenUsage(matching: ActivityStoreQuery())
            snapshot = try makeSnapshot()
            errorMessage = nil
        } catch {
            snapshot = .empty
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllLocalData() throws {
        try store.deleteAll()
        refresh()
    }

    func exportData(format: ActivityDashboardExportFormat) throws -> Data {
        let exportSnapshot = ActivityExportSnapshot(
            exportedAt: now(),
            events: events,
            tokenUsage: tokenUsage
        )
        switch format {
        case .json:
            return try ActivityExporter.exportJSON(exportSnapshot)
        case .eventsCSV:
            return Data(ActivityExporter.exportEventsCSV(events).utf8)
        case .tokenUsageCSV:
            return Data(ActivityExporter.exportTokenUsageCSV(tokenUsage).utf8)
        }
    }

    private func makeSnapshot() throws -> ActivityDashboardSnapshot {
        let eventRows = try queryService.eventCounts().map { count in
            ActivityDashboardEventRow(
                kind: count.kind,
                title: Self.title(for: count.kind),
                count: count.count
            )
        }
        let tokenRows = try queryService.tokenUsageByDay().map { bucket in
            ActivityDashboardTokenRow(
                id: bucket.day,
                day: bucket.day,
                dayLabel: Self.dayLabel(for: bucket.day, calendar: calendar),
                inputTokens: bucket.inputTokens,
                outputTokens: bucket.outputTokens,
                totalCostMicros: bucket.totalCostMicros
            )
        }
        let costRows = try queryService.costBreakdown().map { breakdown in
            ActivityDashboardCostRow(
                provider: breakdown.provider,
                model: breakdown.model,
                inputTokens: breakdown.inputTokens,
                outputTokens: breakdown.outputTokens,
                totalCostMicros: breakdown.totalCostMicros
            )
        }
        let projectTimeRows = try queryService.projectTimeBreakdown().map { breakdown in
            ActivityDashboardProjectTimeRow(
                projectID: breakdown.project.id,
                projectName: breakdown.project.name,
                durationMilliseconds: breakdown.durationMilliseconds
            )
        }
        let insights = try queryService.productivityInsights()

        return ActivityDashboardSnapshot(
            totalEvents: events.count,
            totalTokens: tokenUsage.reduce(0) { $0 + $1.totalTokens },
            totalCostMicros: tokenUsage.reduce(0) { $0 + $1.estimatedCostMicros },
            eventRows: eventRows,
            tokenRows: tokenRows,
            costRows: costRows,
            projectTimeRows: projectTimeRows,
            insights: ActivityDashboardInsights(
                mostUsedCommands: insights.mostUsedCommands,
                peakHour: insights.peakHour,
                peakHourLabel: Self.peakHourLabel(insights.peakHour),
                projectSwitches: insights.projectSwitches
            )
        )
    }

    private static func trackingState(
        for policy: ActivityPrivacyPolicy
    ) -> ActivityDashboardTrackingState {
        if policy.activityTrackingEnabled && policy.tokenCostTrackingEnabled {
            return .enabled
        }
        if policy.activityTrackingEnabled {
            return .activityOnly
        }
        return .disabled
    }

    private static func title(for kind: ActivityEventKind) -> String {
        switch kind {
        case .commandExecuted:
            return "Commands"
        case .tabOpened:
            return "Tabs"
        case .splitCreated:
            return "Splits"
        case .agentInvoked:
            return "Agents"
        case .blockFinished:
            return "Blocks"
        case .errorEncountered:
            return "Errors"
        case .projectSwitched:
            return "Project Switches"
        }
    }

    private static func peakHourLabel(_ hour: Int?) -> String {
        guard let hour else { return "None" }
        return String(format: "%02d:00", hour)
    }

    private static func dayLabel(for day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: day)
        guard let month = components.month, let day = components.day else {
            return "Unknown"
        }
        return String(format: "%02d/%02d", month, day)
    }
}
