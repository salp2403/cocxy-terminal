// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewTemplate.swift - HTML template builder for WKWebView markdown preview.

import Foundation

/// Builds the complete HTML page loaded once into the WKWebView.
///
/// The template embeds Catppuccin Mocha CSS and reserves a `<div id="content">`
/// that is updated via `evaluateJavaScript("updateContent('...')")` each time
/// the document changes. Mermaid and KaTeX scripts run after each update.
///
/// The heavy JS libraries (Mermaid ~3MB, KaTeX ~270KB) load once on the
/// initial page load and persist across content updates.
enum MarkdownPreviewTemplate {

    /// Builds the full HTML page with CSS and JS library placeholders.
    ///
    /// - Parameters:
    ///   - mermaidJS: Contents of `mermaid.min.js`, or empty to skip.
    ///   - katexJS: Contents of `katex.min.js`, or empty to skip.
    ///   - katexCSS: Contents of `katex.min.css`, or empty to skip.
    ///   - autoRenderJS: Contents of `katex-auto-render.min.js`, or empty to skip.
    /// - Returns: A complete HTML document string.
    static func build(
        mermaidJS: String = "",
        katexJS: String = "",
        katexCSS: String = "",
        autoRenderJS: String = ""
    ) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>\(previewCSS)</style>
        \(katexCSS.isEmpty ? "" : "<style>\(katexCSS)</style>")
        \(katexJS.isEmpty ? "" : "<script>\(katexJS)</script>")
        \(autoRenderJS.isEmpty ? "" : "<script>\(autoRenderJS)</script>")
        </head>
        <body>
        <button id="toc-toggle" title="Table of Contents">&#9776;</button>
        <div id="toc-panel"></div>
        <div id="content"></div>
        \(mermaidJS.isEmpty ? "" : "<script>\(mermaidJS)</script>")
        <script>\(updateScript)</script>
        </body>
        </html>
        """
    }

    /// JavaScript function injected into the page. Called from Swift via
    /// `evaluateJavaScript("updateContent('...')")` to replace the body
    /// content and re-run Mermaid/KaTeX rendering.
    private static var updateScript: String {
        """
        function updateContent(html) {
            var el = document.getElementById('content');
            if (!el) return;

            // Preserve scroll position during live editing so the preview
            // does not jump to the top on every keystroke.
            var savedY = window.scrollY;

            el.innerHTML = html;

            // Re-render Mermaid diagrams
            if (typeof mermaid !== 'undefined') {
                try {
                    el.querySelectorAll('.mermaid[data-processed]').forEach(function(node) {
                        node.removeAttribute('data-processed');
                    });
                    mermaid.run({ nodes: el.querySelectorAll('.mermaid') });
                } catch(e) {
                    console.log('Mermaid render error:', e);
                }
            }

            // Re-render KaTeX math expressions
            if (typeof renderMathInElement !== 'undefined') {
                try {
                    renderMathInElement(el, {
                        delimiters: [
                            { left: '$$', right: '$$', display: true },
                            { left: '$', right: '$', display: false }
                        ],
                        throwOnError: false
                    });
                } catch(e) {
                    console.log('KaTeX render error:', e);
                }
            }

            // Restore scroll position after DOM update.
            window.scrollTo(0, savedY);

            // Rebuild floating TOC if it is visible
            var tocPanel = document.getElementById('toc-panel');
            if (tocPanel && tocPanel.classList.contains('visible')) {
                buildTOC();
            }
        }

        function scrollToHeading(title) {
            var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
            for (var i = 0; i < headings.length; i++) {
                if (headings[i].textContent.trim() === title) {
                    headings[i].scrollIntoView({ behavior: 'smooth', block: 'start' });
                    return true;
                }
            }
            return false;
        }

        // Initialize Mermaid with dark theme on first load
        if (typeof mermaid !== 'undefined') {
            mermaid.initialize({
                startOnLoad: false,
                theme: 'dark',
                themeVariables: {
                    darkMode: true,
                    background: '#1e1e2e',
                    primaryColor: '#89b4fa',
                    primaryTextColor: '#cdd6f4',
                    primaryBorderColor: '#585b70',
                    lineColor: '#6c7086',
                    secondaryColor: '#cba6f7',
                    tertiaryColor: '#313244',
                    noteBkgColor: '#313244',
                    noteTextColor: '#cdd6f4',
                    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace'
                }
            });
        }

