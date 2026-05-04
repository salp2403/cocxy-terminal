// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewTemplate.swift - HTML template builder for WKWebView markdown preview.

import Foundation

/// Builds the complete HTML page loaded once into the WKWebView.
///
/// The template embeds Catppuccin Mocha CSS and bundled JavaScript
/// dependencies. Swift updates only `#content`, while the template keeps
/// reusable infrastructure warm: Mermaid, KaTeX, Highlight.js, TOC, lightbox,
/// footnote popovers, copy buttons, checkbox messaging, and click-to-source.
enum MarkdownPreviewTemplate {

    static func build(
        mermaidJS: String = "",
        katexJS: String = "",
        katexCSS: String = "",
        autoRenderJS: String = "",
        highlightJS: String = "",
        highlightCSS: String = "",
        tableOfContentsTitle: String = "Table of Contents"
    ) -> String {
        let escapedTableOfContentsTitle = htmlAttributeEscape(tableOfContentsTitle)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>\(previewCSS)</style>
        \(katexCSS.isEmpty ? "" : "<style>\(katexCSS)</style>")
        \(highlightCSS.isEmpty ? "" : "<style>\(highlightCSS)</style>")
        \(katexJS.isEmpty ? "" : "<script>\(katexJS)</script>")
        \(autoRenderJS.isEmpty ? "" : "<script>\(autoRenderJS)</script>")
        \(highlightJS.isEmpty ? "" : "<script>\(highlightJS)</script>")
        </head>
        <body>
        <button id="toc-toggle" title="\(escapedTableOfContentsTitle)">&#9776;</button>
        <div id="toc-panel"></div>
        <div id="content"></div>
        <div id="footnote-popover" class="footnote-popover" hidden></div>
        <div id="lightbox-overlay" class="lightbox-overlay" hidden>
          <img id="lightbox-img" class="lightbox-img" alt="" />
        </div>
        \(mermaidJS.isEmpty ? "" : "<script>\(mermaidJS)</script>")
        <script>\(updateScript)</script>
        </body>
        </html>
        """
    }

    private static func htmlAttributeEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
