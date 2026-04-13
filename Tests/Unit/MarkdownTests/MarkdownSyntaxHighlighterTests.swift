// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownSyntaxHighlighter")
@MainActor
struct MarkdownSyntaxHighlighterTests {

    private let highlighter = MarkdownSyntaxHighlighter()

    @Test("bold content keeps bold styling while delimiters are subtle")
    func boldContentVsDelimiters() {
        let result = highlighter.highlight("**bold**")

        let openingColor = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let contentColor = result.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        let closingColor = result.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        let contentFont = result.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let markerFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        #expect(openingColor == highlighter.theme.subtleColor)
        #expect(closingColor == highlighter.theme.subtleColor)
        #expect(contentColor == highlighter.theme.textColor)
        #expect(contentFont == highlighter.theme.boldFont)
        #expect(markerFont == highlighter.theme.boldFont)
    }

    @Test("italic content keeps italic styling while delimiters are subtle")
    func italicContentVsDelimiters() {
        let result = highlighter.highlight("*italics*")

        let openingColor = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let contentColor = result.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        let closingColor = result.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
        let contentFont = result.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        let markerFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        #expect(openingColor == highlighter.theme.subtleColor)
        #expect(closingColor == highlighter.theme.subtleColor)
        #expect(contentColor == highlighter.theme.textColor)
        #expect(contentFont == highlighter.theme.italicFont)
        #expect(markerFont == highlighter.theme.italicFont)
    }

    @Test("highlight markers stay subtle while content receives background")
    func highlightMarkerVsContent() {
        let result = highlighter.highlight("==focus==")

        let openingColor = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let contentColor = result.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        let contentBackground = result.attribute(.backgroundColor, at: 2, effectiveRange: nil) as? NSColor

        #expect(openingColor == highlighter.theme.subtleColor)
        #expect(contentColor == highlighter.theme.textColor)
        #expect(contentBackground != nil)
    }

    @Test("emoji shortcode and footnote refs are highlighted distinctly")
    func emojiAndFootnoteMarkers() {
        let result = highlighter.highlight("Launch :rocket: and cite [^note]")

        let nsString = result.string as NSString
        let emojiRange = nsString.range(of: ":rocket:")
        let footnoteRange = nsString.range(of: "[^note]")

        let emojiColor = result.attribute(.foregroundColor, at: emojiRange.location, effectiveRange: nil) as? NSColor
        let emojiFont = result.attribute(.font, at: emojiRange.location, effectiveRange: nil) as? NSFont
        let footnoteColor = result.attribute(.foregroundColor, at: footnoteRange.location, effectiveRange: nil) as? NSColor
        let footnoteFont = result.attribute(.font, at: footnoteRange.location, effectiveRange: nil) as? NSFont

        #expect(emojiColor == CocxyColors.peach)
        #expect(emojiFont == highlighter.theme.boldFont)
        #expect(footnoteColor == highlighter.theme.linkColor)
        #expect(footnoteFont == highlighter.theme.boldFont)
    }
}