        // Floating TOC — uses DOM API (createElement + textContent) to avoid
        // re-injecting unescaped heading text via innerHTML, which would break
        // the renderer's XSS guarantee.
        function buildTOC() {
            var panel = document.getElementById('toc-panel');
            if (!panel) return;
            var headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');

            // Clear previous TOC entries safely
            while (panel.firstChild) panel.removeChild(panel.firstChild);

            if (headings.length === 0) {
                var empty = document.createElement('div');
                empty.className = 'toc-empty';
                empty.textContent = 'No headings';
                panel.appendChild(empty);
                return;
            }

            for (var i = 0; i < headings.length; i++) {
                var h = headings[i];
                var level = h.tagName.toLowerCase();
                var id = 'toc-heading-' + i;
                h.id = id;

                var link = document.createElement('a');
                link.href = '#';
                link.className = 'toc-' + level;
                link.setAttribute('data-target', id);
                // textContent is safe: it sets text, never parses HTML
                link.textContent = h.textContent.trim();
                link.addEventListener('click', (function(targetId) {
                    return function(e) {
                        e.preventDefault();
                        var el = document.getElementById(targetId);
                        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    };
                })(id));
                panel.appendChild(link);
            }
        }

        // Toggle TOC panel visibility
        var tocToggle = document.getElementById('toc-toggle');
        if (tocToggle) {
            tocToggle.addEventListener('click', function() {
                var panel = document.getElementById('toc-panel');
                if (!panel) return;
                var isVisible = panel.classList.toggle('visible');
                tocToggle.classList.toggle('active', isVisible);
                if (isVisible) buildTOC();
            });
        }

        function scrollToFraction(fraction) {
            var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
            window.scrollTo(0, Math.round(maxScroll * fraction));
        }
        """
    }

    // MARK: - Catppuccin Mocha CSS

    /// CSS using exact Catppuccin Mocha hex values from CocxyColors.swift.
    static var previewCSS: String {
        """
        :root {
            --base: #1e1e2e;
            --mantle: #181825;
            --crust: #11111b;
            --surface0: #313244;
            --surface1: #45475a;
            --surface2: #585b70;
            --overlay0: #6c7086;
            --text: #cdd6f4;
            --subtext0: #a6adc8;
            --subtext1: #bac2de;
            --blue: #89b4fa;
            --green: #a6e3a1;
            --red: #f38ba8;
            --yellow: #f9e2af;
            --peach: #fab387;
            --mauve: #cba6f7;
            --teal: #94e2d5;
            --lavender: #b4befe;
            --sky: #89dceb;
            --rosewater: #f5e0dc;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            font-size: 14px;
            line-height: 1.7;
            color: var(--text);
            background: var(--base);
            padding: 20px 24px;
            -webkit-font-smoothing: antialiased;
        }

        #content > *:first-child { margin-top: 0; }

        /* Headings */
        h1, h2, h3, h4, h5, h6 {
            margin: 1.4em 0 0.6em;
            font-weight: 600;
            line-height: 1.3;
        }
        h1 { font-size: 1.8em; color: var(--blue); border-bottom: 1px solid var(--surface1); padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; color: var(--mauve); border-bottom: 1px solid var(--surface0); padding-bottom: 0.2em; }
        h3 { font-size: 1.25em; color: var(--teal); }
        h4 { font-size: 1.1em; color: var(--lavender); }
        h5 { font-size: 1.0em; color: var(--sky); }
        h6 { font-size: 0.9em; color: var(--peach); }

        /* Paragraphs */
        p { margin: 0.8em 0; }

        /* Links */
        a { color: var(--blue); text-decoration: none; }
        a:hover { text-decoration: underline; }

        /* Strong / Emphasis */
        strong { font-weight: 600; }

        /* Inline code */
        code {
            font-family: ui-monospace, SFMono-Regular, 'JetBrains Mono', Menlo, monospace;
            font-size: 0.9em;
            background: var(--surface0);
            color: var(--rosewater);
            padding: 0.15em 0.4em;
            border-radius: 4px;
        }

        /* Code blocks */
        pre {
            background: var(--mantle);
            border: 1px solid var(--surface0);
            border-radius: 6px;
            padding: 14px 16px;
            margin: 1em 0;
            overflow-x: auto;
            line-height: 1.5;
        }
        pre code {
            background: none;
            padding: 0;
            color: var(--text);
            font-size: 0.85em;
        }

