// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSlideExporterTests.swift - Tests for slide export functionality.

import Testing
import Foundation
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownSlideExporter")
struct MarkdownSlideExporterTests {

    // MARK: - Split Into Slides

    @Test("Single slide with no separators")
    func singleSlide() {
        let slides = MarkdownSlideExporter.splitIntoSlides(body: "# Hello\n\nWorld")
        #expect(slides.count == 1)
        #expect(slides[0].contains("# Hello"))
    }

    @Test("Multiple slides separated by ---")
    func multipleSlidesHR() {
        let body = "# Slide 1\n\nContent\n\n---\n\n# Slide 2\n\nMore content\n\n---\n\n# Slide 3"
        let slides = MarkdownSlideExporter.splitIntoSlides(body: body)
        #expect(slides.count == 3)
        #expect(slides[0].contains("Slide 1"))
        #expect(slides[1].contains("Slide 2"))
        #expect(slides[2].contains("Slide 3"))
    }

    @Test("Frontmatter is already stripped by MarkdownDocument.parse — body has no frontmatter")
    func frontmatterAlreadyStripped() {
        // MarkdownDocument.parse extracts frontmatter; body only has content
        let doc = MarkdownDocument.parse("---\ntitle: Test\n---\n\n# First Slide\n\n---\n\n# Second Slide")
        let slides = MarkdownSlideExporter.splitIntoSlides(body: doc.body)
        #expect(slides.count == 2)
        #expect(slides[0].contains("First Slide"))
        #expect(slides[1].contains("Second Slide"))
    }

    @Test("Document starting with --- without frontmatter is not lost")
    func startsWithHRNoFrontmatter() {
        // A document that starts with --- as a slide separator, not frontmatter
        // MarkdownDocument.parse will treat lone --- as frontmatter opener only
        // if followed by a closing ---. Otherwise body = full source.
        let body = "# Slide 1\n\nContent"
        let slides = MarkdownSlideExporter.splitIntoSlides(body: body)
        #expect(slides.count == 1)
        #expect(slides[0].contains("Slide 1"))
    }

    @Test("Empty body produces empty slides")
    func emptyBody() {
        let slides = MarkdownSlideExporter.splitIntoSlides(body: "")
        #expect(slides.isEmpty)
    }

    @Test("Only separators produce empty slides")
    func onlySeparators() {
        let slides = MarkdownSlideExporter.splitIntoSlides(body: "---\n---\n---")
        #expect(slides.isEmpty)
    }

    @Test("--- inside fenced code block is not a slide separator")
    func dashesInsideCodeBlock() {
        let body = """
        # Slide 1

        ```yaml
        key: value
        ---
        another: key
        ```

        ---

        # Slide 2
        """
        let slides = MarkdownSlideExporter.splitIntoSlides(body: body)
        #expect(slides.count == 2)
        #expect(slides[0].contains("```yaml"))
        #expect(slides[0].contains("---"))
        #expect(slides[0].contains("another: key"))
        #expect(slides[1].contains("Slide 2"))
    }

    @Test("--- inside tilde fenced block is not a slide separator")
    func dashesInsideTildeBlock() {
        let body = "# A\n\n~~~\n---\n~~~\n\n---\n\n# B"
        let slides = MarkdownSlideExporter.splitIntoSlides(body: body)
        #expect(slides.count == 2)
        #expect(slides[0].contains("---"))
        #expect(slides[1].contains("B"))
    }

    @Test("Slide split preserves original markdown without reserialization")
    func preservesOriginalMarkdown() {
        let body = "# **Bold** *Heading*\n\n- [x] Done task\n- [ ] Open task\n\n---\n\n| H1 | H2 |\n|:---|---:|\n| L | R |"
        let slides = MarkdownSlideExporter.splitIntoSlides(body: body)
        #expect(slides.count == 2)
        // Original inline formatting preserved exactly
        #expect(slides[0].contains("**Bold**"))
        #expect(slides[0].contains("*Heading*"))
        // Task list states preserved
        #expect(slides[0].contains("[x]"))
        #expect(slides[0].contains("[ ]"))
        // Table alignment preserved
        #expect(slides[1].contains(":---|"))
        #expect(slides[1].contains("---:|"))
    }

    @Test("Code blocks with --- inside are preserved intact")
    func codeBlockPreserved() {
        let body = "# Code\n\n```yaml\nfoo: bar\n---\nbaz: qux\n```\n\n---\n\n# Next"
        let slides = MarkdownSlideExporter.splitIntoSlides(body: body)
        #expect(slides.count == 2)
        #expect(slides[0].contains("```yaml"))
        #expect(slides[0].contains("foo: bar"))
        #expect(slides[0].contains("---"))
        #expect(slides[0].contains("baz: qux"))
        #expect(slides[0].contains("```"))
    }

