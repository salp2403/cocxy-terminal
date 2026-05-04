// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDashboardView.swift - SwiftUI local Activity dashboard.

import SwiftUI

struct ActivityDashboardView: View {
    @ObservedObject var viewModel: ActivityDashboardViewModel
    @StateObject private var fileActions: ActivityDashboardFileActions
    var onDismiss: (() -> Void)? = nil
    var localizer: AppLocalizer

    static let panelWidth: CGFloat = 400

    init(
        viewModel: ActivityDashboardViewModel,
        onDismiss: (() -> Void)? = nil,
        fileActions: ActivityDashboardFileActions? = nil,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.localizer = localizer
        _fileActions = StateObject(
            wrappedValue: fileActions ?? ActivityDashboardFileActions(
                viewModel: viewModel,
                presenter: SystemActivityDashboardFilePresenter(localizer: localizer)
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .glassPanelBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("activity.accessibility", fallback: "Activity Dashboard"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.secondary)

            Text(localized("activity.title", fallback: "Activity"))
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Menu {
                Button(ActivityDashboardExportFormat.json.localizedMenuTitle(using: localizer)) {
                    fileActions.export(.json)
                }
                Button(ActivityDashboardExportFormat.eventsCSV.localizedMenuTitle(using: localizer)) {
                    fileActions.export(.eventsCSV)
                }
                Button(ActivityDashboardExportFormat.tokenUsageCSV.localizedMenuTitle(using: localizer)) {
                    fileActions.export(.tokenUsageCSV)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(!hasLocalData)
            .help(localized("activity.export", fallback: "Export Activity"))
            .accessibilityLabel(localized("activity.export", fallback: "Export Activity"))

            Button(role: .destructive, action: fileActions.confirmAndDeleteAllLocalData) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(!hasLocalData)
            .help(localized("activity.deleteData", fallback: "Delete Activity Data"))
            .accessibilityLabel(localized("activity.deleteData", fallback: "Delete Activity Data"))

            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(localized("common.refresh", fallback: "Refresh"))
            .accessibilityLabel(localized("activity.refresh", fallback: "Refresh Activity"))

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .help(localized("activity.close", fallback: "Close Activity"))
                .accessibilityLabel(localized("activity.close", fallback: "Close Activity"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                ActivityPrivacyTogglesView(state: viewModel.trackingState, localizer: localizer)

                if let error = viewModel.errorMessage {
                    ActivityInlineStatus(
                        title: localized("activity.unavailable.title", fallback: "Activity unavailable"),
                        detail: error,
                        symbolName: "exclamationmark.triangle"
                    )
                }

                if let actionError = fileActions.errorMessage {
                    ActivityInlineStatus(
                        title: localized("activity.actionFailed.title", fallback: "Activity action failed"),
                        detail: actionError,
                        symbolName: "exclamationmark.triangle"
                    )
                }

                metricsGrid
                ProjectTimeBreakdownChart(rows: viewModel.snapshot.projectTimeRows, localizer: localizer)
                TokenUsageGraph(rows: viewModel.snapshot.tokenRows, localizer: localizer)
                CostBreakdownChart(rows: viewModel.snapshot.costRows, localizer: localizer)
                ActivityEventCountsView(rows: viewModel.snapshot.eventRows, localizer: localizer)
                ProductivityInsightsCard(insights: viewModel.snapshot.insights, localizer: localizer)
            }
            .padding(12)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            ActivityMetricTile(
                title: localized("activity.metric.events", fallback: "Events"),
                value: "\(viewModel.snapshot.totalEvents)",
                symbolName: "list.bullet.rectangle"
            )
            ActivityMetricTile(
                title: localized("activity.metric.tokens", fallback: "Tokens"),
                value: "\(viewModel.snapshot.totalTokens)",
                symbolName: "number"
            )
            ActivityMetricTile(
                title: localized("activity.metric.cost", fallback: "Cost"),
                value: viewModel.snapshot.totalCostText,
                symbolName: "creditcard"
            )
        }
    }

    private var hasLocalData: Bool {
        viewModel.snapshot.totalEvents > 0 || viewModel.snapshot.totalTokens > 0
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct ActivityMetricTile: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: CocxyColors.teal))
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.58))
        )
    }
}

struct ActivityPrivacyTogglesView: View {
    let state: ActivityDashboardTrackingState
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        ActivityInlineStatus(
            title: title,
            detail: detail,
            symbolName: symbolName
        )
    }

    private var title: String {
        state.localizedTitle(using: localizer)
    }

    private var detail: String {
        state.localizedDetail(using: localizer)
    }

    private var symbolName: String {
        switch state {
        case .enabled, .activityOnly:
            return "lock.fill"
        case .disabled:
            return "pause.circle"
        }
    }
}

