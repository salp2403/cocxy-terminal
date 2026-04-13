// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownHTMLRenderer.swift - Converts parsed markdown AST into HTML string.

import Foundation

/// Converts a `MarkdownParseResult` into an HTML string for WKWebView rendering.
///
/// The renderer produces semantic HTML with enough metadata for the preview to
/// support click-to-source, interactive task toggles, lightbox images,
/// footnote popovers, Mermaid, KaTeX, and Highlight.js post-processing.
public enum MarkdownHTMLRenderer {

    private struct FootnoteBundle {
        let definitions: [String: [MarkdownBlock]]
        let order: [String]
        let labels: [String: String]
        let previews: [String: String]
    }

    private struct HeadingEntry {
        let level: Int
        let title: String
        let id: String
    }

    private struct RenderContext {
        let footnotes: FootnoteBundle
        let headings: [HeadingEntry]
        var checkboxIndex = 0
        var headingIndex = 0

        mutating func nextHeadingEntry() -> HeadingEntry? {
            guard headingIndex < headings.count else { return nil }
            let entry = headings[headingIndex]
            headingIndex += 1
            return entry
        }
    }

    /// Renders a parse result to an HTML fragment (no `<html>` wrapper).
    public static func render(_ result: MarkdownParseResult, bodyLineOffset: Int = 0) -> String {
        var context = RenderContext(
            footnotes: collectFootnotes(from: result.blocks),
            headings: collectHeadings(from: result.blocks)
        )
        var parts: [String] = []

        for (index, block) in result.blocks.enumerated() {
            if case .footnoteDefinition = block {
                continue
            }
            let sourceLine = index < result.locations.count
                ? bodyLineOffset + result.locations[index].startLine
                : nil
            parts.append(renderBlock(block, sourceLine: sourceLine, context: &context))
        }

        let footnotesHTML = renderFootnotesSection(context: context)
        if !footnotesHTML.isEmpty {
            parts.append(footnotesHTML)
        }

        return parts.joined(separator: "\n")
    }

    /// Renders a full document including optional frontmatter section.
    public static func renderDocument(_ document: MarkdownDocument) -> String {
        var parts: [String] = []

        let frontmatterHTML = renderFrontmatter(document.frontmatter)
        if !frontmatterHTML.isEmpty {
            parts.append(frontmatterHTML)
        }

        let bodyHTML = render(document.parseResult, bodyLineOffset: document.bodyLineOffset)
        if !bodyHTML.isEmpty {
            parts.append(bodyHTML)
        }

        return parts.joined(separator: "\n")
    }

    /// Renders frontmatter metadata as a styled section.
    public static func renderFrontmatter(_ frontmatter: MarkdownFrontmatter) -> String {
        guard !frontmatter.isEmpty else { return "" }

        var rows: [String] = []

        let sortedScalars = frontmatter.scalars.sorted { $0.key < $1.key }
        for (key, value) in sortedScalars {
            rows.append("""
            <tr><td class="fm-key">\(escapeHTML(key))</td>\
            <td class="fm-value">\(escapeHTML(value))</td></tr>
            """)
        }

        let sortedLists = frontmatter.lists.sorted { $0.key < $1.key }
        for (key, values) in sortedLists {
            let tags = values.map { "<span class=\"fm-tag\">\(escapeHTML($0))</span>" }.joined(separator: " ")
            rows.append("""
            <tr><td class="fm-key">\(escapeHTML(key))</td>\
            <td class="fm-value">\(tags)</td></tr>
            """)
        }

        return """
        <section class="frontmatter">
        <table>\(rows.joined(separator: "\n"))</table>
        </section>
        """
    }

    // MARK: - Block Rendering

