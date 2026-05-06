// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRRemoteReviewThreadSuggestionExtractor.swift - Extracts local suggestions from remote review threads.

import Foundation

enum PRRemoteReviewThreadSuggestionExtractor {
    static func suggestions(from thread: GitHubPullRequestReviewThread) -> [PRSuggestion] {
        let trimmedPath = thread.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, let lineRange = thread.lineRange else { return [] }

        return thread.comments.flatMap { comment in
            PRSuggestionExtractor.suggestions(from: ReviewComment(
                filePath: trimmedPath,
                lineRange: lineRange,
                body: comment.body,
                timestamp: comment.createdAt ?? Date(timeIntervalSince1970: 0)
            ))
        }
    }
}

extension GitHubPullRequestReviewThread {
    var reviewSuggestions: [PRSuggestion] {
        PRRemoteReviewThreadSuggestionExtractor.suggestions(from: self)
    }
}
