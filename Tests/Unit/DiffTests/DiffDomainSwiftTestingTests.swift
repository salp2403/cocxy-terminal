// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Diff domain")
struct DiffDomainSwiftTestingTests {
    @Test("DiffLineKind is the shared line-kind API for parsed lines")
    func diffLineKindAPI() {
        let line = DiffLine(
            kind: DiffLineKind.addition,
            content: "new value",
            oldLineNumber: nil,
            newLineNumber: 12
        )

        #expect(line.kind == .addition)
        #expect(line.displayLineNumber == 12)
        #expect(line.isCommentable)
    }

    @Test("SplitDiffLayout pairs replacement blocks and preserves side-only rows")
    func splitLayoutPairsReplacementBlocks() {
        let hunk = DiffHunk(
            header: "@@ -7,4 +7,5 @@",
            oldStart: 7,
            oldCount: 4,
            newStart: 7,
            newCount: 5,
            lines: [
                DiffLine(kind: .context, content: "same", oldLineNumber: 7, newLineNumber: 7),
                DiffLine(kind: .deletion, content: "old one", oldLineNumber: 8, newLineNumber: nil),
                DiffLine(kind: .deletion, content: "old two", oldLineNumber: 9, newLineNumber: nil),
                DiffLine(kind: .addition, content: "new one", oldLineNumber: nil, newLineNumber: 8),
                DiffLine(kind: .context, content: "tail", oldLineNumber: 10, newLineNumber: 9),
                DiffLine(kind: .addition, content: "extra", oldLineNumber: nil, newLineNumber: 10),
            ]
        )

        let rows = SplitDiffLayout.rows(for: hunk)

        #expect(rows.count == 5)
        #expect(rows[0].left?.content == "same")
        #expect(rows[0].right?.content == "same")
        #expect(rows[1].left?.content == "old one")
        #expect(rows[1].right?.content == "new one")
        #expect(rows[1].isReplacement)
        #expect(rows[2].left?.content == "old two")
        #expect(rows[2].right == nil)
        #expect(rows[3].left?.content == "tail")
        #expect(rows[3].right?.content == "tail")
        #expect(rows[4].left == nil)
        #expect(rows[4].right?.content == "extra")
    }

    @Test("DiffStager builds explicit git apply plans for hunk operations")
    func stagerBuildsApplyPlans() throws {
        let hunk = DiffHunk(
            header: "@@ -1,1 +1,1 @@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1,
            lines: [
                DiffLine(kind: .deletion, content: "old", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(kind: .addition, content: "new", oldLineNumber: nil, newLineNumber: 1),
            ]
        )
        let fileDiff = FileDiff(
            filePath: "Sources/App/Main.swift",
            status: .modified,
            hunks: [hunk]
        )

        let stage = DiffStager.plan(action: .stage, fileDiff: fileDiff, hunk: hunk)
        let unstage = DiffStager.plan(action: .unstage, fileDiff: fileDiff, hunk: hunk)
        let discard = DiffStager.plan(action: .discard, fileDiff: fileDiff, hunk: hunk)

        #expect(stage.arguments == ["apply", "--cached", "--recount", "-"])
        #expect(unstage.arguments == ["apply", "--cached", "--reverse", "--recount", "-"])
        #expect(discard.arguments == ["apply", "--reverse", "--recount", "-"])
        #expect(stage.patch.contains("diff --git a/Sources/App/Main.swift b/Sources/App/Main.swift"))
        #expect(stage.stdin == stage.patch.data(using: .utf8))
    }

    @Test("DiffStager executes through an injectable runner")
    func stagerExecutesThroughRunner() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-diff-stager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let hunk = DiffHunk(
            header: "@@ -1,1 +1,1 @@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1,
            lines: [
                DiffLine(kind: .deletion, content: "old", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(kind: .addition, content: "new", oldLineNumber: nil, newLineNumber: 1),
            ]
        )
        let fileDiff = FileDiff(filePath: "Example.swift", status: .modified, hunks: [hunk])
        var capturedArguments: [String] = []
        var capturedWorkingDirectory: URL?
        var capturedStdin = Data()
        let stager = DiffStager { workingDirectory, arguments, stdin in
            capturedWorkingDirectory = workingDirectory
            capturedArguments = arguments
            capturedStdin = stdin
            return CodeReviewGitResult(stdout: "", stderr: "", terminationStatus: 0)
        }

        try stager.perform(
            action: .stage,
            fileDiff: fileDiff,
            hunk: hunk,
            workingDirectory: temporaryDirectory
        )

        #expect(capturedWorkingDirectory == temporaryDirectory)
        #expect(capturedArguments == ["apply", "--cached", "--recount", "-"])
        #expect(String(decoding: capturedStdin, as: UTF8.self).contains("Example.swift"))
    }
}
