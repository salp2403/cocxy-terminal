// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDashboardView.swift - SwiftUI local Activity dashboard.

import SwiftUI

struct ActivityDashboardView: View {
    @ObservedObject var viewModel: ActivityDashboardViewModel
    @StateObject private var fileActions: ActivityDashboardFileActions
    var onDismiss: (() -> Void)? = nil

    static let panelWidth: CGFloat = 400

    init(
        viewModel: ActivityDashboardViewModel,
        onDismiss: (() -> Void)? = nil,
        fileActions: ActivityDashboardFileActions? = nil
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _fileActions = StateObject(
            wrappedValue: fileActions ?? ActivityDashboardFileActions(viewModel: viewModel)
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
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity Dashboard")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.secondary)

            Text("Activity")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Menu {
                Button(ActivityDashboardExportFormat.json.menuTitle) {
                    fileActions.export(.json)
                }
                Button(ActivityDashboardExportFormat.eventsCSV.menuTitle) {
                    fileActions.export(.eventsCSV)
                }
                Button(ActivityDashboardExportFormat.tokenUsageCSV.menuTitle) {
                    fileActions.export(.tokenUsageCSV)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(!hasLocalData)
            .help("Export Activity")
            .accessibilityLabel("Export Activity")

            Button(role: .destructive, action: fileActions.confirmAndDeleteAllLocalData) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(!hasLocalData)
            .help("Delete Activity Data")
            .accessibilityLabel("Delete Activity Data")

            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help("Refresh")
            .accessibilityLabel("Refresh Activity")

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .help("Close Activity")
                .accessibilityLabel("Close Activity")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                ActivityPrivacyTogglesView(state: viewModel.trackingState)

                if let error = viewModel.errorMessage {
                    ActivityInlineStatus(
                        title: "Activity unavailable",
                        detail: error,
                        symbolName: "exclamationmark.triangle"
                    )
                }

                if let actionError = fileActions.errorMessage {
                    ActivityInlineStatus(
                        title: "Activity action failed",
                        detail: actionError,
                        symbolName: "exclamationmark.triangle"
                    )
                }

                metricsGrid
                TokenUsageGraph(rows: viewModel.snapshot.tokenRows)
                CostBreakdownChart(rows: viewModel.snapshot.costRows)
                ActivityEventCountsView(rows: viewModel.snapshot.eventRows)
                ProductivityInsightsCard(insights: viewModel.snapshot.insights)
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
                title: "Events",
                value: "\(viewModel.snapshot.totalEvents)",
                symbolName: "list.bullet.rectangle"
            )
            ActivityMetricTile(
                title: "Tokens",
                value: "\(viewModel.snapshot.totalTokens)",
                symbolName: "number"
            )
            ActivityMetricTile(
                title: "Cost",
                value: viewModel.snapshot.totalCostText,
                symbolName: "creditcard"
            )
        }
    }

    private var hasLocalData: Bool {
        viewModel.snapshot.totalEvents > 0 || viewModel.snapshot.totalTokens > 0
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

    var body: some View {
        ActivityInlineStatus(
            title: title,
            detail: detail,
            symbolName: symbolName
        )
    }

    private var title: String {
        switch state {
        case .enabled:
            return "Local tracking enabled"
        case .activityOnly:
            return "Local activity enabled"
        case .disabled:
            return "Local tracking disabled"
        }
    }

    private var detail: String {
        switch state {
        case .enabled:
            return "Activity and cost records stay on this Mac."
        case .activityOnly:
            return "Activity records stay on this Mac; cost tracking is off."
        case .disabled:
            return "Existing local records remain visible until deleted."
        }
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

struct TokenUsageGraph: View {
    let rows: [ActivityDashboardTokenRow]

    var body: some View {
        ActivitySection(title: "Token Usage", symbolName: "chart.bar.xaxis") {
            if rows.isEmpty {
                ActivityEmptyRow(title: "No token usage")
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
}

struct CostBreakdownChart: View {
    let rows: [ActivityDashboardCostRow]

    var body: some View {
        ActivitySection(title: "Cost Breakdown", symbolName: "creditcard") {
            if rows.isEmpty {
                ActivityEmptyRow(title: "No cost records")
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
}

private struct ActivityEventCountsView: View {
    let rows: [ActivityDashboardEventRow]

    var body: some View {
        ActivitySection(title: "Events", symbolName: "list.bullet") {
            if rows.isEmpty {
                ActivityEmptyRow(title: "No activity events")
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.title)
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
}

struct ProductivityInsightsCard: View {
    let insights: ActivityDashboardInsights

    var body: some View {
        ActivitySection(title: "Insights", symbolName: "sparkle.magnifyingglass") {
            VStack(alignment: .leading, spacing: 8) {
                insightRow("Peak hour", value: insights.peakHourLabel)
                insightRow("Project switches", value: "\(insights.projectSwitches)")
                if insights.mostUsedCommands.isEmpty {
                    ActivityEmptyRow(title: "No commands yet")
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Top commands")
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