    private static func renderBlock(
        _ block: MarkdownBlock,
        sourceLine: Int?,
        context: inout RenderContext
    ) -> String {
        let sourceAttribute = sourceLineAttribute(sourceLine)

        switch block {
        case .heading(let level, let inlines):
            let tag = "h\(level)"
            let headingID = context.nextHeadingEntry()?.id ?? "heading-\(context.headingIndex)"
            return "<\(tag)\(sourceAttribute) id=\"\(headingID)\">\(renderInlines(inlines, context: &context))</\(tag)>"

        case .paragraph(let inlines):
            if isInlineTOCPlaceholder(inlines) {
                return renderInlineTOC(headings: context.headings, sourceAttribute: sourceAttribute)
            }
            return "<p\(sourceAttribute)>\(renderInlines(inlines, context: &context))</p>"

        case .blockquote(let blocks):
            let inner = blocks.map { renderBlock($0, sourceLine: nil, context: &context) }.joined(separator: "\n")
            return "<blockquote\(sourceAttribute)>\(inner)</blockquote>"

        case .callout(let type, let title, let isFolded, let blocks):
            let inner = blocks.map { renderBlock($0, sourceLine: nil, context: &context) }.joined(separator: "\n")
            let summary = """
            <summary class="callout-summary">\
            <span class="callout-icon">\(escapeHTML(type.icon))</span>\
            <span class="callout-title">\(escapeHTML(title))</span>\
            </summary>
            """
            if isFolded {
                return """
                <details class="callout callout-\(type.rawValue)"\(sourceAttribute)>\
                \(summary)\
                <div class="callout-body">\(inner)</div>\
                </details>
                """
            }
            return """
            <details class="callout callout-\(type.rawValue)" open\(sourceAttribute)>\
            \(summary)\
            <div class="callout-body">\(inner)</div>\
            </details>
            """

        case .list(let ordered, let start, let items):
            let tag = ordered ? "ol" : "ul"
            let startAttr = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let inner = items.map { renderListItem($0, context: &context) }.joined(separator: "\n")
            return "<\(tag)\(startAttr)\(sourceAttribute)>\n\(inner)\n</\(tag)>"

        case .codeBlock(let language, let title, let text):
            return renderCodeBlock(
                language: language,
                title: title,
                text: text,
                sourceAttribute: sourceAttribute
            )

        case .table(let headers, let alignments, let rows):
            return renderTable(
                headers: headers,
                alignments: alignments,
                rows: rows,
                sourceAttribute: sourceAttribute,
                context: &context
            )

        case .footnoteDefinition:
            return ""

        case .horizontalRule:
            return "<hr\(sourceAttribute) />"
        }
    }

    // MARK: - Code Blocks

    private static func renderCodeBlock(
        language: String?,
        title: String?,
        text: String,
        sourceAttribute: String
    ) -> String {
        let escaped = escapeHTML(text)
        let label = escapeHTML(language?.lowercased() ?? "text")
        let filenameHeader = title.map { title in
            "<div class=\"code-filename\">\(escapeHTML(title))</div>"
        } ?? ""

        if let lang = language?.lowercased(), lang == "mermaid" {
            return """
            <div class="code-block code-block-mermaid"\(sourceAttribute)>
              \(filenameHeader)
              <div class="code-header">
                <span class="code-lang">\(label)</span>
                <button type="button" class="code-copy">Copy</button>
              </div>
              <div class="code-scroller">
                <div class="code-line-numbers" aria-hidden="true"></div>
                <pre class="mermaid">\(escaped)</pre>
              </div>
            </div>
            """
        }

        let classAttribute = language.map { " class=\"language-\(escapeHTML($0))\"" } ?? ""
        return """
        <div class="code-block"\(sourceAttribute)>
          \(filenameHeader)
          <div class="code-header">
            <span class="code-lang">\(label)</span>
            <button type="button" class="code-copy">Copy</button>
          </div>
          <div class="code-scroller">
            <div class="code-line-numbers" aria-hidden="true"></div>
            <pre><code\(classAttribute)>\(escaped)</code></pre>
          </div>
        </div>
        """
    }

    // MARK: - Lists

