// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownWordCountTests.swift - Tests for word/character/line counting.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownWordCount")
struct MarkdownWordCountTests {

    @Test("Empty body returns zero counts")
    func emptyBody() {
        let result = MarkdownWordCount.count(body: "")
        #expect(result == .zero)
        #expect(result.words == 0)
        #expect(result.characters == 0)
        #expect(result.lines == 0)
    }

    @Test("Whitespace-only body returns zero counts")
    func whitespaceOnlyBody() {
        let result = MarkdownWordCount.count(body: "   \n\n  \t  ")
        #expect(result == .zero)
    }

    @Test("Single word")
    func singleWord() {
        let result = MarkdownWordCount.count(body: "Hello")
        #expect(result.words == 1)
        #expect(result.characters == 5)
        #expect(result.lines == 1)
    }

    @Test("Multiple words on single line")
    func multipleWordsOneLine() {
        let result = MarkdownWordCount.count(body: "Hello world foo")
        #expect(result.words == 3)
        #expect(result.characters == 15)
        #expect(result.lines == 1)
    }

    @Test("Multiple lines")
    func multipleLines() {
        let body = "Line one\nLine two\nLine three"
        let result = MarkdownWordCount.count(body: body)
        #expect(result.words == 6)
        #expect(result.lines == 3)
    }

    @Test("Markdown formatting does not affect word count")
    func markdownFormatting() {
        let body = "**bold** and *italic* text"
        let result = MarkdownWordCount.count(body: body)
        #expect(result.words == 4)
    }

    @Test("Code block content is counted")
    func codeBlockCounted() {
        let body = "```swift\nlet x = 1\n```"
        let result = MarkdownWordCount.count(body: body)
        // ```swift, let, x, =, 1, ``` → 6 tokens split by whitespace
        #expect(result.words == 6)
        #expect(result.lines == 3)
    }

    @Test("Trailing newlines contribute to line count")
    func trailingNewlines() {
        let body = "Hello\n\n"
        let result = MarkdownWordCount.count(body: body)
        #expect(result.words == 1)
        #expect(result.lines == 3) // "Hello", "", ""
    }

    @Test("Unicode characters are counted correctly")
    func unicodeCharacters() {
        let body = "café résumé naïve"
        let result = MarkdownWordCount.count(body: body)
        #expect(result.words == 3)
        #expect(result.characters == 17)
    }

    @Test("Zero static value")
    func zeroStatic() {
        #expect(MarkdownWordCount.zero.words == 0)
        #expect(MarkdownWordCount.zero.characters == 0)
        #expect(MarkdownWordCount.zero.lines == 0)
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = MarkdownWordCount(words: 10, characters: 50, lines: 3)
        let b = MarkdownWordCount(words: 10, characters: 50, lines: 3)
        let c = MarkdownWordCount(words: 11, characters: 50, lines: 3)
        #expect(a == b)
        #expect(a != c)
    }
}