private struct ActivityInlineStatus: View {
    let title: String
    let detail: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: CocxyColors.green))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.48))
        )
    }
}

struct ProjectTimeBreakdownChart: View {
    let rows: [ActivityDashboardProjectTimeRow]
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        ActivitySection(
            title: localized("activity.section.projectTime", fallback: "Project Time"),
            symbolName: "clock"
        ) {
            if rows.isEmpty {
                ActivityEmptyRow(title: localized("activity.empty.noProjectRuntime", fallback: "No project runtime"))
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.projectName)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(row.durationText)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: CocxyColors.teal))
                            }
                            ProgressView(value: progress(for: row))
                                .progressViewStyle(.linear)
                                .tint(Color(nsColor: CocxyColors.teal))
                        }
                    }
                }
            }
        }
    }

    private func progress(for row: ActivityDashboardProjectTimeRow) -> Double {
        let maximum = max(rows.map(\.durationMilliseconds).max() ?? 1, 1)
        return Double(row.durationMilliseconds) / Double(maximum)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

struct TokenUsageGraph: View {
    let rows: [ActivityDashboardTokenRow]
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        ActivitySection(
            title: localized("activity.section.tokenUsage", fallback: "Token Usage"),
            symbolName: "chart.bar.xaxis"
        ) {
            if rows.isEmpty {
                ActivityEmptyRow(title: localized("activity.empty.noTokenUsage", fallback: "No token usage"))
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(rows.suffix(14)) { row in
                        VStack(spacing: 5) {
                            GeometryReader { proxy in
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(nsColor: CocxyColors.blue))
                                        .frame(height: barHeight(for: row, availableHeight: proxy.size.height))
                                }
                            }
                            .frame(height: 72)
                            Text(row.dayLabel)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func barHeight(for row: ActivityDashboardTokenRow, availableHeight: CGFloat) -> CGFloat {
        let maximum = max(rows.map(\.totalTokens).max() ?? 1, 1)
        return max(4, availableHeight * CGFloat(row.totalTokens) / CGFloat(maximum))
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

struct CostBreakdownChart: View {
    let rows: [ActivityDashboardCostRow]
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        ActivitySection(
            title: localized("activity.section.costBreakdown", fallback: "Cost Breakdown"),
            symbolName: "creditcard"
        ) {
            if rows.isEmpty {
                ActivityEmptyRow(title: localized("activity.empty.noCostRecords", fallback: "No cost records"))
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(row.provider) / \(row.model)")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(row.totalCostText)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: CocxyColors.teal))
                            }
                            ProgressView(value: progress(for: row))
                                .progressViewStyle(.linear)
                                .tint(Color(nsColor: CocxyColors.teal))
                        }
                    }
                }
            }
        }
    }

    private func progress(for row: ActivityDashboardCostRow) -> Double {
        let maximum = max(rows.map(\.totalCostMicros).max() ?? 1, 1)
        return Double(row.totalCostMicros) / Double(maximum)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct ActivityEventCountsView: View {
    let rows: [ActivityDashboardEventRow]
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        ActivitySection(title: localized("activity.section.events", fallback: "Events"), symbolName: "list.bullet") {
            if rows.isEmpty {
                ActivityEmptyRow(title: localized("activity.empty.noActivityEvents", fallback: "No activity events"))
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.kind.localizedDashboardTitle(using: localizer))
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(row.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

struct ProductivityInsightsCard: View {
    let insights: ActivityDashboardInsights
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        ActivitySection(title: localized("activity.section.insights", fallback: "Insights"), symbolName: "sparkle.magnifyingglass") {
            VStack(alignment: .leading, spacing: 8) {
                insightRow(
                    localized("activity.insight.peakHour", fallback: "Peak hour"),
                    value: localizedPeakHour
                )
                insightRow(
                    localized("activity.insight.projectSwitches", fallback: "Project switches"),
                    value: "\(insights.projectSwitches)"
                )
                if insights.mostUsedCommands.isEmpty {
                    ActivityEmptyRow(title: localized("activity.empty.noCommands", fallback: "No commands yet"))
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized("activity.insight.topCommands", fallback: "Top commands"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(insights.mostUsedCommands, id: \.self) { command in
                            Text(command)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private func insightRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private var localizedPeakHour: String {
        if insights.peakHour == nil {
            return localized("activity.insight.none", fallback: "None")
        }
        return insights.peakHourLabel
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct ActivitySection<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.42))
        )
    }
}

private struct ActivityEmptyRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
