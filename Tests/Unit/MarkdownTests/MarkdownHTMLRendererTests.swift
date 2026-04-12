// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownHTMLRendererTests.swift - Tests for AST-to-HTML conversion.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownHTMLRenderer")
struct MarkdownHTMLRendererTests {

    private func parse(_ source: String) -> MarkdownParseResult {
        MarkdownParser().parse(source)
    }

    // MARK: - Headings

    @Test("headings render as h1-h6 with correct level")
    func headingsRenderCorrectLevel() {
        let result = parse("# Title\n## Subtitle\n### H3")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<h2>Subtitle</h2>"))
        #expect(html.contains("<h3>H3</h3>"))
    }

    // MARK: - Paragraphs

    @Test("paragraphs wrap in p tags")
    func paragraphsWrapInPTags() {
        let result = parse("Hello world")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<p>Hello world</p>"))
    }

    // MARK: - Inline Formatting

    @Test("bold text renders as strong")
    func boldRendersAsStrong() {
        let result = parse("**bold**")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<strong>bold</strong>"))
    }

    @Test("italic text renders as em")
    func italicRendersAsEm() {
        let result = parse("*italic*")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<em>italic</em>"))
    }

    @Test("inline code renders as code")
    func inlineCodeRendersAsCode() {
        let result = parse("`hello`")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<code>hello</code>"))
    }

    @Test("strikethrough renders as del")
    func strikethroughRendersAsDel() {
        let result = parse("~~deleted~~")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<del>deleted</del>"))
    }

