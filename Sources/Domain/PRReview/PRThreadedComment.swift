// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRThreadedComment.swift - Local threaded review comments and suggestion extraction.

import Foundation

struct PRThreadedComment: Identifiable, Equatable, Sendable {
    let id: String
    let filePath: String
    let lineRange: ClosedRange<Int>
    let comments: [ReviewComment]
    let suggestions: [PRSuggestion]

    var rootComment: ReviewComment {
        comments[0]
    }

    var replies: [ReviewComment] {
        Array(comments.dropFirst())
    }
}

enum PRThreadedCommentBuilder {
    static func makeThreads(from comments: [ReviewComment]) -> [PRThreadedComment] {
        let grouped = Dictionary(grouping: comments) { comment in
            PRThreadKey(filePath: comment.filePath, lineRange: comment.lineRange)
        }

        return grouped.map { key, values in
            let sortedComments = values.sorted(by: reviewCommentSort)
            let suggestions = sortedComments.flatMap(PRSuggestionExtractor.suggestions)
            return PRThreadedComment(
                id: key.id,
                filePath: key.filePath,
                lineRange: key.lineRange,
                comments: sortedComments,
                suggestions: suggestions
            )
        }
        .sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath {
                return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
            }
            if lhs.lineRange.lowerBound != rhs.lineRange.lowerBound {
                return lhs.lineRange.lowerBound < rhs.lineRange.lowerBound
            }
            return lhs.rootComment.timestamp < rhs.rootComment.timestamp
        }
    }

    private static func reviewCommentSort(_ lhs: ReviewComment, _ rhs: ReviewComment) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct PRThreadKey: Hashable {
    let filePath: String
    let lineRange: ClosedRange<Int>

    var id: String {
        "\(filePath):\(lineRange.lowerBound)-\(lineRange.upperBound)"
    }
}

enum PRSuggestionExtractor {
    static func suggestions(from comment: ReviewComment) -> [PRSuggestion] {
        let pattern = #"(?s)```suggestion[^\r\n]*(?:\r?\n)(.*?)\r?\n```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let body = comment.body as NSString
        let range = NSRange(location: 0, length: body.length)

        return regex.matches(in: comment.body, range: range).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let replacementRange = match.range(at: 1)
            guard replacementRange.location != NSNotFound else { return nil }
            return PRSuggestion(
                filePath: comment.filePath,
                lineRange: comment.lineRange,
                replacementText: body.substring(with: replacementRange)
            )
        }
    }
}
