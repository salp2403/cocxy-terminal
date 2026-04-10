// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {

    @Test("parse empty string yields empty document")
    func parseEmpty() {
        let doc = MarkdownDocument.parse("")
        #expect(doc.isEmpty == true)
        #expect(doc.frontmatter.isEmpty == true)
        #expect(doc.outline.isEmpty == true)
    }

    @Test("parse simple document populates blocks and outline")
    func parseSimpleDocument() {
        let source = """
        # Title

        Body paragraph with **bold**.
        """
        let doc = MarkdownDocument.parse(source)
        #expect(doc.parseResult.blocks.count == 2)
        #expect(doc.outline.entries.count == 1)
        #expect(doc.outline.entries.first?.title == "Title")
    }

    @Test("parse document with frontmatter extracts metadata and body")
    func parseWithFrontmatter() {
        let source = """
        ---
        title: Doc
        tags: [a, b]
        ---
        # Body
        """
        let doc = MarkdownDocument.parse(source)
        #expect(doc.frontmatter.scalars["title"] == "Doc")
        #expect(doc.frontmatter.lists["tags"] == ["a", "b"])
        #expect(doc.outline.entries.first?.title == "Body")
    }

    @Test("sourceLine adjusts for frontmatter offset")
    func sourceLineOffset() {
        let source = """
        ---
        title: X
        ---
        paragraph
        """
        let doc = MarkdownDocument.parse(source)
        #expect(doc.bodyLineOffset == 3)
        #expect(doc.sourceLine(forBodyLine: 0) == 3)
    }

    @Test("empty singleton document is idempotent")
    func emptySingleton() {
        #expect(MarkdownDocument.empty.isEmpty == true)
    }

    @Test("parse is pure: identical input yields identical output")
    func parseIsPure() {
        let source = "# Hello\n\nworld"
        #expect(MarkdownDocument.parse(source) == MarkdownDocument.parse(source))
    }
}
