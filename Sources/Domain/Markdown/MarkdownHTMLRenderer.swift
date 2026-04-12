// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownHTMLRenderer.swift - Converts parsed markdown AST into HTML string.

import Foundation

/// Converts a `MarkdownParseResult` into an HTML string for WKWebView rendering.
///
/// This renderer produces semantic HTML that Mermaid.js and KaTeX can
/// post-process. Fenced code blocks with `language == "mermaid"` emit
/// `<pre class="mermaid">` instead of `<pre><code>`, which is the
/// convention Mermaid expects. Math delimiters (`$...$`, `$$...$$`) pass
/// through as plain text for KaTeX auto-render to detect.
///
/// All user-supplied text is HTML-escaped to prevent XSS. Links open
/// in new tabs with `rel="noopener noreferrer"`.
enum MarkdownHTMLRenderer {

    /// Renders a parse result to an HTML fragment (no `<html>` wrapper).
    static func render(_ result: MarkdownParseResult) -> String {
        result.blocks.map { renderBlock($0) }.joined(separator: "\n")
    }

    /// Renders a full document including optional frontmatter section.
    static func renderDocument(_ document: MarkdownDocument) -> String {
        var parts: [String] = []

        let frontmatterHTML = renderFrontmatter(document.frontmatter)
        if !frontmatterHTML.isEmpty {
            parts.append(frontmatterHTML)
        }

        let bodyHTML = render(document.parseResult)
        if !bodyHTML.isEmpty {
            parts.append(bodyHTML)
        }

        return parts.joined(separator: "\n")
    }

    /// Renders frontmatter metadata as a styled section.
    ///
    /// Returns an empty string when the frontmatter has no keys, so callers
    /// can safely concatenate without producing empty DOM nodes.
    static func renderFrontmatter(_ frontmatter: MarkdownFrontmatter) -> String {
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

    private static func renderBlock(_ block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let inlines):
            let tag = "h\(level)"
            return "<\(tag)>\(renderInlines(inlines))</\(tag)>"

        case .paragraph(let inlines):
            return "<p>\(renderInlines(inlines))</p>"

        case .blockquote(let blocks):
            let inner = blocks.map { renderBlock($0) }.joined(separator: "\n")
            return "<blockquote>\(inner)</blockquote>"

        case .list(let ordered, let start, let items):
            let tag = ordered ? "ol" : "ul"
            let startAttr = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let inner = items.map { renderListItem($0) }.joined(separator: "\n")
            return "<\(tag)\(startAttr)>\n\(inner)\n</\(tag)>"

        case .codeBlock(let language, let text):
            return renderCodeBlock(language: language, text: text)

        case .table(let headers, let alignments, let rows):
            return renderTable(headers: headers, alignments: alignments, rows: rows)

        case .horizontalRule:
            return "<hr />"
        }
    }

    // MARK: - Code Blocks

    private static func renderCodeBlock(language: String?, text: String) -> String {
        let escaped = escapeHTML(text)

        // Mermaid blocks use <pre class="mermaid"> per Mermaid.js convention.
        if let lang = language?.lowercased(), lang == "mermaid" {
            return "<pre class=\"mermaid\">\(escaped)</pre>"
        }

        if let lang = language, !lang.isEmpty {
            return "<pre><code class=\"language-\(escapeHTML(lang))\">\(escaped)</code></pre>"
        }

        return "<pre><code>\(escaped)</code></pre>"
    }

    // MARK: - Lists

    private static func renderListItem(_ item: MarkdownListItem) -> String {
        var inner = ""

        switch item.taskState {
        case .checked:
            inner += "<input type=\"checkbox\" checked disabled /> "
        case .unchecked:
            inner += "<input type=\"checkbox\" disabled /> "
        case .none:
            break
        }

        for block in item.blocks {
            switch block {
            case .paragraph(let inlines):
                inner += renderInlines(inlines)
            default:
                inner += renderBlock(block)
            }
        }

        let taskClass = item.taskState != .none ? " class=\"task-item\"" : ""
        return "<li\(taskClass)>\(inner)</li>"
    }

    // MARK: - Tables

    private static func renderTable(
        headers: [[MarkdownInline]],
        alignments: [MarkdownTableAlignment],
        rows: [[[MarkdownInline]]]
    ) -> String {
        var html = "<table>\n<thead>\n<tr>\n"

        for (i, header) in headers.enumerated() {
            let align = alignmentAttribute(alignments, at: i)
            html += "<th\(align)>\(renderInlines(header))</th>\n"
        }
        html += "</tr>\n</thead>\n"

        if !rows.isEmpty {
            html += "<tbody>\n"
            for row in rows {
                html += "<tr>\n"
                for (i, cell) in row.enumerated() {
                    let align = alignmentAttribute(alignments, at: i)
                    html += "<td\(align)>\(renderInlines(cell))</td>\n"
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

    private static func renderInlines(_ inlines: [MarkdownInline]) -> String {
        inlines.map { renderInline($0) }.joined()
    }

    private static func renderInline(_ inline: MarkdownInline) -> String {
        switch inline {
        case .text(let text):
            return escapeHTML(text)

        case .strong(let inlines):
            return "<strong>\(renderInlines(inlines))</strong>"

        case .emphasis(let inlines):
            return "<em>\(renderInlines(inlines))</em>"

        case .code(let text):
            return "<code>\(escapeHTML(text))</code>"

        case .strike(let inlines):
            return "<del>\(renderInlines(inlines))</del>"

        case .image(let alt, let url):
            let src = escapeHTML(url)
            let altText = escapeHTML(alt)
            return "<img src=\"\(src)\" alt=\"\(altText)\" />"

        case .link(let text, let url):
            let href = escapeHTML(url)
            return "<a href=\"\(href)\">\(renderInlines(text))</a>"

        case .autolink(let url):
            let href = escapeHTML(url)
            return "<a href=\"\(href)\">\(href)</a>"

        case .lineBreak:
            return "<br />"
        }
    }

    // MARK: - HTML Escaping

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
