// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownInlineParser")
struct MarkdownInlineParserTests {

    let parser = MarkdownInlineParser()

    @Test("empty input returns empty nodes")
    func emptyInput() {
        #expect(parser.parse("") == [])
    }

    @Test("plain text becomes a single text node")
    func plainText() {
        #expect(parser.parse("hello world") == [.text("hello world")])
    }

    @Test("adjacent text runs are flattened")
    func adjacentTextFlattened() {
        // `abc` with an escaped `*` still produces a single text node
        // because the escape is consumed and merged with the rest.
        #expect(parser.parse("a\\*b") == [.text("a*b")])
    }

    @Test("single asterisk produces emphasis")
    func singleAsterisk() {
        #expect(parser.parse("*italic*") == [
            .emphasis(inlines: [.text("italic")])
        ])
    }

    @Test("double asterisk produces strong")
    func doubleAsterisk() {
        #expect(parser.parse("**bold**") == [
            .strong(inlines: [.text("bold")])
        ])
    }

    @Test("triple asterisk produces strong wrapping emphasis")
    func tripleAsterisk() {
        #expect(parser.parse("***both***") == [
            .strong(inlines: [.emphasis(inlines: [.text("both")])])
        ])
    }

    @Test("underscore emphasis works outside word boundaries")
    func underscoreEmphasis() {
        #expect(parser.parse("_italic_") == [
            .emphasis(inlines: [.text("italic")])
        ])
    }

    @Test("underscore mid-word is literal")
    func underscoreMidWord() {
        let result = parser.parse("snake_case_name")
        #expect(result == [.text("snake_case_name")])
    }

    @Test("inline code strips matching backticks")
    func inlineCode() {
        #expect(parser.parse("`code`") == [.code(text: "code")])
    }

    @Test("inline code with double backticks allows single backtick content")
    func inlineCodeDoubleBackticks() {
        #expect(parser.parse("``a`b``") == [.code(text: "a`b")])
    }

    @Test("unmatched backtick is literal")
    func unmatchedBacktick() {
        #expect(parser.parse("`oops") == [.text("`oops")])
    }

    @Test("strikethrough requires double tildes")
    func strikethrough() {
        #expect(parser.parse("~~gone~~") == [
            .strike(inlines: [.text("gone")])
        ])
    }

    @Test("single tilde is literal")
    func singleTilde() {
        #expect(parser.parse("~nope~") == [.text("~nope~")])
    }

    @Test("inline link produces link node with URL")
    func inlineLink() {
        #expect(parser.parse("[Cocxy](https://cocxy.dev)") == [
            .link(text: [.text("Cocxy")], url: "https://cocxy.dev")
        ])
    }

    @Test("link with nested emphasis preserves inline tree")
    func linkWithEmphasis() {
        #expect(parser.parse("[**bold** link](https://x)") == [
            .link(
                text: [.strong(inlines: [.text("bold")]), .text(" link")],
                url: "https://x"
            )
        ])
    }

    @Test("autolink recognized for http URLs")
    func autolink() {
        #expect(parser.parse("<https://example.com>") == [
            .autolink(url: "https://example.com")
        ])
    }

    @Test("angle brackets without valid URL stay literal")
    func notAnAutolink() {
        #expect(parser.parse("<notreallyaurl>") == [.text("<notreallyaurl>")])
    }

    @Test("mixed content preserves order")
    func mixedContent() {
        let result = parser.parse("a **b** `c` ~~d~~ [e](f)")
        #expect(result == [
            .text("a "),
            .strong(inlines: [.text("b")]),
            .text(" "),
            .code(text: "c"),
            .text(" "),
            .strike(inlines: [.text("d")]),
            .text(" "),
            .link(text: [.text("e")], url: "f")
        ])
    }

    // MARK: - Images

    @Test("image syntax produces image inline")
    func imageInline() {
        let result = parser.parse("![alt text](image.png)")
        #expect(result == [.image(alt: "alt text", url: "image.png")])
    }

    @Test("image with empty alt")
    func imageEmptyAlt() {
        let result = parser.parse("![](photo.jpg)")
        #expect(result == [.image(alt: "", url: "photo.jpg")])
    }

    @Test("image mixed with text")
    func imageMixedWithText() {
        let result = parser.parse("See ![logo](logo.png) here")
        #expect(result.count == 3)
        #expect(result[0] == .text("See "))
        #expect(result[1] == .image(alt: "logo", url: "logo.png"))
        #expect(result[2] == .text(" here"))
    }

    @Test("link URL can contain balanced parentheses")
    func linkURLWithParentheses() {
        let result = parser.parse("[Docs](https://example.com/foo(bar)/baz)")
        #expect(result == [
            .link(text: [.text("Docs")], url: "https://example.com/foo(bar)/baz")
        ])
    }

    @Test("image URL can contain balanced parentheses")
    func imageURLWithParentheses() {
        let result = parser.parse("![diagram](assets/diagram (1).png)")
        #expect(result == [
            .image(alt: "diagram", url: "assets/diagram (1).png")
        ])
    }

    @Test("bare exclamation mark is text")
    func bareExclamation() {
        let result = parser.parse("Hello! World")
        #expect(result == [.text("Hello! World")])
    }
}
