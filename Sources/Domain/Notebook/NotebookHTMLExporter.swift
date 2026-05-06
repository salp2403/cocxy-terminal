// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookHTMLExporter.swift - Standalone local HTML export for Cocxy notebooks.

import Foundation
import CocxyMarkdownLib

enum NotebookHTMLExporter {
    static func render(_ notebook: NotebookDocument) -> String {
        let title = notebook.metadata.title ?? "Cocxy Notebook"
        let cells = notebook.cells.enumerated()
            .map { renderCell($0.element, index: $0.offset) }
            .joined(separator: "\n")
        let tags = notebook.metadata.tags.map(renderTag).joined()

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>\(escapeHTML(title))</title>
          <style>
            :root {
              color-scheme: light dark;
              --bg: #11111b;
              --surface: #1e1e2e;
              --surface-2: #313244;
              --text: #cdd6f4;
              --muted: #a6adc8;
              --accent: #89b4fa;
              --ok: #a6e3a1;
              --warn: #f9e2af;
              --danger: #f38ba8;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              background: var(--bg);
              color: var(--text);
              font: 15px/1.65 -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", sans-serif;
            }
            main { max-width: 980px; margin: 0 auto; padding: 48px 24px 72px; }
            header { margin-bottom: 32px; }
            h1 { margin: 0 0 8px; font-size: 2rem; line-height: 1.2; }
            .tags { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
            .tag {
              border: 1px solid var(--surface-2);
              border-radius: 999px;
              color: var(--muted);
              padding: 2px 10px;
              font-size: 0.82rem;
            }
            .notebook-cell {
              border: 1px solid var(--surface-2);
              border-radius: 10px;
              background: var(--surface);
              margin: 18px 0;
              overflow: hidden;
            }
            .notebook-cell-markdown { padding: 20px 24px; }
            .notebook-cell-code { padding: 0; }
            .cell-input, .cell-output { padding: 16px 18px; }
            .cell-input { border-bottom: 1px solid var(--surface-2); }
            .cell-label {
              color: var(--muted);
              font-size: 0.75rem;
              font-weight: 700;
              letter-spacing: 0.08em;
              margin-bottom: 10px;
              text-transform: uppercase;
            }
            pre {
              margin: 0;
              overflow-x: auto;
              white-space: pre-wrap;
              word-break: break-word;
            }
            code, pre {
              font-family: "JetBrains Mono", "SF Mono", Menlo, Consolas, monospace;
              font-size: 0.92rem;
            }
            .cell-output { border-top: 1px solid var(--surface-2); }
            .cell-output-stdout { color: var(--ok); }
            .cell-output-stderr { color: var(--warn); }
            .cell-output-error { color: var(--danger); }
            a { color: var(--accent); }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid var(--surface-2); padding: 8px 10px; }
            blockquote { border-left: 3px solid var(--accent); margin-left: 0; padding-left: 16px; color: var(--muted); }
          </style>
        </head>
        <body>
          <main>
            <header>
              <h1>\(escapeHTML(title))</h1>
              \(tags.isEmpty ? "" : "<div class=\"tags\">\(tags)</div>")
            </header>
            \(cells)
          </main>
        </body>
        </html>
        """
    }

    private static func renderCell(_ cell: NotebookCell, index: Int) -> String {
        switch cell.kind {
        case .markdown:
            let result = MarkdownParser().parse(cell.source)
            let html = MarkdownHTMLRenderer.render(result)
            return """
            <section class="notebook-cell notebook-cell-markdown" data-cell-index="\(index)">
            \(html)
            </section>
            """
        case .code:
            let language = cell.language ?? "text"
            let outputs = cell.outputs.map(renderOutput).joined(separator: "\n")
            return """
            <section class="notebook-cell notebook-cell-code" data-cell-index="\(index)">
              <div class="cell-input">
                <div class="cell-label">\(escapeHTML(language))</div>
                <pre><code class="language-\(escapeHTML(language))">\(escapeHTML(cell.source))</code></pre>
              </div>
              \(outputs)
            </section>
            """
        }
    }

    private static func renderOutput(_ output: NotebookCellOutput) -> String {
        """
        <div class="cell-output cell-output-\(output.kind.rawValue)">
          <div class="cell-label">\(escapeHTML(output.kind.rawValue))</div>
          <pre>\(escapeHTML(output.text))</pre>
        </div>
        """
    }

    private static func renderTag(_ tag: String) -> String {
        "<span class=\"tag\">\(escapeHTML(tag))</span>"
    }

    private static func escapeHTML(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }
}
