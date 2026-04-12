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
        highlightCSS: String = ""
    ) -> String {
        """
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
        <button id="toc-toggle" title="Table of Contents">&#9776;</button>
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

    private static var updateScript: String {
        """
        function postPreviewMessage(type, payload) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cocxy) {
                window.webkit.messageHandlers.cocxy.postMessage({ type: type, payload: payload });
            }
        }

        function renderMermaid(root) {
            if (typeof mermaid === 'undefined') return;
            try {
                root.querySelectorAll('.mermaid[data-processed]').forEach(function(node) {
                    node.removeAttribute('data-processed');
                });
                mermaid.run({ nodes: root.querySelectorAll('.mermaid') });
            } catch (error) {
                console.log('Mermaid render error:', error);
            }
        }

        function renderMath(root) {
            if (typeof renderMathInElement === 'undefined') return;
            try {
                renderMathInElement(root, {
                    delimiters: [
                        { left: '$$', right: '$$', display: true },
                        { left: '$', right: '$', display: false }
                    ],
                    throwOnError: false
                });
            } catch (error) {
                console.log('KaTeX render error:', error);
            }
        }

        function decorateCodeBlocks(root) {
            root.querySelectorAll('.code-block').forEach(function(block) {
                var pre = block.querySelector('pre');
                var code = block.querySelector('code');
                var rawText = code ? code.textContent : (pre ? pre.textContent : '');
                var lineCount = rawText.length === 0 ? 1 : rawText.split('\\n').length;
                var gutter = block.querySelector('.code-line-numbers');
                if (!gutter) return;
                var numbers = [];
                for (var i = 1; i <= lineCount; i++) {
                    numbers.push(String(i));
                }
                gutter.textContent = numbers.join('\\n');
            });
        }

        function highlightCode(root) {
            if (typeof hljs !== 'undefined') {
                root.querySelectorAll('pre code').forEach(function(code) {
                    hljs.highlightElement(code);
                });
            }
            decorateCodeBlocks(root);
        }

        function updateContent(html) {
            var content = document.getElementById('content');
            if (!content) return;

            var savedY = window.scrollY;
            content.innerHTML = html;

            renderMermaid(content);
            renderMath(content);
            highlightCode(content);

            window.scrollTo(0, savedY);

            var tocPanel = document.getElementById('toc-panel');
            if (tocPanel && tocPanel.classList.contains('visible')) {
                buildTOC();
            }
        }

        function scrollToHeading(title) {
            var headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
            for (var i = 0; i < headings.length; i++) {
                if (headings[i].textContent.trim() === title) {
                    headings[i].scrollIntoView({ behavior: 'smooth', block: 'start' });
                    return true;
                }
            }
            return false;
        }

        function buildTOC() {
            var panel = document.getElementById('toc-panel');
            if (!panel) return;
            while (panel.firstChild) panel.removeChild(panel.firstChild);

            var headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
            if (headings.length === 0) {
                var empty = document.createElement('div');
                empty.className = 'toc-empty';
                empty.textContent = 'No headings';
                panel.appendChild(empty);
                return;
            }

            headings.forEach(function(heading, index) {
                var level = heading.tagName.toLowerCase();
                var id = 'toc-heading-' + index;
                heading.id = id;

                var link = document.createElement('a');
                link.href = '#';
                link.className = 'toc-' + level;
                link.textContent = heading.textContent.trim();
                link.addEventListener('click', function(event) {
                    event.preventDefault();
                    heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
                });
                panel.appendChild(link);
            });
        }

        function closeLightbox() {
            var overlay = document.getElementById('lightbox-overlay');
            if (!overlay) return;
            overlay.hidden = true;
            overlay.classList.remove('visible');
        }

        function showLightbox(src, alt) {
            var overlay = document.getElementById('lightbox-overlay');
            var image = document.getElementById('lightbox-img');
            if (!overlay || !image) return;
            image.src = src;
            image.alt = alt || '';
            overlay.hidden = false;
            overlay.classList.add('visible');
        }

        function copyCode(button) {
            var block = button.closest('.code-block');
            if (!block) return;
            var pre = block.querySelector('pre');
            var text = pre ? pre.textContent : '';
            if (!text) return;

            var finish = function(success) {
                var previous = button.textContent;
                button.textContent = success ? 'Copied' : 'Copy failed';
                window.setTimeout(function() {
                    button.textContent = previous;
                }, 1200);
            };

            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(function() {
                    finish(true);
                }).catch(function() {
                    finish(false);
                });
                return;
            }

            try {
                var textarea = document.createElement('textarea');
                textarea.value = text;
                textarea.style.position = 'fixed';
                textarea.style.opacity = '0';
                document.body.appendChild(textarea);
                textarea.select();
                var copied = document.execCommand('copy');
                document.body.removeChild(textarea);
                finish(copied);
            } catch (_) {
                finish(false);
            }
        }

        function showFootnotePopover(anchor) {
            var preview = anchor.getAttribute('data-footnote-preview');
            if (!preview) return;
            var popover = document.getElementById('footnote-popover');
            if (!popover) return;
            popover.textContent = preview;
            popover.hidden = false;
            var rect = anchor.getBoundingClientRect();
            popover.style.left = Math.max(12, rect.left + window.scrollX) + 'px';
            popover.style.top = (rect.bottom + window.scrollY + 10) + 'px';
        }

        function hideFootnotePopover() {
            var popover = document.getElementById('footnote-popover');
            if (!popover) return;
            popover.hidden = true;
            popover.textContent = '';
        }

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

        document.addEventListener('click', function(event) {
            var tocToggle = event.target.closest('#toc-toggle');
            if (tocToggle) {
                var panel = document.getElementById('toc-panel');
                if (!panel) return;
                var isVisible = panel.classList.toggle('visible');
                tocToggle.classList.toggle('active', isVisible);
                if (isVisible) buildTOC();
                return;
            }

            var codeButton = event.target.closest('.code-copy');
            if (codeButton) {
                event.preventDefault();
                copyCode(codeButton);
                return;
            }

            var image = event.target.closest('#content img');
            if (image) {
                event.preventDefault();
                showLightbox(image.getAttribute('src'), image.getAttribute('alt'));
                return;
            }

            if (event.target.id === 'lightbox-overlay') {
                closeLightbox();
            }
        });

        document.addEventListener('change', function(event) {
            var checkbox = event.target.closest('input[data-checkbox-index]');
            if (!checkbox) return;
            var index = parseInt(checkbox.getAttribute('data-checkbox-index'), 10);
            if (Number.isNaN(index)) return;
            postPreviewMessage('checkboxToggle', {
                index: index,
                checked: checkbox.checked
            });
        });

        document.addEventListener('dblclick', function(event) {
            var node = event.target;
            while (node && node !== document.body) {
                if (node.dataset && node.dataset.sourceLine !== undefined) {
                    var sourceLine = parseInt(node.dataset.sourceLine, 10);
                    if (!Number.isNaN(sourceLine)) {
                        postPreviewMessage('clickToSource', { sourceLine: sourceLine });
                    }
                    return;
                }
                node = node.parentElement;
            }
        });

        document.addEventListener('mouseover', function(event) {
            var anchor = event.target.closest('.footnote-ref a[data-footnote-preview]');
            if (anchor) showFootnotePopover(anchor);
        });

        document.addEventListener('mouseout', function(event) {
            var anchor = event.target.closest('.footnote-ref a[data-footnote-preview]');
            if (anchor) hideFootnotePopover();
        });

        document.addEventListener('keydown', function(event) {
            if (event.key === 'Escape') {
                closeLightbox();
                hideFootnotePopover();
            }
        });

        function scrollToFraction(fraction) {
            var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
            window.scrollTo(0, Math.round(maxScroll * fraction));
        }
        """
    }

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
        [data-source-line] { scroll-margin-top: 20px; }

        h1, h2, h3, h4, h5, h6 {
            margin: 1.4em 0 0.6em;
            font-weight: 600;
            line-height: 1.3;
        }
        h1 { font-size: 1.8em; color: var(--blue); border-bottom: 1px solid var(--surface1); padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; color: var(--mauve); border-bottom: 1px solid var(--surface0); padding-bottom: 0.2em; }
        h3 { font-size: 1.25em; color: var(--teal); }
        h4 { font-size: 1.1em; color: var(--lavender); }
        h5 { font-size: 1em; color: var(--sky); }
        h6 { font-size: 0.9em; color: var(--peach); }

        p { margin: 0.8em 0; }
        a { color: var(--blue); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        mark { background: var(--yellow); color: var(--base); padding: 0 0.18em; border-radius: 3px; }
        sup, sub { font-size: 0.75em; line-height: 0; }

        code {
            font-family: ui-monospace, SFMono-Regular, 'JetBrains Mono', Menlo, monospace;
            font-size: 0.9em;
            background: var(--surface0);
            color: var(--rosewater);
            padding: 0.15em 0.4em;
            border-radius: 4px;
        }

        .code-block {
            background: var(--mantle);
            border: 1px solid var(--surface0);
            border-radius: 8px;
            overflow: hidden;
            margin: 1em 0;
        }
        .code-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            padding: 10px 14px;
            background: rgba(49, 50, 68, 0.85);
            border-bottom: 1px solid var(--surface1);
        }
        .code-lang {
            font-size: 0.78em;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: var(--subtext1);
        }
        .code-copy {
            appearance: none;
            border: 1px solid var(--surface1);
            border-radius: 6px;
            background: var(--surface0);
            color: var(--text);
            padding: 4px 10px;
            font-size: 0.82em;
            cursor: pointer;
        }
        .code-copy:hover { background: var(--surface1); }
        .code-scroller {
            display: grid;
            grid-template-columns: auto 1fr;
            align-items: stretch;
        }
        .code-line-numbers {
            white-space: pre;
            user-select: none;
            padding: 14px 10px 14px 14px;
            text-align: right;
            color: var(--overlay0);
            background: rgba(24, 24, 37, 0.9);
            border-right: 1px solid var(--surface0);
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.85em;
            line-height: 1.5;
        }
        pre {
            margin: 0;
            overflow-x: auto;
            padding: 14px 16px;
            line-height: 1.5;
            background: transparent;
        }
        pre code {
            background: none;
            padding: 0;
            color: var(--text);
            font-size: 0.85em;
        }
        pre.mermaid {
            text-align: center;
            min-height: 48px;
        }

        blockquote {
            border-left: 3px solid var(--blue);
            padding: 0.4em 1em;
            margin: 1em 0;
            color: var(--subtext1);
            background: var(--mantle);
            border-radius: 0 4px 4px 0;
        }
        blockquote p { margin: 0.4em 0; }

        .callout {
            margin: 1em 0;
            border: 1px solid var(--surface1);
            border-left-width: 4px;
            border-radius: 10px;
            background: rgba(24, 24, 37, 0.92);
            overflow: hidden;
        }
        .callout-summary {
            list-style: none;
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 12px 14px;
            cursor: pointer;
            font-weight: 600;
        }
        .callout-summary::-webkit-details-marker { display: none; }
        .callout-body { padding: 0 14px 12px; }
        .callout-note { border-left-color: var(--blue); }
        .callout-tip { border-left-color: var(--green); }
        .callout-important { border-left-color: var(--mauve); }
        .callout-warning { border-left-color: var(--yellow); }
        .callout-caution { border-left-color: var(--red); }
        .callout-abstract { border-left-color: var(--teal); }
        .callout-todo { border-left-color: var(--lavender); }
        .callout-bug { border-left-color: var(--red); }

        ul, ol { margin: 0.8em 0; padding-left: 1.8em; }
        li { margin: 0.3em 0; }
        li.task-item { list-style: none; margin-left: -1.4em; }
        li.task-item input[type="checkbox"] {
            margin-right: 0.5em;
            accent-color: var(--blue);
            cursor: pointer;
        }

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

        hr {
            border: none;
            border-top: 1px solid var(--surface1);
            margin: 1.5em 0;
        }

        del { color: var(--overlay0); text-decoration: line-through; }
        .katex-display { margin: 1em 0; overflow-x: auto; }

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
            padding: 2px 8px;
            border-radius: 999px;
            margin-right: 6px;
            background: var(--surface0);
            color: var(--blue);
        }

        .footnotes {
            margin-top: 2em;
            color: var(--subtext1);
            font-size: 0.92em;
        }
        .footnotes ol { padding-left: 1.4em; }
        .footnotes li { margin-bottom: 0.8em; }
        .footnote-ref a { font-size: 0.78em; vertical-align: super; }
        .footnote-backref { margin-left: 0.4em; }
        .footnote-popover {
            position: absolute;
            max-width: 320px;
            padding: 10px 12px;
            border-radius: 8px;
            background: var(--mantle);
            border: 1px solid var(--surface1);
            color: var(--text);
            box-shadow: 0 12px 28px rgba(0, 0, 0, 0.35);
            z-index: 2100;
            font-size: 0.85em;
        }

        #toc-toggle {
            position: fixed;
            top: 14px;
            right: 16px;
            width: 34px;
            height: 34px;
            border-radius: 8px;
            border: 1px solid var(--surface1);
            background: rgba(49, 50, 68, 0.88);
            color: var(--text);
            cursor: pointer;
            z-index: 1200;
        }
        #toc-toggle.active { background: var(--surface1); }
        #toc-panel {
            position: fixed;
            top: 56px;
            right: 16px;
            width: 240px;
            max-height: calc(100vh - 80px);
            overflow-y: auto;
            border-radius: 10px;
            background: rgba(24, 24, 37, 0.96);
            border: 1px solid var(--surface1);
            box-shadow: 0 16px 38px rgba(0, 0, 0, 0.35);
            padding: 12px;
            display: none;
            z-index: 1200;
        }
        #toc-panel.visible { display: block; }
        #toc-panel a {
            display: block;
            padding: 4px 0;
            color: var(--subtext1);
        }
        #toc-panel .toc-h1 { padding-left: 0; color: var(--text); }
        #toc-panel .toc-h2 { padding-left: 10px; }
        #toc-panel .toc-h3 { padding-left: 20px; }
        #toc-panel .toc-h4 { padding-left: 30px; }
        #toc-panel .toc-h5 { padding-left: 40px; }
        #toc-panel .toc-h6 { padding-left: 50px; }
        .toc-empty { color: var(--subtext0); }

        .lightbox-overlay {
            position: fixed;
            inset: 0;
            background: rgba(17, 17, 27, 0.86);
            display: none;
            align-items: center;
            justify-content: center;
            padding: 24px;
            z-index: 2200;
        }
        .lightbox-overlay.visible { display: flex; }
        .lightbox-img {
            max-width: 90vw;
            max-height: 90vh;
            border-radius: 14px;
            box-shadow: 0 24px 60px rgba(0, 0, 0, 0.45);
        }

        img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            cursor: zoom-in;
        }
        """
    }
}
