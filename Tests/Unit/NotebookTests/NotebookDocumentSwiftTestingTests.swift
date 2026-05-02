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
