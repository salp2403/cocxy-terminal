// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// JupyterNotebookCodecSwiftTestingTests.swift - `.ipynb` import/export coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("JupyterNotebookCodec")
struct JupyterNotebookCodecSwiftTestingTests {
    @Test("exports Cocxy notebook cells to nbformat 4 JSON")
    func exportsNotebookCellsToJupyterJSON() throws {
        let notebook = NotebookDocument(
            metadata: NotebookMetadata(title: "Interop"),
            cells: [
                .markdown("# Interop\n\nMarkdown cell."),
                .code(
                    language: "python",
                    source: "print(\"hello\")",
                    outputs: [
                        NotebookCellOutput(kind: .stdout, text: "hello\n"),
                    ]
                ),
            ]
        )

        let data = try JupyterNotebookCodec.exportData(from: notebook)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let cells = try #require(object["cells"] as? [[String: Any]])
        let codeMetadata = try #require(cells[1]["metadata"] as? [String: Any])
        let cocxyMetadata = try #require(codeMetadata["cocxy"] as? [String: Any])

        #expect(object["nbformat"] as? Int == 4)
        #expect(cells[0]["cell_type"] as? String == "markdown")
        #expect(cells[1]["cell_type"] as? String == "code")
        #expect(cocxyMetadata["language"] as? String == "python")
        #expect((cells[1]["source"] as? [String])?.joined() == "print(\"hello\")")
        #expect(((cells[1]["outputs"] as? [[String: Any]])?.first?["text"] as? [String])?.joined() == "hello\n")
    }

    @Test("imports Jupyter markdown code and stream outputs")
    func importsJupyterNotebook() throws {
        let json = """
        {
          "nbformat": 4,
          "nbformat_minor": 5,
          "metadata": {
            "cocxy": {
              "title": "Imported"
            }
          },
          "cells": [
            {
              "cell_type": "markdown",
              "metadata": {},
              "source": ["# Imported\\n", "Intro"]
            },
            {
              "cell_type": "code",
              "execution_count": 1,
              "metadata": {
                "cocxy": {
                  "language": "bash"
                }
              },
              "outputs": [
                {
                  "output_type": "stream",
                  "name": "stdout",
                  "text": ["done\\n"]
                }
              ],
              "source": ["echo done"]
            }
          ]
        }
        """

        let notebook = try JupyterNotebookCodec.importDocument(from: Data(json.utf8))

        #expect(notebook.metadata.title == "Imported")
        #expect(notebook.cells == [
            .markdown("# Imported\nIntro"),
            .code(
                language: "bash",
                source: "echo done",
                outputs: [NotebookCellOutput(kind: .stdout, text: "done\n")]
            ),
        ])
    }

    @Test("rejects unsupported Jupyter major versions")
    func rejectsUnsupportedMajorVersions() throws {
        let json = """
        {
          "nbformat": 3,
          "nbformat_minor": 0,
          "metadata": {},
          "cells": []
        }
        """

        do {
            _ = try JupyterNotebookCodec.importDocument(from: Data(json.utf8))
            Issue.record("Expected unsupported format error")
        } catch let error as JupyterNotebookCodec.CodecError {
            #expect(error == .unsupportedFormat(nbformat: 3))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
