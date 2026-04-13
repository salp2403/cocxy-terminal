// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownCallout")
struct MarkdownCalloutTests {
    private let parser = MarkdownParser()

    @Test("callout header parses default title")
    func parseHeaderDefaultTitle() {
        let header = MarkdownCallout.parseHeader("[!NOTE]")
        #expect(header?.type == .note)
        #expect(header?.title == "Note")
        #expect(header?.isFolded == false)
    }

    @Test("callout header parses fold state and custom title")
    func parseHeaderFoldedWithTitle() {
        let header = MarkdownCallout.parseHeader("[!WARNING]- Read this first")
        #expect(header?.type == .warning)
        #expect(header?.title == "Read this first")
        #expect(header?.isFolded == true)
    }

    @Test("parser emits callout block instead of blockquote")
    func parserEmitsCalloutBlock() {
        let result = parser.parse("> [!TIP]\n> Ship it carefully")
        #expect(result.blocks == [
            .callout(
                type: .tip,
                title: "Tip",
                isFolded: false,
                blocks: [.paragraph(inlines: [.text("Ship it carefully")])]
            )
        ])
    }

    @Test("plain blockquote remains blockquote")
    func regularBlockquoteUnchanged() {
        let result = parser.parse("> just a quote")
        guard case .blockquote(let blocks)? = result.blocks.first else {
            Issue.record("Expected blockquote")
            return
        }
        #expect(blocks == [.paragraph(inlines: [.text("just a quote")])])
    }

    @Test("HTML renderer emits callout markup")
    func htmlRendererEmitsCalloutMarkup() {
        let document = MarkdownDocument.parse("> [!WARNING]- Heads up\n> Danger")
        let html = MarkdownHTMLRenderer.renderDocument(document)
        #expect(html.contains("class=\"callout callout-warning\""))
        #expect(html.contains("callout-summary"))
        #expect(html.contains("Heads up"))
        #expect(html.contains("Danger"))
    }

    @Test("parser recognizes all fifteen callout types")
    func allFifteenCalloutTypes() {
        let types = [
            "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION",
            "ABSTRACT", "TODO", "BUG", "EXAMPLE", "QUOTE",
            "DANGER", "FAILURE", "SUCCESS", "QUESTION", "INFO"
        ]

        for marker in types {
            let result = MarkdownCallout.parseHeader("[!\(marker)]")
            #expect(result != nil, "Should parse [!\(marker)]")
        }
    }

    @Test("new callout types have correct icons")
    func newCalloutTypeIcons() {
        #expect(MarkdownCalloutType.example.icon == "📝")
        #expect(MarkdownCalloutType.quote.icon == "❝")
        #expect(MarkdownCalloutType.danger.icon == "⚡")
        #expect(MarkdownCalloutType.failure.icon == "✗")
        #expect(MarkdownCalloutType.success.icon == "✓")
        #expect(MarkdownCalloutType.question.icon == "❓")
        #expect(MarkdownCalloutType.info.icon == "ℹ")
    }
}