    private static func renderListItem(_ item: MarkdownListItem, context: inout RenderContext) -> String {
        var parts: [String] = []

        switch item.taskState {
        case .checked, .unchecked:
            let index = context.checkboxIndex
            context.checkboxIndex += 1
            let checkedAttr = item.taskState == .checked ? " checked" : ""
            parts.append("""
            <input type="checkbox" data-checkbox-index="\(index)" aria-label="Toggle task"\(checkedAttr) />
            """)
        case .none:
            break
        }

        for block in item.blocks {
            switch block {
            case .paragraph(let inlines):
                parts.append(renderInlines(inlines, context: &context))
            default:
                parts.append(renderBlock(block, sourceLine: nil, context: &context))
            }
        }

        let taskClass = item.taskState != .none ? " class=\"task-item\"" : ""
        return "<li\(taskClass)>\(parts.joined())</li>"
    }

    // MARK: - Tables

    private static func renderTable(
        headers: [[MarkdownInline]],
        alignments: [MarkdownTableAlignment],
        rows: [[[MarkdownInline]]],
        sourceAttribute: String,
        context: inout RenderContext
    ) -> String {
        var html = "<table\(sourceAttribute)>\n<thead>\n<tr>\n"

        for (i, header) in headers.enumerated() {
            let align = alignmentAttribute(alignments, at: i)
            html += "<th\(align)>\(renderInlines(header, context: &context))</th>\n"
        }
        html += "</tr>\n</thead>\n"

        if !rows.isEmpty {
            html += "<tbody>\n"
            for row in rows {
                html += "<tr>\n"
                for (i, cell) in row.enumerated() {
                    let align = alignmentAttribute(alignments, at: i)
                    html += "<td\(align)>\(renderInlines(cell, context: &context))</td>\n"
                }
                html += "</tr>\n"
            }
            html += "</tbody>\n"
        }

        html += "</table>"
        return html
    }

    private static func alignmentAttribute(
        _ alignments: [MarkdownTableAlignment],
        at index: Int
    ) -> String {
        guard index < alignments.count else { return "" }
        switch alignments[index] {
        case .none: return ""
        case .left: return " style=\"text-align:left\""
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        }
    }

    // MARK: - Inline Rendering

    private static func renderInlines(_ inlines: [MarkdownInline], context: inout RenderContext) -> String {
        inlines.map { renderInline($0, context: &context) }.joined()
    }

    private static func renderInline(_ inline: MarkdownInline, context: inout RenderContext) -> String {
        switch inline {
        case .text(let text):
            return escapeHTML(text)

        case .strong(let inlines):
            return "<strong>\(renderInlines(inlines, context: &context))</strong>"

        case .emphasis(let inlines):
            return "<em>\(renderInlines(inlines, context: &context))</em>"

        case .code(let text):
            return "<code>\(escapeHTML(text))</code>"

        case .strike(let inlines):
            return "<del>\(renderInlines(inlines, context: &context))</del>"

        case .highlight(let inlines):
            return "<mark>\(renderInlines(inlines, context: &context))</mark>"

        case .superscript(let inlines):
            return "<sup>\(renderInlines(inlines, context: &context))</sup>"

        case .`subscript`(let inlines):
            return "<sub>\(renderInlines(inlines, context: &context))</sub>"

        case .image(let alt, let url):
            let src = escapeHTML(url)
            let altText = escapeHTML(alt)
            return "<img src=\"\(src)\" alt=\"\(altText)\" loading=\"lazy\" />"

        case .link(let text, let url):
            let href = escapeHTML(url)
            return "<a href=\"\(href)\" target=\"_blank\" rel=\"noopener noreferrer\">\(renderInlines(text, context: &context))</a>"

        case .autolink(let url):
            let href = escapeHTML(url)
            return "<a href=\"\(href)\" target=\"_blank\" rel=\"noopener noreferrer\">\(href)</a>"

        case .footnoteRef(let id):
            let safeID = MarkdownFootnote.anchorID(for: id)
            let preview = escapeHTML(context.footnotes.previews[id] ?? "")
            let label = escapeHTML(context.footnotes.labels[id] ?? id)
            return """
            <sup class="footnote-ref"><a href="#fn-\(safeID)" id="fnref-\(safeID)" data-footnote-preview="\(preview)">\(label)</a></sup>
            """

        case .lineBreak:
            return "<br />"
        }
    }

