// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectActivityMetricsView.swift - Compact weekly and monthly project activity.

import SwiftUI

struct ProjectActivityMetricsView: View {
    let state: ProjectActivitySummaryState
    let localizer: AppLocalizer

    @Environment(\.designThemePalette) private var palette

    var body: some View {
        Group {
            switch state {
            case .loading:
                statusLabel(
                    localizer.string("projectHome.activity.loading", fallback: "Loading activity"),
                    icon: "clock"
                )
            case .disabled:
                statusLabel(
                    localizer.string(
                        "projectHome.activity.disabled",
                        fallback: "Local activity tracking is off"
                    ),
                    icon: "eye.slash"
                )
            case .unavailable:
                statusLabel(
                    localizer.string(
                        "projectHome.activity.unavailable",
                        fallback: "Project activity is unavailable"
                    ),
                    icon: "exclamationmark.triangle"
                )
            case .available(let summary, let costTrackingEnabled):
                metricsGrid(summary, costTrackingEnabled: costTrackingEnabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricsGrid(
        _ summary: ProjectActivitySummary,
        costTrackingEnabled: Bool
    ) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Color.clear.frame(width: 42, height: 1)
                    metricHeader("projectHome.activity.time", fallback: "Time")
                    metricHeader("projectHome.activity.tokens", fallback: "Tokens")
                    metricHeader("projectHome.activity.cost", fallback: "Cost")
                }
                metricRow(
                    "projectHome.activity.week",
                    fallback: "Week",
                    metrics: summary.week
                )
                metricRow(
                    "projectHome.activity.month",
                    fallback: "Month",
                    metrics: summary.month
                )
            }
            if !costTrackingEnabled {
                Label(
                    localizer.string(
                        "projectHome.activity.costDisabled",
                        fallback: "Cost tracking off"
                    ),
                    systemImage: "lock"
                )
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textLow.resolvedColor())
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func metricHeader(_ key: String, fallback: String) -> some View {
        Text(localizer.string(key, fallback: fallback))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(palette.textLow.resolvedColor())
    }

    private func metricRow(
        _ key: String,
        fallback: String,
        metrics: ProjectActivityMetrics
    ) -> some View {
        GridRow {
            Text(localizer.string(key, fallback: fallback))
                .foregroundStyle(palette.textLow.resolvedColor())
            Text(ProjectActivityMetricsFormatter.duration(metrics.durationMilliseconds))
            Text(ProjectActivityMetricsFormatter.tokens(metrics.totalTokens))
            Text(ProjectActivityMetricsFormatter.cost(metrics.totalCostMicros))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(palette.textMedium.resolvedColor())
    }

    private func statusLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(palette.textLow.resolvedColor())
    }
}

enum ProjectActivityMetricsFormatter {
    static func duration(_ milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds) / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m" }
        return "\(seconds)s"
    }

    static func tokens(_ count: Int) -> String {
        let value = max(0, count)
        if value >= 1_000_000 {
            return compact(Double(value) / 1_000_000, suffix: "M")
        }
        if value >= 1_000 {
            return compact(Double(value) / 1_000, suffix: "K")
        }
        return "\(value)"
    }

    static func cost(_ micros: Int64) -> String {
        String(format: "$%.4f", Double(max(0, micros)) / 1_000_000)
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let format = value >= 100 || value.rounded() == value ? "%.0f%@" : "%.1f%@"
        return String(format: format, value, suffix)
    }
}
