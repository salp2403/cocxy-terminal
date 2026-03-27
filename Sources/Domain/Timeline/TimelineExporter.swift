// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineExporter.swift - Export timeline events to JSON and Markdown.

import Foundation

// MARK: - Timeline Exporter

/// Exports timeline events to JSON and Markdown formats.
///
/// This is a stateless utility with static methods. All formatting
/// logic lives here to keep the store focused on storage.
///
/// ## JSON Format
///
/// Standard Codable serialization with pretty-printing and ISO 8601 dates.
///
/// ## Markdown Format
///
/// ```
/// ## Agent Timeline
///
/// | Time | Action | File | Duration |
/// |------|--------|------|----------|
/// | 14:32:01 | Write | Sources/App.swift | 120ms |
/// | 14:32:15 | Bash | npm test | 3.4s |
/// | 14:33:02 | x Edit | config.toml | -- |
/// ```
///
/// - SeeAlso: HU-109 (Timeline export)
enum TimelineExporter {

    // MARK: - JSON Export

    /// Exports events as formatted JSON.
    ///
    /// Uses ISO 8601 dates and pretty-printing for readability.
    ///
    /// - Parameter events: The events to export.
    /// - Returns: UTF-8 encoded JSON data. Returns empty JSON array if no events.
    static func exportJSON(events: [TimelineEvent]) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(events)
        } catch {
            // Fallback: empty array. This should never happen since
            // TimelineEvent fully conforms to Codable.
            return Data("[]".utf8)
        }
    }

    // MARK: - Markdown Export

    /// Exports events as a Markdown table.
    ///
    /// Each row shows the timestamp (HH:mm:ss), action name, file path
    /// (last component only), and formatted duration.
    ///
    /// Error events are prefixed with "x " in the Action column.
    ///
    /// - Parameter events: The events to export.
    /// - Returns: Markdown-formatted string. Returns empty string if no events.
    static func exportMarkdown(events: [TimelineEvent]) -> String {
        guard !events.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("## Agent Timeline")
        lines.append("")
        lines.append("| Time | Action | File | Duration |")
        lines.append("|------|--------|------|----------|")

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for event in events {
            let time = timeFormatter.string(from: event.timestamp)
            let action = formatAction(event)
            let file = formatFilePath(event)
            let duration = formatDuration(event.durationMs)

            lines.append("| \(time) | \(action) | \(file) | \(duration) |")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Duration Formatting

    /// Formats a duration in milliseconds to a human-readable string.
    ///
    /// - Less than 1000ms: "120ms"
    /// - 1000ms or more: "3.4s" (one decimal place)
    /// - Nil: "--"
    ///
    /// - Parameter durationMs: Duration in milliseconds, or nil.
    /// - Returns: Formatted duration string.
    static func formatDuration(_ durationMs: Int?) -> String {
        guard let ms = durationMs else { return "--" }

        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }

    // MARK: - Private Helpers

    /// Formats the action column for a timeline event.
    ///
    /// Uses the tool name if available, otherwise the event type summary.
    /// Error events are prefixed with "x ".
    private static func formatAction(_ event: TimelineEvent) -> String {
        let baseName: String
        if let toolName = event.toolName {
            baseName = toolName
        } else {
            baseName = formatEventTypeName(event.type)
        }

        if event.isError {
            return "x \(baseName)"
        }
        return baseName
    }

    /// Returns a human-readable name for a timeline event type.
    private static func formatEventTypeName(_ type: TimelineEventType) -> String {
        switch type {
        case .sessionStart:   return "Session Start"
        case .sessionEnd:     return "Session End"
        case .toolUse:        return "Tool Use"
        case .toolFailure:    return "Tool Failure"
        case .userPrompt:     return "User Prompt"
        case .agentResponse:  return "Agent Response"
        case .subagentStart:  return "Subagent Start"
        case .subagentStop:   return "Subagent Stop"
        case .notification:   return "Notification"
        case .taskCompleted:  return "Task Completed"
        case .stateChange:    return "State Change"
        }
    }

    /// Formats the file path column, showing only the last path component.
    ///
    /// Returns "--" if no file path is available.
    private static func formatFilePath(_ event: TimelineEvent) -> String {
        guard let path = event.filePath else { return "--" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
