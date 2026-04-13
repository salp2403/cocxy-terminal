// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownOutline")
struct MarkdownOutlineTests {

    @Test("outline extracts all heading levels")
    func extractAllHeadings() {
        let source = """
        # Root

        Some text

        ## Child A

        More text

        ### Grandchild

        ## Child B
        """
        let parseResult = MarkdownParser().parse(source)
        let outline = MarkdownOutline.extract(from: parseResult)

        #expect(outline.entries.count == 4)
        #expect(outline.entries.map(\.level) == [1, 2, 3, 2])
        #expect(outline.entries.map(\.title) == ["Root", "Child A", "Grandchild", "Child B"])
    }

    @Test("empty document yields empty outline")
    func emptyDocumentEmptyOutline() {
        let parseResult = MarkdownParser().parse("")
        #expect(MarkdownOutline.extract(from: parseResult).isEmpty == true)
    }

    @Test("document without headings yields empty outline")
    func noHeadingsEmptyOutline() {
        let parseResult = MarkdownParser().parse("just a paragraph")
        #expect(MarkdownOutline.extract(from: parseResult).isEmpty == true)
    }

    @Test("outline entries record source lines")
    func outlineRecordsSourceLines() {
        let source = """
        intro

        # Title

        body

        ## Sub
        """
        let parseResult = MarkdownParser().parse(source)
        let outline = MarkdownOutline.extract(from: parseResult)
        #expect(outline.entries[0].title == "Title")
        #expect(outline.entries[0].sourceLine == 2)
        #expect(outline.entries[1].sourceLine == 6)
    }

    @Test("tree view nests children under parents")
    func treeViewNesting() {
        let source = """
        # Root

        ## A

        ### A.1

        ## B
        """
        let tree = MarkdownOutline.extract(
            from: MarkdownParser().parse(source)
        ).tree()

        #expect(tree.count == 1)
        #expect(tree[0].entry.title == "Root")
        #expect(tree[0].children.count == 2)
        #expect(tree[0].children[0].entry.title == "A")
        #expect(tree[0].children[0].children.count == 1)
        #expect(tree[0].children[0].children[0].entry.title == "A.1")
        #expect(tree[0].children[1].entry.title == "B")
    }

    @Test("inline markup in headings is flattened to plain text")
    func inlineMarkupFlattened() {
        let source = "# **bold** and *italic*"
        let outline = MarkdownOutline.extract(
            from: MarkdownParser().parse(source)
        )
        #expect(outline.entries.first?.title == "bold and italic")
    }
}