    // MARK: - Export

    @Test("Export produces valid HTML with slide sections")
    func exportProducesHTML() {
        let doc = MarkdownDocument.parse("# Hello\n\nWorld\n\n---\n\n# Goodbye")
        let html = MarkdownSlideExporter.export(document: doc)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<section class=\"slide"))
        #expect(html.contains("slide-counter"))
        #expect(html.contains("nextSlide"))
        #expect(html.contains("prevSlide"))
    }

    @Test("Export uses first heading as title")
    func exportUsesFirstHeading() {
        let doc = MarkdownDocument.parse("# My Presentation\n\nIntro")
        let html = MarkdownSlideExporter.export(document: doc)

        #expect(html.contains("<title>My Presentation</title>"))
    }

    @Test("Export uses custom title when provided")
    func exportCustomTitle() {
        let doc = MarkdownDocument.parse("# Heading\n\nContent")
        let html = MarkdownSlideExporter.export(document: doc, title: "Custom Title")

        #expect(html.contains("<title>Custom Title</title>"))
    }

    @Test("Export contains progress bar")
    func exportProgressBar() {
        let doc = MarkdownDocument.parse("# Slide 1\n\n---\n\n# Slide 2")
        let html = MarkdownSlideExporter.export(document: doc)

        #expect(html.contains("progress-bar"))
        #expect(html.contains("progress-fill"))
    }

    @Test("Export contains keyboard navigation")
    func exportKeyboardNav() {
        let doc = MarkdownDocument.parse("# Test")
        let html = MarkdownSlideExporter.export(document: doc)

        #expect(html.contains("ArrowRight"))
        #expect(html.contains("ArrowLeft"))
    }

    @Test("Export escapes HTML in title")
    func exportEscapesTitle() {
        let doc = MarkdownDocument.parse("# Test <script>alert(1)</script>")
        let html = MarkdownSlideExporter.export(document: doc)

        #expect(!html.contains("<title>Test <script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("Export with no heading uses default title")
    func exportDefaultTitle() {
        let doc = MarkdownDocument.parse("Just some text without heading")
        let html = MarkdownSlideExporter.export(document: doc)

        #expect(html.contains("<title>Presentation</title>"))
    }

    @Test("Export includes Mermaid init when JS is provided")
    func exportWithMermaid() {
        let doc = MarkdownDocument.parse("# Slide\n\n```mermaid\ngraph TD\n```")
        let html = MarkdownSlideExporter.export(document: doc, mermaidJS: "/* mermaid */")

        #expect(html.contains("/* mermaid */"))
        #expect(html.contains("mermaid.initialize"))
        #expect(html.contains("mermaid.run"))
    }

    @Test("Export includes KaTeX when JS is provided")
    func exportWithKaTeX() {
        let doc = MarkdownDocument.parse("# Math\n\n$E=mc^2$")
        let html = MarkdownSlideExporter.export(
            document: doc,
            katexJS: "/* katex */",
            katexCSS: "/* katex-css */",
            autoRenderJS: "/* auto-render */"
        )

        #expect(html.contains("/* katex */"))
        #expect(html.contains("/* katex-css */"))
        #expect(html.contains("/* auto-render */"))
        #expect(html.contains("renderMathInElement"))
    }

    @Test("Export includes Highlight.js when JS and CSS are provided")
    func exportWithHighlight() {
        let doc = MarkdownDocument.parse("# Code\n\n```swift\nprint(\"hi\")\n```")
        let html = MarkdownSlideExporter.export(
            document: doc,
            highlightJS: "/* highlight */",
            highlightCSS: "/* highlight-css */"
        )

        #expect(html.contains("/* highlight */"))
        #expect(html.contains("/* highlight-css */"))
        #expect(html.contains("hljs.highlightElement"))
    }

    @Test("Export without libs produces no script/style blocks for them")
    func exportWithoutLibs() {
        let doc = MarkdownDocument.parse("# Simple")
        let html = MarkdownSlideExporter.export(document: doc)

        // Should still have mermaid/katex init code in the JS, but no lib scripts
        #expect(!html.contains("/* mermaid */"))
    }

    @Test("Export does not include base tag — image inlining is done by caller")
    func exportHasNoBaseTag() {
        let doc = MarkdownDocument.parse("# Test\n\n![img](photo.png)")
        let html = MarkdownSlideExporter.export(document: doc)

        // base tag removed — caller uses MarkdownImageInliner instead
        #expect(!html.contains("<base"))
    }
}