    // MARK: - Footnotes

    private static func collectHeadings(from blocks: [MarkdownBlock]) -> [HeadingEntry] {
        var headings: [HeadingEntry] = []

        func walk(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                switch block {
                case .heading(let level, let inlines):
                    let title = MarkdownOutline.plainText(from: inlines).trimmingCharacters(in: .whitespacesAndNewlines)
                    headings.append(HeadingEntry(level: level, title: title, id: "heading-\(headings.count)"))
                case .blockquote(let blocks),
                     .callout(_, _, _, let blocks),
                     .footnoteDefinition(_, let blocks):
                    walk(blocks)
                case .list(_, _, let items):
                    for item in items {
                        walk(item.blocks)
                    }
                case .paragraph, .codeBlock, .table, .horizontalRule:
                    break
                }
            }
        }

        walk(blocks)
        return headings
    }

    private static func collectFootnotes(from blocks: [MarkdownBlock]) -> FootnoteBundle {
        var definitions: [String: [MarkdownBlock]] = [:]
        var order: [String] = []

        for block in blocks {
            if case .footnoteDefinition(let id, let nestedBlocks) = block {
                definitions[id] = nestedBlocks
                order.append(id)
            }
        }

        var labels: [String: String] = [:]
        var previews: [String: String] = [:]
        for (ordinal, id) in order.enumerated() {
            let blocks = definitions[id] ?? []
            labels[id] = MarkdownFootnote.displayLabel(for: id, ordinal: ordinal + 1)
            previews[id] = MarkdownFootnote.definitionPreviewText(from: blocks)
        }

        return FootnoteBundle(definitions: definitions, order: order, labels: labels, previews: previews)
    }

    private static func isInlineTOCPlaceholder(_ inlines: [MarkdownInline]) -> Bool {
        guard inlines.count == 1 else { return false }
        guard case .text(let text) = inlines[0] else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "[TOC]"
    }

    private static func renderInlineTOC(headings: [HeadingEntry], sourceAttribute: String) -> String {
        guard !headings.isEmpty else {
            return "<nav class=\"toc-inline\"\(sourceAttribute)><div class=\"toc-empty\">No headings</div></nav>"
        }

        let links = headings.map { heading in
            "<a class=\"toc-inline-link toc-h\(heading.level)\" href=\"#\(heading.id)\">\(escapeHTML(heading.title))</a>"
        }.joined(separator: "\n")

        return """
        <nav class="toc-inline"\(sourceAttribute)>
          <div class="toc-inline-title">Table of Contents</div>
          \(links)
        </nav>
        """
    }

    private static func renderFootnotesSection(context: RenderContext) -> String {
        guard !context.footnotes.order.isEmpty else { return "" }

        var items: [String] = []
        for id in context.footnotes.order {
            guard let blocks = context.footnotes.definitions[id] else { continue }
            let safeID = MarkdownFootnote.anchorID(for: id)
            let label = escapeHTML(context.footnotes.labels[id] ?? id)
            var innerContext = context
            let body = blocks.map { renderBlock($0, sourceLine: nil, context: &innerContext) }.joined(separator: "\n")
            items.append("""
            <li id="fn-\(safeID)" data-footnote-label="\(label)">
              <div class="footnote-body">\(body)</div>
              <a class="footnote-backref" href="#fnref-\(safeID)">↩</a>
            </li>
            """)
        }

        return """
        <section class="footnotes">
          <hr />
          <ol>
            \(items.joined(separator: "\n"))
          </ol>
        </section>
        """
    }

    // MARK: - Attributes / Escaping

    private static func sourceLineAttribute(_ sourceLine: Int?) -> String {
        guard let sourceLine else { return "" }
        return " data-source-line=\"\(sourceLine)\""
    }

    static func escapeHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }
}
