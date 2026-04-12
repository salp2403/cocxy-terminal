// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownGitServiceTests.swift - Tests for git blame/diff parsing.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("MarkdownGitService")
struct MarkdownGitServiceTests {

    // MARK: - Blame Parsing

    @Test("parseBlameOutput returns empty for empty input")
    func parseBlameOutputEmpty() {
        let results = MarkdownGitService.parseBlameOutput("")
        #expect(results.isEmpty)
    }

    @Test("parseBlameOutput parses porcelain format")
    func parseBlameOutputPorcelain() {
        let output = """
        abc1234567890abcdef1234567890abcdef123456 1 1 1
        author John Doe
        author-mail <john@example.com>
        author-time 1700000000
        author-tz +0000
        committer John Doe
        committer-mail <john@example.com>
        committer-time 1700000000
        committer-tz +0000
        summary Initial commit
        filename README.md
        \t# Hello World
        """

        let results = MarkdownGitService.parseBlameOutput(output)
        #expect(results.count == 1)
        #expect(results[0].commitHash == "abc12345")
        #expect(results[0].author == "John Doe")
        #expect(results[0].lineNumber == 1)
        #expect(results[0].content == "# Hello World")
    }

    @Test("parseBlameOutput handles multiple lines")
    func parseBlameOutputMultipleLines() {
        let output = """
        abc1234567890abcdef1234567890abcdef123456 1 1 2
        author Alice
        author-time 1700000000
        \tLine one
        abc1234567890abcdef1234567890abcdef123456 2 2
        author Alice
        author-time 1700000000
        \tLine two
        """

        let results = MarkdownGitService.parseBlameOutput(output)
        #expect(results.count == 2)
        #expect(results[0].content == "Line one")
        #expect(results[1].content == "Line two")
        #expect(results[0].lineNumber == 1)
        #expect(results[1].lineNumber == 2)
    }

    // MARK: - Diff Parsing

    @Test("parseDiffOutput returns empty for empty input")
    func parseDiffOutputEmpty() {
        let hunks = MarkdownGitService.parseDiffOutput("")
        #expect(hunks.isEmpty)
    }

    @Test("parseDiffOutput parses a single hunk")
    func parseDiffOutputSingleHunk() {
        let output = """
        diff --git a/file.md b/file.md
        index abc1234..def5678 100644
        --- a/file.md
        +++ b/file.md
        @@ -1,3 +1,4 @@
         context line
        -removed line
        +added line
        +another new line
         more context
        """

        let hunks = MarkdownGitService.parseDiffOutput(output)
        #expect(hunks.count == 1)
        #expect(hunks[0].header.hasPrefix("@@ -1,3 +1,4 @@"))
        #expect(hunks[0].lines.count == 5)

        #expect(hunks[0].lines[0].type == .context)
        #expect(hunks[0].lines[0].text == "context line")

        #expect(hunks[0].lines[1].type == .deletion)
        #expect(hunks[0].lines[1].text == "removed line")

        #expect(hunks[0].lines[2].type == .addition)
        #expect(hunks[0].lines[2].text == "added line")

        #expect(hunks[0].lines[3].type == .addition)
        #expect(hunks[0].lines[3].text == "another new line")

        #expect(hunks[0].lines[4].type == .context)
        #expect(hunks[0].lines[4].text == "more context")
    }

    @Test("parseDiffOutput handles multiple hunks")
    func parseDiffOutputMultipleHunks() {
        let output = """
        @@ -1,2 +1,2 @@
        -old
        +new
        @@ -10,2 +10,2 @@
        -old2
        +new2
        """

        let hunks = MarkdownGitService.parseDiffOutput(output)
        #expect(hunks.count == 2)
        #expect(hunks[0].lines.count == 2)
        #expect(hunks[1].lines.count == 2)
    }

    @Test("GitDiffLine types are correct")
    func diffLineTypes() {
        let addition = GitDiffLine(type: .addition, text: "new")
        let deletion = GitDiffLine(type: .deletion, text: "old")
        let context = GitDiffLine(type: .context, text: "same")

        #expect(addition.type == .addition)
        #expect(deletion.type == .deletion)
        #expect(context.type == .context)
        #expect(addition != deletion)
    }

    @Test("GitBlameLine equatable")
    func blameLineEquatable() {
        let a = GitBlameLine(commitHash: "abc", author: "Alice", date: "2024-01-01", lineNumber: 1, content: "x")
        let b = GitBlameLine(commitHash: "abc", author: "Alice", date: "2024-01-01", lineNumber: 1, content: "x")
        let c = GitBlameLine(commitHash: "def", author: "Bob", date: "2024-01-02", lineNumber: 2, content: "y")

        #expect(a == b)
        #expect(a != c)
    }
}
