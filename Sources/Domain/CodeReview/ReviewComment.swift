// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ReviewComment.swift - Inline comment model for the code review panel.

import Foundation

struct ReviewComment: Identifiable, Sendable, Equatable {
    let id: UUID
    let filePath: String
    let lineRange: ClosedRange<Int>
    let body: String
    let timestamp: Date
    let reviewRoundID: Int?

    init(
        id: UUID = UUID(),
        filePath: String,
        lineRange: ClosedRange<Int>,
        body: String,
        timestamp: Date = Date(),
        reviewRoundID: Int? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.lineRange = lineRange
        self.body = body
        self.timestamp = timestamp
        self.reviewRoundID = reviewRoundID
    }

    var displayLineDescription: String {
        if lineRange.lowerBound == lineRange.upperBound {
            return "line \(lineRange.lowerBound)"
        }
        return "lines \(lineRange.lowerBound)-\(lineRange.upperBound)"
    }
}
