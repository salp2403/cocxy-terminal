// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("CodeReview Models")
struct CodeReviewModelsTests {
    @Test("FileDiff computes additions and deletions")
    func fileDiffStats() {
        let hunk = DiffHunk(
            header: "@@ -1,3 +1,4 @@",
            oldStart: 1,
            oldCount: 3,
            newStart: 1,
            newCount: 4,
            lines: [
                DiffLine(kind: .context, content: "line1", oldLineNumber: 1, newLineNumber: 1),
                DiffLine(kind: .addition, content: "new", oldLineNumber: nil, newLineNumber: 2),
                DiffLine(kind: .deletion, content: "old", oldLineNumber: 2, newLineNumber: nil),
                DiffLine(kind: .context, content: "line3", oldLineNumber: 3, newLineNumber: 3),
            ]
        )
        let diff = FileDiff(filePath: "foo.swift", status: .modified, hunks: [hunk])
        #expect(diff.additions == 1)
        #expect(diff.deletions == 1)
        #expect(diff.id == "foo.swift")
    }
}

@Suite("DiffParser")
struct DiffParserSwiftTestingTests {
    @Test("parses multi-file unified diff with line numbers")
    func parseMultiFile() {
        let raw = """
        diff --git a/foo.swift b/foo.swift
        index abc..def 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,4 @@
         unchanged
        +added line
         also unchanged
        -removed line
        diff --git a/bar.swift b/bar.swift
        new file mode 100644
        --- /dev/null
        +++ b/bar.swift
        @@ -0,0 +1,2 @@
        +first line
        +second line
        """
        let result = DiffParser.parse(raw)
        #expect(result.count == 2)
        #expect(result[0].filePath == "foo.swift")
        #expect(result[0].status == .modified)
        #expect(result[0].hunks.count == 1)
        #expect(result[0].hunks[0].lines.count == 4)
        #expect(result[1].filePath == "bar.swift")
        #expect(result[1].status == .added)
        #expect(result[1].additions == 2)
    }

    @Test("assigns correct line numbers to context addition and deletion")
    func lineNumbers() {
        let raw = """
        diff --git a/x.swift b/x.swift
        --- a/x.swift
        +++ b/x.swift
        @@ -10,4 +10,5 @@
         context
        -old
        +new1
        +new2
         context2
        """
        let diffs = DiffParser.parse(raw)
        let lines = diffs[0].hunks[0].lines
        #expect(lines[0].oldLineNumber == 10)
        #expect(lines[0].newLineNumber == 10)
        #expect(lines[1].oldLineNumber == 11)
        #expect(lines[1].newLineNumber == nil)
        #expect(lines[2].oldLineNumber == nil)
        #expect(lines[2].newLineNumber == 11)
        #expect(lines[3].oldLineNumber == nil)
        #expect(lines[3].newLineNumber == 12)
        #expect(lines[4].oldLineNumber == 12)
        #expect(lines[4].newLineNumber == 13)
    }

    @Test("parses deleted file")
    func deletedFile() {
        let raw = """
        diff --git a/gone.swift b/gone.swift
        deleted file mode 100644
        --- a/gone.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -line1
        -line2
        """
        let diffs = DiffParser.parse(raw)
        #expect(diffs.count == 1)
        #expect(diffs[0].status == .deleted)
        #expect(diffs[0].deletions == 2)
    }

    @Test("empty input returns empty array")
    func emptyInput() {
        #expect(DiffParser.parse("").isEmpty)
        #expect(DiffParser.parse("   \n  ").isEmpty)
    }

    @Test("porcelain status parser handles untracked rename and modified")
    func parseStatus() {
        let raw = """
         M foo.swift
        R  old.swift -> new.swift
        ?? scratch.swift
        """
        let parsed = DiffParser.parseStatus(raw)
        #expect(parsed.count == 3)
        #expect(parsed[0].path == "foo.swift")
        #expect(parsed[0].status == .modified)
        #expect(parsed[1].path == "new.swift")
        #expect(parsed[1].status == .renamed)
        #expect(parsed[2].path == "scratch.swift")
        #expect(parsed[2].status == .untracked)
    }

    @Test("porcelain status parser handles composite index and worktree markers")
    func parseCompositeStatusMarkers() {
        let raw = """
        MM dirty.swift
        AD removed-after-add.swift
        AM added-then-edited.swift
        RM renamed-and-edited.swift -> renamed.swift
        """

        let parsed = DiffParser.parseStatus(raw)
        #expect(parsed.count == 4)
        #expect(parsed[0].path == "dirty.swift")
        #expect(parsed[0].status == .modified)
        #expect(parsed[1].path == "removed-after-add.swift")
        #expect(parsed[1].status == .deleted)
        #expect(parsed[2].path == "added-then-edited.swift")
        #expect(parsed[2].status == .added)
        #expect(parsed[3].path == "renamed.swift")
        #expect(parsed[3].status == .renamed)
    }

    @Test("binary diff surfaces an explicit review note")
    func parseBinaryDiff() {
        let raw = """
        diff --git a/Assets/logo.png b/Assets/logo.png
        Binary files a/Assets/logo.png and b/Assets/logo.png differ
        """

        let diffs = DiffParser.parse(raw)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "Assets/logo.png")
        #expect(diffs[0].hunks.isEmpty)
        #expect(diffs[0].reviewNote?.contains("Binary file changed") == true)
    }

    @Test("malformed hunk headers preserve the file and emit a recovery note")
    func malformedHunkHeader() {
        let raw = """
        diff --git a/foo.swift b/foo.swift
        --- a/foo.swift
        +++ b/foo.swift
        @@ this is not a valid hunk header @@
        +line that cannot be mapped
        """

        let diffs = DiffParser.parse(raw)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "foo.swift")
        #expect(diffs[0].hunks.isEmpty)
        #expect(diffs[0].reviewNote?.contains("could not be parsed") == true)
    }

    @Test("timestamp suffixes are stripped from --- and +++ path lines")
    func parseTimestampedPaths() {
        let raw = """
        diff --git a/foo.swift b/foo.swift
        --- a/foo.swift\t2026-04-13 12:00:00
        +++ b/foo.swift\t2026-04-13 12:00:01
        @@ -1 +1 @@
        -old
        +new
        """

        let diffs = DiffParser.parse(raw)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "foo.swift")
        #expect(diffs[0].hunks.count == 1)
    }

    @Test("rename headers preserve both original and new paths")
    func parseRenameHeaders() {
        let raw = """
        diff --git a/old.swift b/new.swift
        similarity index 88%
        rename from old.swift
        rename to new.swift
        --- a/old.swift
        +++ b/new.swift
        @@ -1 +1,2 @@
         one
        +two
        """

        let diffs = DiffParser.parse(raw)
        #expect(diffs.count == 1)
        #expect(diffs[0].status == .renamed)
        #expect(diffs[0].originalFilePath == "old.swift")
        #expect(diffs[0].filePath == "new.swift")
        #expect(diffs[0].hunks.count == 1)
    }

    @Test("hunk headers without explicit counts default to one line")
    func parseImplicitCounts() {
        let raw = """
        diff --git a/foo.swift b/foo.swift
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1 +1 @@
        -old
        +new
        """

        let diffs = DiffParser.parse(raw)
        #expect(diffs.count == 1)
        #expect(diffs[0].hunks[0].oldCount == 1)
        #expect(diffs[0].hunks[0].newCount == 1)
    }
}
