// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownDocument.swift - Full parsed markdown document: source + AST + outline + frontmatter.

import Foundation

// MARK: - Document

/// Full parsed representation of a markdown document.
///
/// Created by `MarkdownDocument.parse(_:)`. Carries:
/// - the raw source,
/// - the extracted frontmatter (may be empty),
/// - the body text with frontmatter removed,
/// - the block AST and source locations,
/// - the heading outline.
///
/// This is the single model consumed by the Markdown UI layer. All
/// transformations (syntax highlighting, preview rendering, outline
/// navigation) derive their data from a single `MarkdownDocument` instance,
/// which guarantees consistency across modes.
public struct MarkdownDocument: Equatable, Sendable {
    public let source: String
    public let frontmatter: MarkdownFrontmatter
    public let body: String
    public let parseResult: MarkdownParseResult
    public let outline: MarkdownOutline
    public let bodyLineOffset: Int

    public init(
        source: String,
        frontmatter: MarkdownFrontmatter,
        body: String,
        parseResult: MarkdownParseResult,
        outline: MarkdownOutline,
        bodyLineOffset: Int
    ) {
        self.source = source
        self.frontmatter = frontmatter
        self.body = body
        self.parseResult = parseResult
        self.outline = outline
        self.bodyLineOffset = bodyLineOffset
    }

    // MARK: - Parsing

    /// Parses a raw markdown source into a full document model.
    ///
    /// The pipeline is:
    /// 1. Extract frontmatter (if any).
    /// 2. Parse the body into a block tree.
    /// 3. Extract the heading outline.
    ///
    /// The operation is pure: calling `parse(_:)` twice on the same input
    /// yields equal results.
    public static func parse(_ source: String) -> MarkdownDocument {
        let extraction = MarkdownFrontmatter.extract(from: source)
        let parseResult = MarkdownParser().parse(extraction.body)
        let outline = MarkdownOutline.extract(from: parseResult)
        return MarkdownDocument(
            source: source,
            frontmatter: extraction.frontmatter,
            body: extraction.body,
            parseResult: parseResult,
            outline: outline,
            bodyLineOffset: extraction.bodyLineOffset
        )
    }

    /// An empty document representing "no file loaded".
    public static let empty = MarkdownDocument(
        source: "",
        frontmatter: MarkdownFrontmatter(),
        body: "",
        parseResult: MarkdownParseResult(blocks: [], locations: []),
        outline: .empty,
        bodyLineOffset: 0
    )

    /// Whether the document has no parsed content.
    public var isEmpty: Bool {
        parseResult.blocks.isEmpty
    }

    /// Maps a body line index (0-based, as used by block locations) back
    /// to the original source line (accounting for frontmatter).
    public func sourceLine(forBodyLine bodyLine: Int) -> Int {
        bodyLineOffset + bodyLine
    }
}
