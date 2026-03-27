// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineEventRow.swift - Individual event row in the timeline view.

import SwiftUI

// MARK: - Timeline Event Row

/// A single row in the timeline view representing one agent action.
///
/// Displays:
/// - Timestamp (HH:mm:ss)
/// - Type icon (SF Symbol, color-coded)
/// - Tool name or event type
/// - File path (truncated to last component)
/// - Duration (formatted: ms or seconds)
///
/// Error rows are highlighted with a red background tint.
///
/// - SeeAlso: `TimelineView` (parent container)
/// - SeeAlso: `TimelineEvent` (data model)
struct TimelineEventRow: View {

    /// The timeline event to display.
    let event: TimelineEvent

    // MARK: - Constants

    /// Maximum characters for a displayed file path before truncation.
    private static let maxFilePathLength = 40

    /// Shared formatter for HH:mm:ss timestamps.
    /// DateFormatter is expensive to create -- reuse a single instance.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            timestampLabel
            iconView
            actionLabel
            Spacer()
            filePathLabel
            durationLabel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(event.isError ? Color.red.opacity(0.15) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Timestamp

    private var timestampLabel: some View {
        Text(formattedTimestamp)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: 58, alignment: .leading)
    }

    // MARK: - Icon

    private var iconView: some View {
        Image(systemName: iconName)
            .font(.system(size: 10))
            .foregroundColor(iconColor)
            .frame(width: 14, height: 14)
    }

    // MARK: - Action Label

    private var actionLabel: some View {
        Text(actionText)
            .font(.system(size: 11, weight: event.isError ? .semibold : .regular))
            .foregroundColor(event.isError ? .red : .primary)
            .lineLimit(1)
            .frame(minWidth: 60, alignment: .leading)
    }

    // MARK: - File Path

    private var filePathLabel: some View {
        Group {
            if let path = event.filePath {
                Text(truncatedFilePath(path))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Duration

    private var durationLabel: some View {
        Text(TimelineExporter.formatDuration(event.durationMs))
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: 50, alignment: .trailing)
    }

    // MARK: - Computed Properties

    /// Formats the timestamp as HH:mm:ss using the shared static formatter.
    private var formattedTimestamp: String {
        Self.timestampFormatter.string(from: event.timestamp)
    }

    /// The SF Symbol name for this event type.
    private var iconName: String {
        switch event.type {
        case .sessionStart:   return "play.circle.fill"
        case .sessionEnd:     return "stop.circle.fill"
        case .toolUse:        return "wrench.fill"
        case .toolFailure:    return "exclamationmark.triangle.fill"
        case .userPrompt:     return "text.bubble.fill"
        case .agentResponse:  return "cpu.fill"
        case .subagentStart:  return "arrow.branch"
        case .subagentStop:   return "arrow.merge"
        case .notification:   return "bell.fill"
        case .taskCompleted:  return "checkmark.circle.fill"
        case .stateChange:    return "arrow.triangle.swap"
        }
    }

    /// The color for this event type's icon.
    private var iconColor: Color {
        if event.isError {
            return Color(nsColor: CocxyColors.red)
        }

        switch event.type {
        case .sessionStart, .taskCompleted:
            return Color(nsColor: CocxyColors.green)
        case .sessionEnd:
            return Color(nsColor: CocxyColors.overlay2)
        case .toolUse:
            return Color(nsColor: CocxyColors.blue)
        case .toolFailure:
            return Color(nsColor: CocxyColors.red)
        case .userPrompt:
            return Color(nsColor: CocxyColors.peach)
        case .agentResponse:
            return Color(nsColor: CocxyColors.mauve)
        case .subagentStart, .subagentStop:
            return Color(nsColor: CocxyColors.sky)
        case .notification:
            return Color(nsColor: CocxyColors.yellow)
        case .stateChange:
            return Color(nsColor: CocxyColors.overlay2)
        }
    }

    /// The action text shown in the row.
    private var actionText: String {
        if let toolName = event.toolName {
            return event.isError ? "x \(toolName)" : toolName
        }
        return event.summary
    }

    /// Truncates a file path to show only the last path component.
    private func truncatedFilePath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Builds an accessibility description from event data.
    private var accessibilityDescription: String {
        var parts = [formattedTimestamp]
        if let toolName = event.toolName {
            parts.append(event.isError ? "Error: \(toolName)" : toolName)
        } else {
            parts.append(event.summary)
        }
        if let path = event.filePath {
            parts.append(truncatedFilePath(path))
        }
        parts.append(TimelineExporter.formatDuration(event.durationMs))
        return parts.joined(separator: ", ")
    }
}
