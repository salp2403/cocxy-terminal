// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownFileSearchTests.swift - Tests for multi-file markdown search.

import Testing
import Foundation
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownFileSearch")
struct MarkdownFileSearchTests {

    @Test("Empty query returns empty results")
    func emptyQuery() {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let results = MarkdownFileSearch.search(query: "", in: dir)
        #expect(results.isEmpty)
    }

    @Test("Search finds matching text in a file")
    func findsMatchingText() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "# Hello World\n\nThis is a test.".write(
            to: dir.appendingPathComponent("doc.md"),
            atomically: true, encoding: .utf8
        )

        let results = MarkdownFileSearch.search(query: "Hello", in: dir)
        #expect(results.count == 1)
        #expect(results[0].fileName == "doc.md")
        #expect(results[0].lineNumber == 1)
        #expect(results[0].lineText == "# Hello World")
    }

    @Test("Search is case-insensitive")
    func caseInsensitive() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "ABC def GHI".write(
            to: dir.appendingPathComponent("file.md"),
            atomically: true, encoding: .utf8
        )

        let results = MarkdownFileSearch.search(query: "abc", in: dir)
        #expect(results.count == 1)

        let results2 = MarkdownFileSearch.search(query: "DEF", in: dir)
        #expect(results2.count == 1)
    }

    @Test("Search finds matches across multiple files")
    func multipleFiles() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "match here".write(to: dir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "no content".write(to: dir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "another match".write(to: dir.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)

        let results = MarkdownFileSearch.search(query: "match", in: dir)
        #expect(results.count == 2)
        let fileNames = Set(results.map(\.fileName))
        #expect(fileNames.contains("a.md"))
        #expect(fileNames.contains("c.md"))
    }

    @Test("Search respects maxResults limit")
    func maxResultsLimit() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let lines = (1...50).map { "match line \($0)" }.joined(separator: "\n")
        try lines.write(to: dir.appendingPathComponent("big.md"), atomically: true, encoding: .utf8)

        let results = MarkdownFileSearch.search(query: "match", in: dir, maxResults: 5)
        #expect(results.count == 5)
    }

    @Test("Search ignores non-markdown files")
    func ignoresNonMd() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "match".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "match".write(to: dir.appendingPathComponent("file.md"), atomically: true, encoding: .utf8)

        let results = MarkdownFileSearch.search(query: "match", in: dir)
        #expect(results.count == 1)
        #expect(results[0].fileName == "file.md")
    }

    @Test("Search finds matches in subdirectories")
    func subdirectories() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let sub = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "deep match".write(to: sub.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)

        let results = MarkdownFileSearch.search(query: "deep", in: dir)
        #expect(results.count == 1)
        #expect(results[0].fileName == "nested.md")
    }

    @Test("Search skips hidden files")
    func skipsHidden() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "match".write(to: dir.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try "match".write(to: dir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let results = MarkdownFileSearch.search(query: "match", in: dir)
        #expect(results.count == 1)
        #expect(results[0].fileName == "visible.md")
    }

    @Test("Multiple matches in same file return correct line numbers")
    func multipleMatchesSameFile() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "first match\nnope\nsecond match\nnope\nthird match".write(
            to: dir.appendingPathComponent("multi.md"),
            atomically: true, encoding: .utf8
        )

        let results = MarkdownFileSearch.search(query: "match", in: dir)
        #expect(results.count == 3)
        #expect(results[0].lineNumber == 1)
        #expect(results[1].lineNumber == 3)
        #expect(results[2].lineNumber == 5)
    }

    @Test("Results are sorted by file name then line number")
    func resultsSortedByFileNameThenLine() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        // Create files with names that would sort differently than filesystem order
        try "match Z".write(to: dir.appendingPathComponent("zzz.md"), atomically: true, encoding: .utf8)
        try "match A line 2\nmatch A line 1".write(to: dir.appendingPathComponent("aaa.md"), atomically: true, encoding: .utf8)
        try "match M".write(to: dir.appendingPathComponent("mmm.md"), atomically: true, encoding: .utf8)

        let results = MarkdownFileSearch.search(query: "match", in: dir)
        #expect(results.count == 4)

        // Verify sorted by file name first
        #expect(results[0].fileName == "aaa.md")
        #expect(results[1].fileName == "aaa.md")
        #expect(results[2].fileName == "mmm.md")
        #expect(results[3].fileName == "zzz.md")

        // Verify sorted by line number within same file
        #expect(results[0].lineNumber == 1)
        #expect(results[1].lineNumber == 2)
    }

    // MARK: - Helpers

    private func createTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-search-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
