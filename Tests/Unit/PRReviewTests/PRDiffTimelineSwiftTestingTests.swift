// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRDiffTimelineSwiftTestingTests.swift - PR review diff timeline tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PR diff timeline")
struct PRDiffTimelineSwiftTestingTests {

    @Test("timeline starts with current diff and then newest review rounds")
    func timelineStartsWithCurrentDiffAndNewestRounds() {
        let olderRound = ReviewRound(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 100),
            baseRef: "abcdef123456",
            diffs: [Self.fileDiff(path: "Sources/App.swift", additions: 2, deletions: 1)],
            comments: [ReviewComment(filePath: "Sources/App.swift", lineRange: 4...4, body: "Handle nil")]
        )
        let newerRound = ReviewRound(
            id: 2,
            timestamp: Date(timeIntervalSince1970: 200),
            baseRef: "1234567890ab",
            diffs: [Self.fileDiff(path: "Sources/View.swift", additions: 1, deletions: 0)],
            comments: []
        )

        let entries = PRDiffTimeline.entries(
            currentDiffs: [Self.fileDiff(path: "Sources/App.swift", additions: 3, deletions: 2)],
            reviewRounds: [olderRound, newerRound]
        )

        #expect(entries.map(\.id) == ["current", "round-2", "round-1"])
        #expect(entries[0].kind == .current)
        #expect(entries[0].additions == 3)
        #expect(entries[0].deletions == 2)
        #expect(entries[0].commentCount == 0)
        #expect(entries[1].kind == .reviewRound(2))
        #expect(entries[1].baseRefShort == "1234567")
        #expect(entries[2].commentCount == 1)
    }

    @Test("empty current diff is omitted when there are historical rounds")
    func emptyCurrentDiffIsOmitted() {
        let round = ReviewRound(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 100),
            baseRef: "abcdef123456",
            diffs: [Self.fileDiff(path: "Sources/App.swift", additions: 1, deletions: 0)],
            comments: []
        )

        let entries = PRDiffTimeline.entries(currentDiffs: [], reviewRounds: [round])

        #expect(entries.map(\.id) == ["round-1"])
        #expect(entries[0].fileCount == 1)
        #expect(entries[0].hunkCount == 1)
    }

    private static func fileDiff(path: String, additions: Int, deletions: Int) -> FileDiff {
        var lines: [DiffLine] = []
        lines.append(contentsOf: (0..<additions).map { index in
            DiffLine(kind: .addition, content: "+\(index)", oldLineNumber: nil, newLineNumber: index + 1)
        })
        lines.append(contentsOf: (0..<deletions).map { index in
            DiffLine(kind: .deletion, content: "-\(index)", oldLineNumber: index + 1, newLineNumber: nil)
        })

        return FileDiff(
            filePath: path,
            status: .modified,
            hunks: [
                DiffHunk(
                    header: "@@ -1,\(deletions) +1,\(additions) @@",
                    oldStart: 1,
                    oldCount: deletions,
                    newStart: 1,
                    newCount: additions,
                    lines: lines
                ),
            ]
        )
    }
}