        /* Mermaid diagrams */
        pre.mermaid {
            background: var(--mantle);
            border: 1px solid var(--surface0);
            text-align: center;
            padding: 16px;
        }

        /* Blockquotes */
        blockquote {
            border-left: 3px solid var(--blue);
            padding: 0.4em 1em;
            margin: 1em 0;
            color: var(--subtext1);
            background: var(--mantle);
            border-radius: 0 4px 4px 0;
        }
        blockquote p { margin: 0.4em 0; }

        /* Lists */
        ul, ol { margin: 0.8em 0; padding-left: 1.8em; }
        li { margin: 0.3em 0; }
        li.task-item { list-style: none; margin-left: -1.4em; }
        li.task-item input[type="checkbox"] { margin-right: 0.5em; }

        /* Tables */
        table {
            border-collapse: collapse;
            margin: 1em 0;
            width: 100%;
            font-size: 0.9em;
        }
        th, td {
            border: 1px solid var(--surface1);
            padding: 8px 12px;
            text-align: left;
        }
        th {
            background: var(--surface0);
            font-weight: 600;
            color: var(--subtext1);
        }
        tr:nth-child(even) td { background: rgba(49, 50, 68, 0.3); }

        /* Horizontal rule */
        hr {
            border: none;
            border-top: 1px solid var(--surface1);
            margin: 1.5em 0;
        }

        /* Strikethrough */
        del { color: var(--overlay0); text-decoration: line-through; }

        /* KaTeX display math */
        .katex-display { margin: 1em 0; overflow-x: auto; }

        /* Frontmatter */
        .frontmatter {
            margin: 0 0 1.5em;
            padding: 12px 16px;
            background: var(--mantle);
            border: 1px solid var(--surface0);
            border-radius: 6px;
            font-size: 0.85em;
        }
        .frontmatter table { margin: 0; width: auto; border: none; }
        .frontmatter td { border: none; padding: 2px 12px 2px 0; vertical-align: top; }
        .fm-key { color: var(--mauve); font-weight: 600; white-space: nowrap; }
        .fm-value { color: var(--subtext1); }
        .fm-tag {
            display: inline-block;
            background: var(--surface0);
            color: var(--blue);
            padding: 1px 8px;
            border-radius: 10px;
            margin: 1px 3px 1px 0;
            font-size: 0.9em;
        }

        /* Images */
        img { max-width: 100%; border-radius: 4px; margin: 0.5em 0; }

        /* Selection */
        ::selection { background: rgba(137, 180, 250, 0.3); }

        /* Floating TOC */
        #toc-toggle {
            position: fixed;
            top: 10px;
            right: 10px;
            z-index: 1000;
            width: 28px;
            height: 28px;
            border-radius: 6px;
            border: 1px solid var(--surface1);
            background: var(--mantle);
            color: var(--subtext0);
            font-size: 14px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            opacity: 0.7;
            transition: opacity 0.15s, background 0.15s;
        }
        #toc-toggle:hover { opacity: 1; background: var(--surface0); }
        #toc-toggle.active { opacity: 1; color: var(--blue); border-color: var(--blue); }

        #toc-panel {
            position: fixed;
            top: 44px;
            right: 10px;
            z-index: 999;
            width: 220px;
            max-height: 60vh;
            overflow-y: auto;
            background: var(--mantle);
            border: 1px solid var(--surface0);
            border-radius: 8px;
            padding: 10px 0;
            display: none;
            box-shadow: 0 4px 16px rgba(0,0,0,0.3);
        }
        #toc-panel.visible { display: block; }
        #toc-panel a {
            display: block;
            padding: 3px 14px;
            color: var(--subtext1);
            text-decoration: none;
            font-size: 12px;
            line-height: 1.5;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        #toc-panel a:hover { background: var(--surface0); color: var(--text); }
        #toc-panel a.toc-h1 { font-weight: 600; color: var(--blue); padding-left: 14px; }
        #toc-panel a.toc-h2 { padding-left: 24px; }
        #toc-panel a.toc-h3 { padding-left: 34px; color: var(--overlay0); }
        #toc-panel a.toc-h4,
        #toc-panel a.toc-h5,
        #toc-panel a.toc-h6 { padding-left: 44px; color: var(--overlay0); font-size: 11px; }
        #toc-panel .toc-empty { padding: 8px 14px; color: var(--overlay0); font-style: italic; font-size: 12px; }
        """
    }
}
