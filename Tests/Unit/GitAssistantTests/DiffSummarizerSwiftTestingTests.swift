import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DiffSummarizer")
struct DiffSummarizerSwiftTestingTests {
    @Test("redacts common secrets and personal email before prompt construction")
    func redactsSecretsAndEmail() {
        let diff = """
        diff --git a/App.swift b/App.swift
        +let email = "owner@example.com"
        +let apiKey = "sk-live-1234567890abcdef"
        +let token = "ghp_abcdefghijklmnopqrstuvwxyz123456"
        +let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature"
        """

        let summary = DiffSummarizer(maxLines: 50).summarize(rawDiff: diff)

        #expect(summary.text.contains("[redacted-email]"))
        #expect(summary.text.contains("[redacted-secret]"))
        #expect(!summary.text.contains("owner@example.com"))
        #expect(!summary.text.contains("sk-live-1234567890abcdef"))
        #expect(!summary.text.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        #expect(!summary.text.contains("eyJhbGciOiJIUzI1NiJ9"))
    }

    @Test("truncates at file boundaries when the next file would exceed budget")
    func truncatesAtFileBoundaries() {
        let diff = """
        diff --git a/First.swift b/First.swift
        @@ -1,2 +1,2 @@
        -old
        +new
        diff --git a/Second.swift b/Second.swift
        @@ -1,3 +1,3 @@
        -second old
        +second new
        """

        let summary = DiffSummarizer(maxLines: 4).summarize(rawDiff: diff)

        #expect(summary.truncated)
        #expect(summary.includedFilePaths == ["First.swift"])
        #expect(summary.omittedFileCount == 1)
        #expect(summary.text.contains("First.swift"))
        #expect(summary.text.contains("[1 file omitted to keep the prompt within budget.]"))
        #expect(!summary.text.contains("second new"))
    }

    @Test("builds a compact summary from parsed file diffs")
    func summarizesParsedFileDiffs() {
        let diff = FileDiff(
            filePath: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(
                    header: "@@ -1,1 +1,1 @@",
                    oldStart: 1,
                    oldCount: 1,
                    newStart: 1,
                    newCount: 1,
                    lines: [
                        DiffLine(kind: .deletion, content: "oldValue()", oldLineNumber: 1, newLineNumber: nil),
                        DiffLine(kind: .addition, content: "newValue()", oldLineNumber: nil, newLineNumber: 1),
                    ]
                ),
            ]
        )

        let summary = DiffSummarizer(maxLines: 20).summarize(fileDiffs: [diff])

        #expect(summary.text.contains("diff --git a/Sources/App.swift b/Sources/App.swift"))
        #expect(summary.text.contains("-oldValue()"))
        #expect(summary.text.contains("+newValue()"))
        #expect(summary.additions == 1)
        #expect(summary.deletions == 1)
    }
}
