// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("MarkdownFrontmatter")
struct MarkdownFrontmatterTests {

    @Test("no frontmatter leaves source untouched")
    func noFrontmatter() {
        let source = "# Title\n\nparagraph"
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.frontmatter.isEmpty == true)
        #expect(result.body == source)
        #expect(result.bodyLineOffset == 0)
    }

    @Test("basic scalar frontmatter extracted")
    func basicScalars() {
        let source = """
        ---
        title: Hello
        author: Said
        ---
        body text
        """
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.frontmatter.scalars["title"] == "Hello")
        #expect(result.frontmatter.scalars["author"] == "Said")
        #expect(result.body == "body text")
    }

    @Test("quoted values have quotes stripped")
    func quotedValues() {
        let source = """
        ---
        title: "Quoted Title"
        name: 'single quoted'
        ---
        body
        """
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.frontmatter.scalars["title"] == "Quoted Title")
        #expect(result.frontmatter.scalars["name"] == "single quoted")
    }

    @Test("inline list frontmatter")
    func inlineList() {
        let source = """
        ---
        tags: [swift, macos, terminal]
        ---
        body
        """
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.frontmatter.lists["tags"] == ["swift", "macos", "terminal"])
    }

    @Test("multi-line list frontmatter")
    func multilineList() {
        let source = """
        ---
        tags:
          - swift
          - macos
        ---
        body
        """
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.frontmatter.lists["tags"] == ["swift", "macos"])
    }

    @Test("missing closing fence leaves source untouched")
    func missingClosingFence() {
        let source = "---\ntitle: X"
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.frontmatter.isEmpty == true)
        #expect(result.body == source)
    }

    @Test("bodyLineOffset points to the first body line")
    func bodyLineOffset() {
        let source = """
        ---
        title: X
        ---
        line one
        line two
        """
        let result = MarkdownFrontmatter.extract(from: source)
        #expect(result.bodyLineOffset == 3)
    }
}
