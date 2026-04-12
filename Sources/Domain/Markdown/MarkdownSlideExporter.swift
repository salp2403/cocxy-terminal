// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSlideExporter.swift - Exports markdown documents as HTML slide presentations.

import Foundation

// MARK: - Slide Exporter

/// Generates a standalone HTML presentation from a markdown document.
///
/// Slides are separated by `---` horizontal rules in the markdown source.
/// Each slide is rendered as a full-screen section with navigation controls.
///
/// The exported HTML is fully standalone with embedded CSS and JavaScript —
/// no external dependencies or network calls required.
enum MarkdownSlideExporter {

    /// Splits a markdown document body into slides using the parsed AST locations.
    ///
    /// Uses `MarkdownParser` to identify `horizontalRule` blocks as slide separators,
    /// then extracts the original source lines between separators. No reserialization
    /// is performed — the original markdown is preserved exactly, including inline
    /// formatting, task states, code fences, and table alignments.
    ///
    /// - Parameter body: The body text of the document (after frontmatter extraction).
    /// - Returns: An array of slide body strings, each preserving the original markdown.
    static func splitIntoSlides(body: String) -> [String] {
        let result = MarkdownParser().parse(body)
        let lines = body.components(separatedBy: "\n")
        guard !result.blocks.isEmpty else { return [] }

        // Find the line ranges of horizontal rule blocks (slide separators)
        var separatorLines: [Int] = []
        for (index, block) in result.blocks.enumerated() {
            if case .horizontalRule = block, index < result.locations.count {
                let loc = result.locations[index]
                // Mark all lines belonging to this HR as separators
                for line in loc.startLine...loc.endLine {
                    separatorLines.append(line)
                }
            }
        }

        // If no separators, the whole body is one slide
        if separatorLines.isEmpty {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        // Extract slides: ranges of source lines between separators
        let separatorSet = Set(separatorLines)
        var slides: [String] = []
        var currentSlideLines: [String] = []

        for (lineIndex, line) in lines.enumerated() {
            if separatorSet.contains(lineIndex) {
                // Flush the current slide
                let slide = currentSlideLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !slide.isEmpty {
                    slides.append(slide)
                }
                currentSlideLines = []
            } else {
                currentSlideLines.append(line)
            }
        }

        // Flush the last slide
        let lastSlide = currentSlideLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastSlide.isEmpty {
            slides.append(lastSlide)
        }

        return slides
    }

    /// Generates a complete standalone HTML presentation.
    ///
    /// - Parameters:
    ///   - document: The markdown document to export.
    ///   - title: Optional title for the presentation (defaults to first heading or "Presentation").
    ///   - mermaidJS: Contents of `mermaid.min.js` to embed, or empty to skip.
    ///   - katexJS: Contents of `katex.min.js` to embed, or empty to skip.
    ///   - katexCSS: Contents of `katex.min.css` to embed, or empty to skip.
    ///   - autoRenderJS: Contents of `katex-auto-render.min.js` to embed, or empty to skip.
    /// - Returns: A complete HTML string ready to save to a file.
    static func export(
        document: MarkdownDocument,
        title: String? = nil,
        mermaidJS: String = "",
        katexJS: String = "",
        katexCSS: String = "",
        autoRenderJS: String = ""
    ) -> String {
        let slides = splitIntoSlides(body: document.body)

        let parser = MarkdownParser()
        let slideHTMLs = slides.map { slideSource -> String in
            let result = parser.parse(slideSource)
            return MarkdownHTMLRenderer.render(result)
        }

        let presentationTitle = title ?? extractTitle(from: document) ?? "Presentation"

        return buildHTML(
            title: presentationTitle,
            slides: slideHTMLs,
            totalSlides: slideHTMLs.count,
            mermaidJS: mermaidJS,
            katexJS: katexJS,
            katexCSS: katexCSS,
            autoRenderJS: autoRenderJS
        )
    }

    // MARK: - Private

    private static func extractTitle(from document: MarkdownDocument) -> String? {
        for block in document.parseResult.blocks {
            if case .heading(_, let inlines) = block {
                return MarkdownOutline.plainText(from: inlines)
            }
        }
        return nil
    }

    private static func buildHTML(
        title: String,
        slides: [String],
        totalSlides: Int,
        mermaidJS: String = "",
        katexJS: String = "",
        katexCSS: String = "",
        autoRenderJS: String = ""
    ) -> String {
        let slideDivs = slides.enumerated().map { index, html in
            """
            <section class="slide\(index == 0 ? " active" : "")" data-index="\(index)">
                <div class="slide-content">\(html)</div>
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>\(MarkdownHTMLRenderer.escapeHTML(title))</title>
        <style>\(slideCSS)</style>
        \(katexCSS.isEmpty ? "" : "<style>\(katexCSS)</style>")
        \(katexJS.isEmpty ? "" : "<script>\(katexJS)</script>")
        \(autoRenderJS.isEmpty ? "" : "<script>\(autoRenderJS)</script>")
        </head>
        <body>
        <div id="presentation">
        \(slideDivs)
        </div>
        <div class="controls">
            <button onclick="prevSlide()" id="btn-prev">&larr;</button>
            <span id="slide-counter">1 / \(totalSlides)</span>
            <button onclick="nextSlide()" id="btn-next">&rarr;</button>
        </div>
        <div class="progress-bar"><div class="progress-fill" id="progress"></div></div>
        \(mermaidJS.isEmpty ? "" : "<script>\(mermaidJS)</script>")
        <script>\(slideJS(totalSlides: totalSlides))</script>
        </body>
        </html>
        """
    }

    private static var slideCSS: String {
        """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            background: #1e1e2e;
            color: #cdd6f4;
            overflow: hidden;
            height: 100vh;
        }
        #presentation { position: relative; width: 100vw; height: 100vh; }
        .slide {
            position: absolute;
            top: 0; left: 0; right: 0; bottom: 0;
            display: none;
            align-items: center;
            justify-content: center;
            padding: 60px 80px;
        }
        .slide.active { display: flex; }
        .slide-content {
            max-width: 900px;
            width: 100%;
            font-size: 1.4em;
            line-height: 1.6;
        }
        .slide-content h1 { font-size: 2.2em; color: #89b4fa; margin-bottom: 0.5em; }
        .slide-content h2 { font-size: 1.8em; color: #cba6f7; margin-bottom: 0.4em; }
        .slide-content h3 { font-size: 1.4em; color: #94e2d5; margin-bottom: 0.3em; }
        .slide-content p { margin: 0.6em 0; }
        .slide-content a { color: #89b4fa; }
        .slide-content strong { font-weight: 600; }
        .slide-content code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            background: #313244; padding: 0.1em 0.4em; border-radius: 4px;
            color: #f5e0dc; font-size: 0.85em;
        }
        .slide-content pre {
            background: #181825; border: 1px solid #313244;
            border-radius: 8px; padding: 16px 20px; margin: 0.8em 0;
            overflow-x: auto;
        }
        .slide-content pre code { background: none; padding: 0; color: #cdd6f4; }
        .slide-content ul, .slide-content ol { padding-left: 1.5em; margin: 0.5em 0; }
        .slide-content li { margin: 0.3em 0; }
        .slide-content blockquote {
            border-left: 3px solid #89b4fa; padding: 0.3em 1em;
            color: #bac2de; background: #181825; border-radius: 0 4px 4px 0;
        }
        .slide-content table { border-collapse: collapse; margin: 0.8em 0; width: 100%; }
        .slide-content th, .slide-content td { border: 1px solid #45475a; padding: 8px 12px; text-align: left; }
        .slide-content th { background: #313244; font-weight: 600; }
        .slide-content img { max-width: 100%; border-radius: 6px; }
        .controls {
            position: fixed;
            bottom: 20px;
            left: 50%;
            transform: translateX(-50%);
            display: flex;
            align-items: center;
            gap: 16px;
            z-index: 100;
        }
        .controls button {
            background: #313244; color: #cdd6f4; border: 1px solid #45475a;
            border-radius: 6px; padding: 8px 16px; font-size: 16px;
            cursor: pointer; transition: background 0.15s;
        }
        .controls button:hover { background: #45475a; }
        #slide-counter { font-size: 14px; color: #a6adc8; min-width: 60px; text-align: center; }
        .progress-bar {
            position: fixed; bottom: 0; left: 0; right: 0; height: 3px;
            background: #313244; z-index: 100;
        }
        .progress-fill { height: 100%; background: #89b4fa; transition: width 0.3s; width: 0; }
        ::selection { background: rgba(137, 180, 250, 0.3); }
        """
    }

    private static func slideJS(totalSlides: Int) -> String {
        """
        var current = 0;
        var total = \(totalSlides);
        function showSlide(n) {
            var slides = document.querySelectorAll('.slide');
            if (n < 0 || n >= slides.length) return;
            slides[current].classList.remove('active');
            current = n;
            slides[current].classList.add('active');
            document.getElementById('slide-counter').textContent = (current + 1) + ' / ' + total;
            document.getElementById('progress').style.width = ((current + 1) / total * 100) + '%';
        }
        function nextSlide() { showSlide(current + 1); }
        function prevSlide() { showSlide(current - 1); }
        document.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); nextSlide(); }
            if (e.key === 'ArrowLeft') { e.preventDefault(); prevSlide(); }
            if (e.key === 'Home') { e.preventDefault(); showSlide(0); }
            if (e.key === 'End') { e.preventDefault(); showSlide(total - 1); }
        });
        showSlide(0);

        // Initialize Mermaid if available
        if (typeof mermaid !== 'undefined') {
            mermaid.initialize({
                startOnLoad: false,
                theme: 'dark',
                themeVariables: { darkMode: true, background: '#1e1e2e', primaryColor: '#89b4fa' }
            });
            mermaid.run({ nodes: document.querySelectorAll('.mermaid') });
        }

        // Auto-render KaTeX math if available
        if (typeof renderMathInElement !== 'undefined') {
            document.querySelectorAll('.slide-content').forEach(function(el) {
                renderMathInElement(el, {
                    delimiters: [
                        { left: '$$', right: '$$', display: true },
                        { left: '$', right: '$', display: false }
                    ],
                    throwOnError: false
                });
            });
        }
        """
    }
}
