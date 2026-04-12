// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownFootnote")
struct MarkdownFootnoteTests {
    private let parser = MarkdownParser()

    @Test("inline footnote reference parses")
    func inlineFootnoteReferenceParses() {
        let inlines = MarkdownInlineParser().parse("Look[^1]")
        #expect(inlines == [.text("Look"), .footnoteRef(id: "1")])
    }

    @Test("footnote definition parses as block")
    func footnoteDefinitionParses() {
        let result = parser.parse("[^1]: Footnote body")
        #expect(result.blocks == [
            .footnoteDefinition(id: "1", blocks: [.paragraph(inlines: [.text("Footnote body")])])
        ])
    }

    @Test("footnote HTML includes refs section and preview data")
    func footnoteHTMLIncludesSectionAndPreviewData() {
        let document = MarkdownDocument.parse("Hello[^1]\n\n[^1]: Footnote body")
        let html = MarkdownHTMLRenderer.renderDocument(document)

        #expect(html.contains("class=\"footnote-ref\""))
        #expect(html.contains("data-footnote-preview=\"Footnote body\""))
        #expect(html.contains("<section class=\"footnotes\">"))
        #expect(html.contains("id=\"fn-1\""))
        #expect(html.contains("href=\"#fnref-1\""))
    }

    @Test("footnote anchor ID sanitizes mixed identifiers")
    func footnoteAnchorIDSanitizes() {
        #expect(MarkdownFootnote.anchorID(for: "Release Note 1") == "release-note-1")
    }
}
