// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownParser")
struct MarkdownParserTests {

    let parser = MarkdownParser()

    // MARK: - Headings

    @Test("single H1 heading")
    func singleHeading() {
        let result = parser.parse("# Title")
        #expect(result.blocks == [
            .heading(level: 1, inlines: [.text("Title")])
        ])
    }

    @Test("H1 through H6 parse with correct levels")
    func allHeadingLevels() {
        let source = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let blocks = parser.parse(source).blocks
        let levels: [Int] = blocks.compactMap {
            if case .heading(let level, _) = $0 { return level }
            return nil
        }
        #expect(levels == [1, 2, 3, 4, 5, 6])
    }

    @Test("seven or more hashes is not a heading")
    func overflowHashes() {
        let blocks = parser.parse("####### not a heading").blocks
        #expect(blocks == [
            .paragraph(inlines: [.text("####### not a heading")])
        ])
    }

    // MARK: - Paragraphs

    @Test("multi-line paragraph joins lines into one block")
    func multilineParagraph() {
        let blocks = parser.parse("one\ntwo\nthree").blocks
        guard blocks.count == 1, case .paragraph(let inlines) = blocks[0] else {
            Issue.record("expected single paragraph")
            return
        }
        #expect(inlines.count == 1)
        #expect(inlines.first == .text("one\ntwo\nthree"))
    }

    @Test("blank line separates paragraphs")
    func blankLineSeparatesParagraphs() {
        let blocks = parser.parse("first\n\nsecond").blocks
        #expect(blocks.count == 2)
    }

    // MARK: - Fenced Code

    @Test("fenced code block captures language and content")
    func fencedCodeBlock() {
        let source = """
        ```swift
        let x = 1
        ```
        """
        let blocks = parser.parse(source).blocks
        #expect(blocks.count == 1)
        if case .codeBlock(let lang, let text) = blocks[0] {
            #expect(lang == "swift")
            #expect(text == "let x = 1")
        } else {
            Issue.record("expected codeBlock")
        }
    }

    @Test("fenced code block without language has nil language")
    func fencedCodeBlockNoLanguage() {
        let source = """
        ```
        raw
        ```
        """
        if case .codeBlock(let lang, _)? = parser.parse(source).blocks.first {
            #expect(lang == nil)
        } else {
            Issue.record("expected codeBlock")
        }
    }

    @Test("indented code block captures content")
    func indentedCodeBlock() {
        let source = "    code line\n    second"
        let blocks = parser.parse(source).blocks
        if case .codeBlock(let lang, let text)? = blocks.first {
            #expect(lang == nil)
            #expect(text == "code line\nsecond")
        } else {
            Issue.record("expected codeBlock")
        }
    }

    // MARK: - Lists

    @Test("unordered list with three items")
    func unorderedList() {
        let source = "- one\n- two\n- three"
        let blocks = parser.parse(source).blocks
        if case .list(let ordered, _, let items)? = blocks.first {
            #expect(ordered == false)
            #expect(items.count == 3)
        } else {
            Issue.record("expected list")
        }
    }

    @Test("ordered list preserves start number")
    func orderedListStart() {
        let source = "3. three\n4. four"
        let blocks = parser.parse(source).blocks
        if case .list(let ordered, let start, let items)? = blocks.first {
            #expect(ordered == true)
            #expect(start == 3)
            #expect(items.count == 2)
        } else {
            Issue.record("expected ordered list")
        }
    }

    @Test("task list items record checked state")
    func taskList() {
        let source = "- [ ] pending\n- [x] done"
        let blocks = parser.parse(source).blocks
        guard case .list(_, _, let items)? = blocks.first else {
            Issue.record("expected list"); return
        }
        #expect(items[0].taskState == .unchecked)
        #expect(items[1].taskState == .checked)
    }

    // MARK: - Blockquotes

    @Test("blockquote wraps inner blocks")
    func blockquote() {
        let source = "> quoted\n> line"
        let blocks = parser.parse(source).blocks
        if case .blockquote(let inner)? = blocks.first {
            #expect(inner.count == 1)
            if case .paragraph(let text)? = inner.first {
                #expect(text == [.text("quoted\nline")])
            }
        } else {
            Issue.record("expected blockquote")
        }
    }

    // MARK: - Tables

    @Test("GFM table with headers and rows")
    func gfmTable() {
        let source = """
        | a | b |
        | - | - |
        | 1 | 2 |
        | 3 | 4 |
        """
        let blocks = parser.parse(source).blocks
        if case .table(let headers, let alignments, let rows)? = blocks.first {
            #expect(headers.count == 2)
            #expect(alignments.count == 2)
            #expect(rows.count == 2)
        } else {
            Issue.record("expected table")
        }
    }

    @Test("table alignment markers produce alignments")
    func tableAlignments() {
        let source = """
        | left | center | right |
        | :- | :-: | -: |
        | a | b | c |
        """
        if case .table(_, let alignments, _)? = parser.parse(source).blocks.first {
            #expect(alignments == [.left, .center, .right])
        } else {
            Issue.record("expected table")
        }
    }

    // MARK: - Horizontal Rule

    @Test("horizontal rule recognized with dashes")
    func horizontalRuleDashes() {
        if case .horizontalRule? = parser.parse("---").blocks.first {
            // pass
        } else {
            Issue.record("expected horizontalRule")
        }
    }

    @Test("horizontal rule recognized with asterisks")
    func horizontalRuleAsterisks() {
        if case .horizontalRule? = parser.parse("***").blocks.first {
            // pass
        } else {
            Issue.record("expected horizontalRule")
        }
    }

    // MARK: - Block Locations

    @Test("block locations track starting lines")
    func blockLocations() {
        let source = """
        # first

        second paragraph
        """
        let result = parser.parse(source)
        #expect(result.locations.count == result.blocks.count)
        #expect(result.locations[0].startLine == 0)
        #expect(result.locations[1].startLine == 2)
    }
}
