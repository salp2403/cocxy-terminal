// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("FeedbackFormatter")
struct FeedbackFormatterSwiftTestingTests {
    @Test("formats single comment")
    func singleComment() {
        let comments = [
            ReviewComment(filePath: "foo.swift", lineRange: 42...42, body: "Handle nil input")
        ]
        let result = FeedbackFormatter.format(comments)
        #expect(result.contains("foo.swift"))
        #expect(result.contains("line 42"))
        #expect(result.contains("Handle nil input"))
    }

    @Test("formats multiple comments grouped by file")
    func multipleComments() {
        let comments = [
            ReviewComment(filePath: "a.swift", lineRange: 10...10, body: "First"),
            ReviewComment(filePath: "b.swift", lineRange: 5...7, body: "Second"),
            ReviewComment(filePath: "a.swift", lineRange: 20...20, body: "Third"),
        ]
        let result = FeedbackFormatter.format(comments)
        let aIndex = result.range(of: "File: a.swift")!.lowerBound
        let firstIndex = result.range(of: "First")!.lowerBound
        let thirdIndex = result.range(of: "Third")!.lowerBound
        #expect(aIndex < firstIndex)
        #expect(firstIndex < thirdIndex)
    }

    @Test("formats line range correctly")
    func lineRange() {
        let comments = [
            ReviewComment(filePath: "x.swift", lineRange: 5...8, body: "Refactor this block")
        ]
        let result = FeedbackFormatter.format(comments)
        #expect(result.contains("lines 5-8"))
    }

    @Test("empty comments returns empty string")
    func emptyComments() {
        #expect(FeedbackFormatter.format([]).isEmpty)
    }
}
