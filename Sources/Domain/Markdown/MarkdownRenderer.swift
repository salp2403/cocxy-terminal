// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownRenderer.swift - Converts a MarkdownDocument's AST into NSAttributedString.

import AppKit

// MARK: - Theme

/// Visual theme used by `MarkdownRenderer`. Colors are always provided by
/// the caller so the renderer stays decoupled from `CocxyColors` for tests.
///
/// The theme owns `NSFont` and `NSColor` references that aren't `Sendable`,
/// so the type itself is deliberately not marked `Sendable`. In practice it
/// is only ever constructed and consumed on the main actor (AppKit
/// rendering), which the surrounding `@MainActor` renderer enforces.
public struct MarkdownRenderTheme {
    public var bodyFont: NSFont
    public var boldFont: NSFont
    public var italicFont: NSFont
    public var boldItalicFont: NSFont
    public var codeFont: NSFont
    public var headingBaseFont: NSFont

    public var textColor: NSColor
    public var subtleColor: NSColor
    public var codeColor: NSColor
    public var codeBackground: NSColor
    public var quoteColor: NSColor
    public var quoteBar: NSColor
    public var linkColor: NSColor
    public var strikeColor: NSColor
    public var tableBorder: NSColor
    public var rule: NSColor

    public var headingColors: [NSColor]  // index 0 → H1, 5 → H6

    public init(
        bodyFont: NSFont,
        boldFont: NSFont,
        italicFont: NSFont,
        boldItalicFont: NSFont,
        codeFont: NSFont,
        headingBaseFont: NSFont,
        textColor: NSColor,
        subtleColor: NSColor,
        codeColor: NSColor,
        codeBackground: NSColor,
        quoteColor: NSColor,
        quoteBar: NSColor,
        linkColor: NSColor,
        strikeColor: NSColor,
        tableBorder: NSColor,
        rule: NSColor,
        headingColors: [NSColor]
    ) {
        self.bodyFont = bodyFont
        self.boldFont = boldFont
        self.italicFont = italicFont
        self.boldItalicFont = boldItalicFont
        self.codeFont = codeFont
        self.headingBaseFont = headingBaseFont
        self.textColor = textColor
        self.subtleColor = subtleColor
        self.codeColor = codeColor
        self.codeBackground = codeBackground
        self.quoteColor = quoteColor
        self.quoteBar = quoteBar
        self.linkColor = linkColor
        self.strikeColor = strikeColor
        self.tableBorder = tableBorder
        self.rule = rule
        self.headingColors = headingColors
    }

    /// Default theme built from the project's centralized palette.
    @MainActor
    public static let cocxyDefault: MarkdownRenderTheme = {
        let bodySize: CGFloat = 13
        let codeSize: CGFloat = 12
        let headingSize: CGFloat = 20
        let body = NSFont.systemFont(ofSize: bodySize, weight: .regular)
        let bold = NSFont.systemFont(ofSize: bodySize, weight: .bold)
        let italic: NSFont = {
            let descriptor = body.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: bodySize) ?? body
        }()
        let boldItalic: NSFont = {
            let traits = NSFontDescriptor.SymbolicTraits([.bold, .italic])
            let descriptor = body.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: descriptor, size: bodySize) ?? bold
        }()
        let code = NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular)
        let heading = NSFont.systemFont(ofSize: headingSize, weight: .bold)

        return MarkdownRenderTheme(
            bodyFont: body,
            boldFont: bold,
            italicFont: italic,
            boldItalicFont: boldItalic,
            codeFont: code,
            headingBaseFont: heading,
            textColor: CocxyColors.text,
            subtleColor: CocxyColors.subtext0,
            codeColor: CocxyColors.green,
            codeBackground: CocxyColors.surface0,
            quoteColor: CocxyColors.subtext1,
            quoteBar: CocxyColors.overlay0,
            linkColor: CocxyColors.blue,
            strikeColor: CocxyColors.subtext0,
            tableBorder: CocxyColors.surface1,
            rule: CocxyColors.surface0,
            headingColors: [
                CocxyColors.blue,       // H1
                CocxyColors.mauve,      // H2
                CocxyColors.teal,       // H3
                CocxyColors.lavender,   // H4
                CocxyColors.sky,        // H5
                CocxyColors.peach       // H6
            ]
        )
    }()
}

// MARK: - Renderer

/// Renders a `MarkdownDocument`'s AST into a fully styled `NSAttributedString`.
///
/// The renderer is `@MainActor` because it creates `NSFont` / `NSColor` /
/// `NSMutableAttributedString` instances. It is stateless beyond the theme,
/// so callers may keep a single instance and call `render(_:)` many times.
@MainActor
public struct MarkdownRenderer {

    public let theme: MarkdownRenderTheme

