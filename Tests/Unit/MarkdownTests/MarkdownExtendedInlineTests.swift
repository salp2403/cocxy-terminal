// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownExtendedInline")
struct MarkdownExtendedInlineTests {
    private let parser = MarkdownInlineParser()

    @Test("highlight parses as mark inline")
    func highlightInline() {
        #expect(parser.parse("==important==") == [.highlight(inlines: [.text("important")])])
    }

    @Test("superscript parses")
    func superscriptInline() {
        #expect(parser.parse("x^2^") == [.text("x"), .superscript(inlines: [.text("2")])])
    }

    @Test("subscript parses")
    func subscriptInline() {
        #expect(parser.parse("H~2~O") == [.text("H"), .`subscript`(inlines: [.text("2")]), .text("O")])
    }

    @Test("highlight can nest existing inline content")
    func highlightNesting() {
        #expect(parser.parse("==**bold**==") == [
            .highlight(inlines: [.strong(inlines: [.text("bold")])])
        ])
    }

    @Test("HTML renderer emits mark sup and sub tags")
    func htmlRendererEmitsExtendedInlineTags() {
        let document = MarkdownDocument.parse("==hi== x^2^ H~2~O")
        let html = MarkdownHTMLRenderer.renderDocument(document)

        #expect(html.contains("<mark>hi</mark>"))
        #expect(html.contains("<sup>2</sup>"))
        #expect(html.contains("<sub>2</sub>"))
    }
}
