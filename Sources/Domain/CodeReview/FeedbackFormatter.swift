// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FeedbackFormatter.swift - Formats inline comments into agent-readable feedback.

import Foundation

enum FeedbackFormatter {
    static func format(_ comments: [ReviewComment]) -> String {
        guard !comments.isEmpty else { return "" }

        let grouped = Dictionary(grouping: comments) { $0.filePath }
        let sortedFiles = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var lines: [String] = [
            "Please address these code review comments carefully:",
            ""
        ]

        for (index, file) in sortedFiles.enumerated() {
            guard let fileComments = grouped[file] else { continue }
            if index > 0 {
                lines.append("")
            }

            lines.append("File: \(file)")
            let sortedComments = fileComments.sorted {
                if $0.lineRange.lowerBound != $1.lineRange.lowerBound {
                    return $0.lineRange.lowerBound < $1.lineRange.lowerBound
                }
                return $0.timestamp < $1.timestamp
            }

            for comment in sortedComments {
                lines.append("- \(comment.displayLineDescription): \(comment.body)")
            }
        }

        lines.append("")
        lines.append("After fixing them, please summarize what changed.")
        return lines.joined(separator: "\n")
    }
}
