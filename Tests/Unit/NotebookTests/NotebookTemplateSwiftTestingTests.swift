// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookTemplateSwiftTestingTests.swift - Built-in notebook template coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Notebook templates")
struct NotebookTemplateSwiftTestingTests {
    @Test("built-in notebook templates have stable unique ids")
    func builtInTemplatesHaveStableUniqueIDs() throws {
        let templates = NotebookTemplateCatalog.builtInTemplates
        let ids = templates.map(\.id)

        #expect(ids.contains("scratch"))
        #expect(ids.contains("python-analysis"))
        #expect(ids.contains("swift-script"))
        #expect(Set(ids).count == ids.count)
        #expect(templates.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
    }

    @Test("renders a selected template as canonical Cocxy notebook markdown")
    func rendersSelectedTemplateAsCanonicalNotebook() throws {
        let template = try #require(NotebookTemplateCatalog.template(id: "python-analysis"))
        let rendered = NotebookMarkdownCodec.render(template.document)
        let reparsed = NotebookDocument.parseMarkdown(rendered)

        #expect(rendered.contains("cocxy-notebook: \"1\""))
        #expect(rendered.contains("title: \"Python Analysis\""))
        #expect(reparsed.metadata.title == "Python Analysis")
        #expect(reparsed.cells.contains { $0.kind == .code && $0.language == "python" })
    }
}
