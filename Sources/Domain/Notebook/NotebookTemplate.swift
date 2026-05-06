// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookTemplate.swift - Built-in local notebook templates.

import Foundation

struct NotebookTemplate: Sendable, Equatable {
    let id: String
    let title: String
    let summary: String
    let document: NotebookDocument
}

enum NotebookTemplateCatalog {
    static let builtInTemplates: [NotebookTemplate] = [
        NotebookTemplate(
            id: "scratch",
            title: "Scratch Notebook",
            summary: "Blank local notebook with a shell cell.",
            document: NotebookDocument(
                metadata: NotebookMetadata(title: "Scratch Notebook", tags: ["scratch"]),
                cells: [
                    .markdown("# Scratch\n\nUse this notebook for quick local notes and commands."),
                    .code(language: "bash", source: "echo \"hello from Cocxy\""),
                ]
            )
        ),
        NotebookTemplate(
            id: "python-analysis",
            title: "Python Analysis",
            summary: "Small Python analysis notebook with local-only execution.",
            document: NotebookDocument(
                metadata: NotebookMetadata(title: "Python Analysis", tags: ["python", "analysis"]),
                cells: [
                    .markdown("# Python Analysis\n\nStart with local data, then summarize the result."),
                    .code(
                        language: "python",
                        source: """
                        values = [3, 5, 8]
                        summary = {"count": len(values), "total": sum(values)}
                        print(summary)
                        """
                    ),
                ]
            )
        ),
        NotebookTemplate(
            id: "swift-script",
            title: "Swift Script",
            summary: "Swift scripting notebook for local automation.",
            document: NotebookDocument(
                metadata: NotebookMetadata(title: "Swift Script", tags: ["swift", "automation"]),
                cells: [
                    .markdown("# Swift Script\n\nRun a local Swift snippet from the notebook."),
                    .code(
                        language: "swift",
                        source: """
                        import Foundation

                        print("swift notebook ready")
                        """
                    ),
                ]
            )
        ),
    ]

    static func template(id: String) -> NotebookTemplate? {
        builtInTemplates.first { $0.id == id }
    }
}
