// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewTemplate+CSS.swift - Catppuccin Mocha CSS for markdown preview.

import Foundation

extension MarkdownPreviewTemplate {
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
        .code-filename {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.78em;
            padding: 6px 14px;
            background: rgba(49, 50, 68, 0.6);
            color: var(--subtext0);
            border-bottom: 1px solid var(--surface0);
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
        .table-tools {
            display: flex;
            justify-content: flex-end;
            margin-top: 0.75em;
            margin-bottom: -0.5em;
        }
        .table-copy {
            appearance: none;
            border: 1px solid var(--surface1);
            border-radius: 6px;
            background: var(--surface0);
            color: var(--text);
            padding: 4px 10px;
            font-size: 0.78em;
            cursor: pointer;
        }
        .table-copy:hover { background: var(--surface1); }
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
        .callout-example { border-left-color: var(--mauve); }
        .callout-quote { border-left-color: var(--overlay0); }
        .callout-danger { border-left-color: var(--red); }
        .callout-failure { border-left-color: var(--red); }
        .callout-success { border-left-color: var(--green); }
        .callout-question { border-left-color: var(--yellow); }
        .callout-info { border-left-color: var(--blue); }

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
        th[data-sort-state] { cursor: pointer; user-select: none; }
        .sort-indicator {
            font-size: 0.7em;
            margin-left: 4px;
            color: var(--overlay0);
        }
        th.sort-asc .sort-indicator,
        th.sort-desc .sort-indicator { color: var(--blue); }
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
        .toc-inline {
            margin: 1em 0;
            padding: 14px 16px;
            background: var(--mantle);
            border: 1px solid var(--surface0);
            border-radius: 10px;
        }
        .toc-inline-title {
            font-size: 0.82em;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: var(--subtext0);
            margin-bottom: 8px;
        }
        .toc-inline-link {
            display: block;
            padding: 4px 0;
            color: var(--subtext1);
        }

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
