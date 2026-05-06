// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookHTMLExporterSwiftTestingTests.swift - Standalone HTML export coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("NotebookHTMLExporter")
struct NotebookHTMLExporterSwiftTestingTests {
    @Test("exports a standalone HTML document with markdown code and outputs")
    func exportsStandaloneHTMLDocument() {
        let notebook = NotebookDocument(
            metadata: NotebookMetadata(title: "Local Demo", tags: ["swift", "html"]),
            cells: [
                .markdown("# Report\n\nSummary with **bold** text."),
                .code(
                    language: "bash",
                    source: "printf '<ok>\\n'",
                    outputs: [
                        NotebookCellOutput(kind: .stdout, text: "<ok>\n"),
                        NotebookCellOutput(kind: .stderr, text: "warn\n"),
                    ]
                ),
            ]
        )

        let html = NotebookHTMLExporter.render(notebook)

        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<title>Local Demo</title>"))
        #expect(html.contains("<h1 data-source-line=\"0\" id=\"heading-0\">Report</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("class=\"notebook-cell notebook-cell-code\""))
        #expect(html.contains("<code class=\"language-bash\">printf &#39;&lt;ok&gt;\\n&#39;</code>"))
        #expect(html.contains("class=\"cell-output cell-output-stdout\""))
        #expect(html.contains("&lt;ok&gt;"))
        #expect(html.contains("class=\"cell-output cell-output-stderr\""))
        #expect(!html.contains("<ok>\n"))
    }
}
