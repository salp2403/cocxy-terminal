// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("MarkdownInteractive", .serialized)
@MainActor
struct MarkdownInteractiveTests {

    @Test("HTML renderer emits source-line attributes using original source lines")
    func rendererEmitsSourceLineAttributes() {
        let document = MarkdownDocument.parse("""
        ---
        title: Test
        ---
        # Heading

        - [ ] Ship
        """)
        let html = MarkdownHTMLRenderer.renderDocument(document)

        #expect(html.contains("data-source-line=\"3\""))
        #expect(html.contains("data-source-line=\"5\""))
    }

    @Test("checkbox HTML is interactive and indexed")
    func checkboxHTMLIsIndexed() {
        let html = MarkdownHTMLRenderer.render(MarkdownParser().parse("- [ ] first\n- [x] second"))
        #expect(html.contains("data-checkbox-index=\"0\""))
        #expect(html.contains("data-checkbox-index=\"1\""))
        #expect(!html.contains("disabled"))
    }

    @Test("preview template contains bridge, lightbox and popover infrastructure")
    func previewTemplateContainsInteractiveInfrastructure() {
        let html = MarkdownPreviewTemplate.build(highlightJS: "window.hljs={};")
        #expect(html.contains("messageHandlers.cocxy"))
        #expect(html.contains("lightbox-overlay"))
        #expect(html.contains("footnote-popover"))
        #expect(html.contains("copyCode"))
    }

    @Test("source view toggles nth checkbox marker")
    func sourceViewTogglesNthCheckbox() {
        let view = MarkdownSourceView()
        view.document = MarkdownDocument.parse("- [ ] first\n- [x] second\n- [ ] third")

        #expect(view.toggleCheckboxAtIndex(2, checked: true))
        #expect(view.currentSource.contains("- [x] third"))

        #expect(view.toggleCheckboxAtIndex(0, checked: true))
        #expect(view.currentSource.contains("- [x] first"))
    }

    @Test("click to source switches preview-only mode into split")
    func clickToSourceAutoSplits() {
        let url = createTempMarkdownFile(content: "# Hello\n\nBody")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        view.mode = .preview

        view.previewView.onClickToSource?(0)

        #expect(view.mode == .split)
        #expect(view.sourceView.selectedSourceRange.location == 0)
    }

    @Test("persist pasted image data falls back to temporary directory")
    func pastedImageFallsBackToTemporaryDirectory() throws {
        let view = MarkdownContentView(filePath: nil)
        let url = try #require(view.persistPastedImageData(Data([0x89, 0x50, 0x4E, 0x47]), now: Date(timeIntervalSince1970: 0)))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.deletingLastPathComponent() == FileManager.default.temporaryDirectory)
        #expect(url.lastPathComponent.hasPrefix("paste-19700101-000000"))
    }

    private func createTempMarkdownFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("interactive-\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
