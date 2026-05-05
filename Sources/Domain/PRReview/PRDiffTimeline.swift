// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRDiffTimeline.swift - Timeline summaries for pull request review diffs.

import Foundation

enum PRDiffTimelineEntryKind: Equatable, Sendable {
    case current
    case reviewRound(Int)
}

struct PRDiffTimelineEntry: Identifiable, Equatable, Sendable {
    let id: String
    let kind: PRDiffTimelineEntryKind
    let timestamp: Date?
    let fileCount: Int
    let hunkCount: Int
    let additions: Int
    let deletions: Int
    let commentCount: Int
    let baseRefShort: String?
}

enum PRDiffTimeline {
    static func entries(
        currentDiffs: [FileDiff],
        reviewRounds: [ReviewRound]
    ) -> [PRDiffTimelineEntry] {
        var entries: [PRDiffTimelineEntry] = []

        if !currentDiffs.isEmpty {
            entries.append(entry(id: "current", kind: .current, diffs: currentDiffs, comments: 0))
        }

        entries.append(contentsOf: reviewRounds
            .sorted { $0.timestamp > $1.timestamp }
            .map { round in
                entry(
                    id: "round-\(round.id)",
                    kind: .reviewRound(round.id),
                    timestamp: round.timestamp,
                    diffs: round.diffs,
                    comments: round.comments.count,
                    baseRef: round.baseRef
                )
            })

        return entries
    }

    private static func entry(
        id: String,
        kind: PRDiffTimelineEntryKind,
        timestamp: Date? = nil,
        diffs: [FileDiff],
        comments: Int,
        baseRef: String? = nil
    ) -> PRDiffTimelineEntry {
        PRDiffTimelineEntry(
            id: id,
            kind: kind,
            timestamp: timestamp,
            fileCount: diffs.count,
            hunkCount: diffs.reduce(0) { $0 + $1.hunks.count },
            additions: diffs.reduce(0) { $0 + $1.additions },
            deletions: diffs.reduce(0) { $0 + $1.deletions },
            commentCount: comments,
            baseRefShort: baseRef.flatMap(Self.shortRef)
        )
    }

    private static func shortRef(_ ref: String) -> String? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(7))
    }
}
