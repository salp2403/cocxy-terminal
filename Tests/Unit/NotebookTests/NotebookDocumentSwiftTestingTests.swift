// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookDocumentSwiftTestingTests.swift - Canonical `.cocxynb` markdown coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("NotebookDocument markdown format")
struct NotebookDocumentSwiftTestingTests {
    @Test("parses markdown frontmatter and executable code fences into notebook cells")
    func parsesMarkdownFrontmatterAndExecutableCodeFences() {
        let notebook = NotebookDocument.parseMarkdown("""
        ---
        cocxy-notebook: "1"
        title: "Setup"
        tags: [demo, local]
        ---

        # Setup

        Prepare the project.

        ```python
        print("hello")
        ```

        Continue in the shell.

        ```bash
        echo done
        ```
        """)

        #expect(notebook.metadata.title == "Setup")
        #expect(notebook.metadata.tags == ["demo", "local"])
        #expect(notebook.cells.count == 4)
        #expect(notebook.cells[0].kind == .markdown)
        #expect(notebook.cells[0].source.contains("Prepare the project."))
        #expect(notebook.cells[1].kind == .code)
        #expect(notebook.cells[1].language == "python")
        #expect(notebook.cells[1].source == "print(\"hello\")")
        #expect(notebook.cells[3].language == "bash")
    }

    @Test("renders canonical markdown that round-trips through the parser")
    func rendersCanonicalMarkdownRoundTrip() {
        let original = NotebookDocument(
            metadata: NotebookMetadata(title: "Demo", tags: ["swift", "notebook"]),
            cells: [
                .markdown("# Demo\n\nNotes before code."),
                .code(language: "swift", source: "print(\"hi\")"),
                .markdown("Final note."),
            ]
        )

        let rendered = NotebookMarkdownCodec.render(original)
        let reparsed = NotebookDocument.parseMarkdown(rendered)

        #expect(rendered.contains("cocxy-notebook: \"1\""))
        #expect(rendered.contains("title: \"Demo\""))
        #expect(rendered.contains("tags: [swift, notebook]"))
        #expect(rendered.contains("```swift\nprint(\"hi\")\n```"))
        #expect(reparsed.metadata == original.metadata)
        #expect(reparsed.cells == original.cells)
    }

    @Test("renders code outputs so Jupyter imports round-trip without data loss")
    func rendersCodeOutputsWithoutDataLoss() {
        let original = NotebookDocument(
            metadata: NotebookMetadata(title: "Output Demo"),
            cells: [
                .code(
                    language: "python",
                    source: "print('ok')",
                    outputs: [
                        NotebookCellOutput(kind: .stdout, text: "ok\n"),
                        NotebookCellOutput(kind: .stderr, text: "warn\n"),
                        NotebookCellOutput(kind: .displayData, text: "inline"),
                    ]
                ),
            ]
        )

        let rendered = NotebookMarkdownCodec.render(original)
        let reparsed = NotebookDocument.parseMarkdown(rendered)

        #expect(rendered.contains("```cocxy-output stdout\nok\n```"))
        #expect(rendered.contains("```cocxy-output stderr\nwarn\n```"))
        #expect(rendered.contains("```cocxy-output display-data no-final-newline\ninline\n```"))
        #expect(reparsed.cells == original.cells)
    }

    @Test("fence-shaped outputs cannot create executable cells after rendering")
    func fenceShapedOutputsPreserveCellGraphAndOwnership() {
        let original = NotebookDocument(
            metadata: NotebookMetadata(title: "Untrusted Output"),
            cells: [
                .code(
                    language: "bash",
                    source: "echo authored",
                    outputs: [
                        NotebookCellOutput(
                            kind: .stdout,
                            text: "safe\n```\n```bash\necho forged\n```\n"
                        ),
                        NotebookCellOutput(
                            kind: .stderr,
                            text: "warn\n   ```\n```python\nprint('forged')\n```\n"
                        ),
                        NotebookCellOutput(
                            kind: .displayData,
                            text: "~~~\n~~~swift\nprint(\"not executable\")\n~~~"
                        ),
                        NotebookCellOutput(
                            kind: .error,
                            text: "before\n``````\n```swift\nprint(\"forged\")\n```\nafter"
                        ),
                    ]
                ),
            ]
        )

        let rendered = NotebookMarkdownCodec.render(original)
        let reparsed = NotebookDocument.parseMarkdown(rendered)

        #expect(rendered.contains("````cocxy-output stdout"))
        #expect(rendered.contains("```````cocxy-output error no-final-newline"))
        #expect(reparsed == original)
        #expect(reparsed.cells.count == 1)
        #expect(reparsed.cells.first?.source == "echo authored")
        #expect(reparsed.cells.first?.outputs == original.cells.first?.outputs)
    }

    @Test("output corpus round-trips without changing executable structure")
    func outputCorpusPreservesExecutableStructure() {
        let corpus = [
            "",
            "\n",
            "\n\n",
            "plain text",
            "plain text\n",
            "```",
            "```\n",
            "  ```  \n```bash\necho forged\n```",
            "~~~~\n~~~python\nprint('data')\n~~~~\n",
            String(repeating: "`", count: 64) + "\n```swift\nprint(\"data\")\n```\n",
            "Unicode: cafe\u{0301} - \u{4F60}\u{597D}\n",
            "embedded\u{0000}nul\n",
            "````cocxy-output stderr\nnested marker\n````\n",
        ]

        for kind in [
            NotebookCellOutputKind.stdout,
            .stderr,
            .displayData,
            .error,
        ] {
            for outputText in corpus {
                let original = NotebookDocument(cells: [
                    .code(
                        language: "bash",
                        source: "printf authored",
                        outputs: [NotebookCellOutput(kind: kind, text: outputText)]
                    ),
                ])

                let reparsed = NotebookDocument.parseMarkdown(
                    NotebookMarkdownCodec.render(original)
                )

                #expect(reparsed == original)
                #expect(reparsed.cells.count == 1)
                #expect(reparsed.cells.first?.source == "printf authored")
            }
        }
    }

    @Test("fence-shaped authored code round-trips as one code cell")
    func fenceShapedAuthoredCodePreservesSource() {
        let source = "echo begin\n```\n```python\nprint('data')\n```\necho end"
        let original = NotebookDocument(cells: [
            .code(language: "bash", source: source),
        ])

        let rendered = NotebookMarkdownCodec.render(original)
        let reparsed = NotebookDocument.parseMarkdown(rendered)

        #expect(rendered.contains("````bash\n"))
        #expect(reparsed == original)
        #expect(reparsed.cells.count == 1)
    }

    @Test("non executable fences remain inside markdown cells")
    func nonExecutableFencesRemainMarkdown() {
        let notebook = NotebookDocument.parseMarkdown("""
        Explain this JSON:

        ```json
        {"ok": true}
        ```

        ```swift
        print("run")
        ```
        """)

        #expect(notebook.cells.count == 2)
        #expect(notebook.cells[0].kind == .markdown)
        #expect(notebook.cells[0].source.contains("```json"))
        #expect(notebook.cells[1].kind == .code)
        #expect(notebook.cells[1].language == "swift")
    }
}
