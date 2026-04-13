// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownRenderer")
@MainActor
struct MarkdownRendererTests {

    @Test("empty document renders empty attributed string")
    func emptyDocument() {
        let renderer = MarkdownRenderer()
        let result = renderer.render(.empty)
        #expect(result.length == 0)
    }

    @Test("heading renders with the configured heading color")
    func headingColor() {
        let doc = MarkdownDocument.parse("# Title")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc)

        #expect(result.length > 0)
        let color = result.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        #expect(color == renderer.theme.headingColors[0])
    }

    @Test("paragraph uses the body text color")
    func paragraphColor() {
        let doc = MarkdownDocument.parse("plain text")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc)
        let color = result.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        #expect(color == renderer.theme.textColor)
    }

    @Test("inline code uses the code background")
    func inlineCodeBackground() {
        let doc = MarkdownDocument.parse("a `snippet` b")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc)
        let string = result.string
        guard let range = string.range(of: "snippet") else {
            Issue.record("expected snippet in output")
            return
        }
        let location = string.distance(from: string.startIndex, to: range.lowerBound)
        let background = result.attribute(
            .backgroundColor,
            at: location,
            effectiveRange: nil
        ) as? NSColor
        #expect(background == renderer.theme.codeBackground)
    }

    @Test("link carries the URL attribute")
    func linkHasURL() {
        let doc = MarkdownDocument.parse("[Cocxy](https://cocxy.dev)")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc)
        let range = (result.string as NSString).range(of: "Cocxy")
        guard range.location != NSNotFound else {
            Issue.record("expected link text in output")
            return
        }
        let url = result.attribute(
            .link,
            at: range.location,
            effectiveRange: nil
        ) as? URL
        #expect(url?.absoluteString == "https://cocxy.dev")
    }

    @Test("strikethrough applies strikethrough style")
    func strikethroughStyle() {
        let doc = MarkdownDocument.parse("~~gone~~")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc)
        let range = (result.string as NSString).range(of: "gone")
        guard range.location != NSNotFound else {
            Issue.record("expected strike text")
            return
        }
        let style = result.attribute(
            .strikethroughStyle,
            at: range.location,
            effectiveRange: nil
        ) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
    }

    @Test("code block renders as monospace")
    func codeBlockMonospace() {
        let doc = MarkdownDocument.parse("```\nlet x = 1\n```")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc)
        let range = (result.string as NSString).range(of: "let x = 1")
        guard range.location != NSNotFound else {
            Issue.record("expected code block content")
            return
        }
        let font = result.attribute(
            .font,
            at: range.location,
            effectiveRange: nil
        ) as? NSFont
        #expect(font?.isFixedPitch == true)
    }

    @Test("ordered list renders numeric markers")
    func orderedListMarkers() {
        let doc = MarkdownDocument.parse("1. alpha\n2. beta")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc).string
        #expect(result.contains("1. alpha"))
        #expect(result.contains("2. beta"))
    }

    @Test("task list renders checkbox glyphs")
    func taskListGlyphs() {
        let doc = MarkdownDocument.parse("- [ ] pending\n- [x] done")
        let renderer = MarkdownRenderer()
        let result = renderer.render(doc).string
        #expect(result.contains("☐"))
        #expect(result.contains("☑"))
    }
}
