// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandDurationFormatter.swift - Formats command duration for display.

import Foundation

// MARK: - Command Duration Formatter

/// Formats a command duration (in seconds) into a human-readable string.
///
/// Rules:
/// - Under 1 second: display as milliseconds (e.g., "45ms").
/// - 1 to 59.9 seconds: display with one decimal (e.g., "5.4s").
/// - 60 seconds and above: display as minutes and seconds (e.g., "2m5s").
enum CommandDurationFormatter {

    /// Formats a duration in seconds into a compact, human-readable string.
    ///
    /// - Parameter seconds: The duration to format. Must be non-negative.
    /// - Returns: A formatted string (e.g., "45ms", "5.4s", "2m5s").
    static func format(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let totalSeconds = Int(seconds)
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            return "\(minutes)m\(remainingSeconds)s"
        }
    }
}
