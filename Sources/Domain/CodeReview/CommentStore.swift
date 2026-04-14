// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommentStore.swift - Pending and submitted review comment state.

import Combine
import Foundation

@MainActor
final class CommentStore: ObservableObject {
    @Published private(set) var pendingComments: [ReviewComment] = []
    @Published private(set) var reviewRounds: [ReviewRound] = []

    var allComments: [ReviewComment] {
        pendingComments
    }

    func add(_ comment: ReviewComment) {
        pendingComments.append(comment)
        pendingComments.sort {
            if $0.filePath != $1.filePath {
                return $0.filePath.localizedCaseInsensitiveCompare($1.filePath) == .orderedAscending
            }
            if $0.lineRange.lowerBound != $1.lineRange.lowerBound {
                return $0.lineRange.lowerBound < $1.lineRange.lowerBound
            }
            return $0.timestamp < $1.timestamp
        }
    }

    func remove(id: UUID) {
        pendingComments.removeAll { $0.id == id }
    }

    func clearAll() {
        pendingComments.removeAll()
    }

    func comments(for filePath: String) -> [ReviewComment] {
        pendingComments.filter { $0.filePath == filePath }
    }

    func comments(for filePath: String, line: Int) -> [ReviewComment] {
        pendingComments.filter { $0.filePath == filePath && $0.lineRange.contains(line) }
    }

    func commentCount(for filePath: String) -> Int {
        comments(for: filePath).count
    }

    @discardableResult
    func archivePendingComments(
        nextRoundID: Int,
        baseRef: String,
        diffs: [FileDiff]
    ) -> ReviewRound? {
        guard !pendingComments.isEmpty else { return nil }
        let roundComments = pendingComments.map {
            ReviewComment(
                id: $0.id,
                filePath: $0.filePath,
                lineRange: $0.lineRange,
                body: $0.body,
                timestamp: $0.timestamp,
                reviewRoundID: nextRoundID
            )
        }
        let round = ReviewRound(
            id: nextRoundID,
            timestamp: Date(),
            baseRef: baseRef,
            diffs: diffs,
            comments: roundComments
        )
        reviewRounds.append(round)
        pendingComments.removeAll()
        return round
    }
}