    public init(theme: MarkdownRenderTheme = .cocxyDefault) {
        self.theme = theme
    }

    /// Produces an attributed string for the document's body. Frontmatter
    /// is not rendered (consumers that want to display it can access
    /// `document.frontmatter` directly).
    public func render(_ document: MarkdownDocument) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, block) in document.parseResult.blocks.enumerated() {
            appendBlock(block, into: output, isLast: index == document.parseResult.blocks.count - 1)
        }
        return output
    }

    // MARK: - Blocks

    private func appendBlock(
        _ block: MarkdownBlock,
        into output: NSMutableAttributedString,
        isLast: Bool
    ) {
        switch block {
        case .heading(let level, let inlines):
            appendHeading(level: level, inlines: inlines, into: output)
        case .paragraph(let inlines):
            appendParagraph(inlines: inlines, into: output)
        case .blockquote(let blocks):
            appendBlockquote(blocks: blocks, into: output)
        case .list(let ordered, let start, let items):
            appendList(ordered: ordered, start: start, items: items, into: output)
        case .codeBlock(let language, let text):
            appendCodeBlock(language: language, text: text, into: output)
        case .table(let headers, let alignments, let rows):
            appendTable(headers: headers, alignments: alignments, rows: rows, into: output)
        case .horizontalRule:
            appendHorizontalRule(into: output)
        }
        if !isLast {
            output.append(NSAttributedString(string: "\n"))
        }
    }

    // MARK: - Heading

    private func appendHeading(
        level: Int,
        inlines: [MarkdownInline],
        into output: NSMutableAttributedString
    ) {
        let clamped = MarkdownBlock.clampedHeadingLevel(level)
        let size = headingSize(for: clamped)
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let color = theme.headingColors[
            max(0, min(theme.headingColors.count - 1, clamped - 1))
        ]

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        paragraph.paragraphSpacingBefore = 10

        let inlineAttr = renderInlines(inlines, baseFont: font, baseColor: color)
        let heading = NSMutableAttributedString(attributedString: inlineAttr)
        heading.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: heading.length)
        )
        heading.append(NSAttributedString(string: "\n"))
        output.append(heading)
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        case 4: return 15
        case 5: return 14
        default: return 13
        }
    }

    // MARK: - Paragraph

    private func appendParagraph(
        inlines: [MarkdownInline],
        into output: NSMutableAttributedString
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        paragraph.lineSpacing = 3

        let inlineAttr = renderInlines(inlines, baseFont: theme.bodyFont, baseColor: theme.textColor)
        let para = NSMutableAttributedString(attributedString: inlineAttr)
        para.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: para.length)
        )
        para.append(NSAttributedString(string: "\n"))
        output.append(para)
    }

    // MARK: - Blockquote

    private func appendBlockquote(
        blocks: [MarkdownBlock],
        into output: NSMutableAttributedString
    ) {
        let quoteParagraph = NSMutableParagraphStyle()
        quoteParagraph.firstLineHeadIndent = 16
        quoteParagraph.headIndent = 16
        quoteParagraph.paragraphSpacing = 6

        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.italicFont,
            .foregroundColor: theme.quoteColor,
            .paragraphStyle: quoteParagraph
        ]

        for block in blocks {
            let inner = NSMutableAttributedString()
            appendBlock(block, into: inner, isLast: true)
            let quoted = NSMutableAttributedString(string: "▎ ", attributes: [
                .foregroundColor: theme.quoteBar,
                .font: theme.boldFont
            ])
            quoted.append(inner)
            quoted.addAttributes(
                quoteAttrs,
                range: NSRange(location: 0, length: quoted.length)
            )
            output.append(quoted)
        }
    }

    // MARK: - List

    private func appendList(
        ordered: Bool,
        start: Int,
        items: [MarkdownListItem],
        into output: NSMutableAttributedString
    ) {
        for (index, item) in items.enumerated() {
            let marker: String
            if ordered {
                marker = "\(start + index). "
            } else {
                marker = "• "
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = 12
            paragraph.headIndent = 28
            paragraph.paragraphSpacing = 2

            let itemString = NSMutableAttributedString()

            // Task state prefix: `[x] ` / `[ ] `.
            switch item.taskState {
            case .none:
                itemString.append(NSAttributedString(string: marker, attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.subtleColor
                ]))
            case .unchecked:
                itemString.append(NSAttributedString(string: "☐ ", attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.subtleColor
                ]))
            case .checked:
                itemString.append(NSAttributedString(string: "☑ ", attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.linkColor
                ]))
            }

            for block in item.blocks {
                let inner = NSMutableAttributedString()
                appendBlock(block, into: inner, isLast: true)
                itemString.append(inner)
            }

            itemString.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: 0, length: itemString.length)
            )
            output.append(itemString)
        }
    }

    // MARK: - Code Block

    private func appendCodeBlock(
        language: String?,
        text: String,
        into output: NSMutableAttributedString
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        paragraph.paragraphSpacing = 6

        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.codeFont,
            .foregroundColor: theme.codeColor,
            .backgroundColor: theme.codeBackground,
            .paragraphStyle: paragraph
        ]

        if let language, !language.isEmpty {
            let label = NSAttributedString(string: "\(language)\n", attributes: [
                .font: theme.bodyFont,
                .foregroundColor: theme.subtleColor,
                .paragraphStyle: paragraph
            ])
            output.append(label)
        }
        let body = NSAttributedString(string: text + "\n", attributes: attrs)
        output.append(body)
    }

    // MARK: - Table

    private func appendTable(
        headers: [[MarkdownInline]],
        alignments: [MarkdownTableAlignment],
        rows: [[[MarkdownInline]]],
        into output: NSMutableAttributedString
    ) {
        let separator = NSAttributedString(string: " | ", attributes: [
            .foregroundColor: theme.tableBorder,
            .font: theme.bodyFont
        ])

        let headerLine = NSMutableAttributedString()
        for (index, header) in headers.enumerated() {
            if index > 0 { headerLine.append(separator) }
            headerLine.append(
                renderInlines(header, baseFont: theme.boldFont, baseColor: theme.textColor)
            )
        }
        headerLine.append(NSAttributedString(string: "\n"))
        output.append(headerLine)

        let ruleCount = max(12, headers.count * 6)
        let rule = NSAttributedString(
            string: String(repeating: "─", count: ruleCount) + "\n",
            attributes: [
                .foregroundColor: theme.tableBorder,
                .font: theme.bodyFont
            ]
        )
        output.append(rule)

        for row in rows {
            let rowLine = NSMutableAttributedString()
            for (index, cell) in row.enumerated() {
                if index > 0 { rowLine.append(separator) }
                rowLine.append(
                    renderInlines(cell, baseFont: theme.bodyFont, baseColor: theme.textColor)
                )
            }
            rowLine.append(NSAttributedString(string: "\n"))
            output.append(rowLine)
        }
        _ = alignments
    }

    // MARK: - Horizontal Rule

    private func appendHorizontalRule(into output: NSMutableAttributedString) {
        let line = NSAttributedString(string: String(repeating: "─", count: 40) + "\n", attributes: [
            .foregroundColor: theme.rule,
            .font: theme.bodyFont
        ])
        output.append(line)
    }

    // MARK: - Inline Rendering

    private func renderInlines(
        _ inlines: [MarkdownInline],
        baseFont: NSFont,
        baseColor: NSColor,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for inline in inlines {
            switch inline {
            case .text(let text):
                let font = fontFor(baseFont: baseFont, bold: bold, italic: italic)
                output.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: baseColor
                ]))

            case .strong(let nested):
                output.append(
                    renderInlines(nested, baseFont: baseFont, baseColor: baseColor, bold: true, italic: italic)
                )

            case .emphasis(let nested):
                output.append(
                    renderInlines(nested, baseFont: baseFont, baseColor: baseColor, bold: bold, italic: true)
                )

            case .strike(let nested):
                let inner = renderInlines(nested, baseFont: baseFont, baseColor: theme.strikeColor, bold: bold, italic: italic)
                let mutable = NSMutableAttributedString(attributedString: inner)
                mutable.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: NSRange(location: 0, length: mutable.length)
                )
                output.append(mutable)

            case .code(let text):
                output.append(NSAttributedString(string: text, attributes: [
                    .font: theme.codeFont,
                    .foregroundColor: theme.codeColor,
                    .backgroundColor: theme.codeBackground
                ]))

            case .link(let textNodes, let url):
                let inner = renderInlines(textNodes, baseFont: baseFont, baseColor: theme.linkColor, bold: bold, italic: italic)
                let mutable = NSMutableAttributedString(attributedString: inner)
                let linkURL = URL(string: url)
                let attrs: [NSAttributedString.Key: Any] = [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: linkURL as Any
                ]
                mutable.addAttributes(attrs, range: NSRange(location: 0, length: mutable.length))
                output.append(mutable)

            case .autolink(let url):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: theme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: URL(string: url) as Any
                ]
                output.append(NSAttributedString(string: url, attributes: attrs))

            case .lineBreak:
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: baseColor
                ]))
            }
        }
        return output
    }

    private func fontFor(baseFont: NSFont, bold: Bool, italic: Bool) -> NSFont {
        switch (bold, italic) {
        case (true, true):
            let traits = NSFontDescriptor.SymbolicTraits([.bold, .italic])
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? theme.boldItalicFont
        case (true, false):
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
            return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? theme.boldFont
        case (false, true):
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? theme.italicFont
        case (false, false):
            return baseFont
        }
    }
}