    @Test("links render as anchor tags")
    func linksRenderAsAnchor() {
        let result = parse("[Cocxy](https://cocxy.dev)")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<a href=\"https://cocxy.dev\">Cocxy</a>"))
    }

    // MARK: - Code Blocks

    @Test("fenced code block renders as pre+code with language class")
    func fencedCodeBlockWithLanguage() {
        let result = parse("```swift\nlet x = 1\n```")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = 1"))
        #expect(html.contains("</code></pre>"))
    }

    @Test("mermaid code block gets special class for JS detection")
    func mermaidCodeBlockGetsSpecialClass() {
        let source = "```mermaid\ngraph TD\n  A-->B\n```"
        let result = parse(source)
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<pre class=\"mermaid\">"))
        #expect(html.contains("graph TD"))
        #expect(!html.contains("<code"))
    }

    // MARK: - Lists

    @Test("unordered list renders as ul+li")
    func unorderedListRendersAsUl() {
        let result = parse("- item one\n- item two")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>"))
        #expect(html.contains("item one"))
        #expect(html.contains("item two"))
        #expect(html.contains("</ul>"))
    }

    @Test("ordered list renders as ol+li")
    func orderedListRendersAsOl() {
        let result = parse("1. first\n2. second")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>"))
        #expect(html.contains("first"))
    }

    @Test("task list renders checkboxes")
    func taskListRendersCheckboxes() {
        let result = parse("- [x] done\n- [ ] pending")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("checked"))
        #expect(html.contains("type=\"checkbox\""))
    }

    // MARK: - Blockquotes

    @Test("blockquote renders as blockquote tag")
    func blockquoteRendersCorrectly() {
        let result = parse("> This is a quote")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<blockquote>"))
        #expect(html.contains("This is a quote"))
        #expect(html.contains("</blockquote>"))
    }

    // MARK: - Tables

    @Test("GFM table renders as table with thead and tbody")
    func tableRendersCorrectly() {
        let source = "| Name | Age |\n|------|-----|\n| Alice | 30 |"
        let result = parse(source)
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<table>"))
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th>"))
        #expect(html.contains("Name"))
        #expect(html.contains("<tbody>"))
        #expect(html.contains("<td>"))
        #expect(html.contains("Alice"))
    }

    // MARK: - Horizontal Rule

    @Test("horizontal rule renders as hr")
    func horizontalRuleRendersAsHr() {
        let result = parse("---")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.contains("<hr"))
    }

    // MARK: - HTML Escaping

    @Test("special HTML characters are escaped")
    func htmlCharactersEscaped() {
        let result = parse("<script>alert('xss')</script>")
        let html = MarkdownHTMLRenderer.render(result)

        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("HTML escaping covers ampersand and quotes")
    func htmlEscapingCoversAllEntities() {
        let escaped = MarkdownHTMLRenderer.escapeHTML("A & B \"C\" 'D'")
        #expect(escaped == "A &amp; B &quot;C&quot; &#39;D&#39;")
    }

    // MARK: - Frontmatter

    @Test("frontmatter with scalars renders as definition list")
    func frontmatterScalarsRenderAsDefinitionList() {
        let fm = MarkdownFrontmatter(scalars: ["title": "Hello", "date": "2026-01-01"])
        let html = MarkdownHTMLRenderer.renderFrontmatter(fm)

        #expect(html.contains("class=\"frontmatter\""))
        #expect(html.contains("title"))
        #expect(html.contains("Hello"))
        #expect(html.contains("date"))
        #expect(html.contains("2026-01-01"))
    }

    @Test("frontmatter with lists renders tags")
    func frontmatterListsRenderTags() {
        let fm = MarkdownFrontmatter(lists: ["tags": ["swift", "macOS"]])
        let html = MarkdownHTMLRenderer.renderFrontmatter(fm)

        #expect(html.contains("tags"))
        #expect(html.contains("swift"))
        #expect(html.contains("macOS"))
    }

    @Test("empty frontmatter renders empty string")
    func emptyFrontmatterRendersNothing() {
        let fm = MarkdownFrontmatter()
        let html = MarkdownHTMLRenderer.renderFrontmatter(fm)

        #expect(html.isEmpty)
    }

    // MARK: - Document Rendering

    @Test("renderDocument includes frontmatter when present")
    func renderDocumentIncludesFrontmatter() {
        let source = "---\ntitle: Test\n---\n# Hello"
        let doc = MarkdownDocument.parse(source)
        let html = MarkdownHTMLRenderer.renderDocument(doc)

        #expect(html.contains("frontmatter"))
        #expect(html.contains("Test"))
        #expect(html.contains("<h1>Hello</h1>"))
    }

    @Test("renderDocument omits frontmatter section when empty")
    func renderDocumentOmitsFrontmatterWhenEmpty() {
        let source = "# Hello"
        let doc = MarkdownDocument.parse(source)
        let html = MarkdownHTMLRenderer.renderDocument(doc)

        #expect(!html.contains("frontmatter"))
        #expect(html.contains("<h1>Hello</h1>"))
    }

    // MARK: - Frontmatter Edge Cases

    @Test("frontmatter scalars and lists coexist in output")
    func frontmatterMixedScalarsAndLists() {
        let fm = MarkdownFrontmatter(
            scalars: ["author": "Said"],
            lists: ["tags": ["swift", "terminal"]]
        )
        let html = MarkdownHTMLRenderer.renderFrontmatter(fm)

        #expect(html.contains("author"))
        #expect(html.contains("Said"))
        #expect(html.contains("tags"))
        #expect(html.contains("fm-tag"))
        #expect(html.contains("swift"))
    }

    @Test("frontmatter escapes HTML in keys and values")
    func frontmatterEscapesHTML() {
        let fm = MarkdownFrontmatter(scalars: ["key<>": "val&ue"])
        let html = MarkdownHTMLRenderer.renderFrontmatter(fm)

        #expect(html.contains("key&lt;&gt;"))
        #expect(html.contains("val&amp;ue"))
    }

    // MARK: - Export Helpers

    @Test("renderDocument of empty document produces empty string")
    func renderDocumentEmpty() {
        let html = MarkdownHTMLRenderer.renderDocument(.empty)
        #expect(html.isEmpty)
    }

    // MARK: - Empty Document

    @Test("empty parse result produces empty string")
    func emptyDocumentProducesEmptyHTML() {
        let result = MarkdownParseResult(blocks: [], locations: [])
        let html = MarkdownHTMLRenderer.render(result)

        #expect(html.isEmpty)
    }

    // MARK: - Image

    @Test("image renders as img tag with escaped attributes")
    func imageRendersAsImgTag() {
        let blocks: [MarkdownBlock] = [
            .paragraph(inlines: [.image(alt: "a photo", url: "pic.png")])
        ]
        let result = MarkdownParseResult(blocks: blocks, locations: [])
        let html = MarkdownHTMLRenderer.render(result)
        #expect(html.contains("<img src=\"pic.png\" alt=\"a photo\" />"))
    }

    @Test("image with special characters in alt/url is escaped")
    func imageEscapesSpecialChars() {
        let blocks: [MarkdownBlock] = [
            .paragraph(inlines: [.image(alt: "a<b", url: "x\"y.png")])
        ]
        let result = MarkdownParseResult(blocks: blocks, locations: [])
        let html = MarkdownHTMLRenderer.render(result)
        #expect(html.contains("alt=\"a&lt;b\""))
        #expect(html.contains("src=\"x&quot;y.png\""))
    }

    // MARK: - Preview Template

    @Test("Preview template contains floating TOC elements")
    func previewTemplateContainsTOC() {
        let html = MarkdownPreviewTemplate.build()
        #expect(html.contains("toc-toggle"))
        #expect(html.contains("toc-panel"))
        #expect(html.contains("buildTOC"))
    }

    @Test("Preview template TOC uses safe DOM creation, not innerHTML concatenation")
    func previewTemplateTOCUsesSafeDOM() {
        let html = MarkdownPreviewTemplate.build()
        // buildTOC must use createElement + textContent, never innerHTML with heading text
        #expect(html.contains("document.createElement('a')"))
        #expect(html.contains("link.textContent"))
        #expect(html.contains("panel.appendChild"))
        // Must NOT concatenate heading text into an innerHTML string
        #expect(!html.contains("html += '<a"))
    }

    @Test("Preview template contains scrollToFraction function")
    func previewTemplateContainsScrollToFraction() {
        let html = MarkdownPreviewTemplate.build()
        #expect(html.contains("scrollToFraction"))
    }
}
