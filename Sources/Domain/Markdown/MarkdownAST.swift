// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownAST.swift - Abstract syntax tree node types for the markdown parser.

import Foundation

// MARK: - Block Nodes

/// A top-level block element in a markdown document.
///
/// `MarkdownBlock` is a pure value type — every case carries enough data to
/// render itself without needing to walk back to the document root. Nested
/// blocks (lists, blockquotes) recurse through `MarkdownBlock` so layout
/// passes can traverse the tree uniformly.
///
/// The parser never produces `.paragraph([])`, `.heading(level:inlines:[])`,
/// or empty lists; each case's invariants are documented inline so downstream
/// consumers (the renderer, the outline extractor, tests) can rely on them.
public enum MarkdownBlock: Equatable, Sendable {
    /// An ATX heading (`# ... ######`). `level` is clamped to 1...6.
    case heading(level: Int, inlines: [MarkdownInline])

    /// A plain paragraph of inline content. Always has at least one inline.
    case paragraph(inlines: [MarkdownInline])

    /// A blockquote wrapping nested block elements (may include other
    /// blockquotes, lists, headings, etc.).
    case blockquote(blocks: [MarkdownBlock])

    /// A GitHub/Obsidian-style admonition rendered from `> [!TYPE]`.
    case callout(type: MarkdownCalloutType, title: String, isFolded: Bool, blocks: [MarkdownBlock])

    /// An unordered or ordered list. `items` is never empty.
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])

    /// A fenced or indented code block. `language` is `nil` for indented
    /// blocks and for fenced blocks without an info string.
    case codeBlock(language: String?, text: String)

    /// A GitHub-flavored table with header row, column alignments, and rows.
    case table(headers: [[MarkdownInline]], alignments: [MarkdownTableAlignment], rows: [[[MarkdownInline]]])

    /// A footnote definition block (`[^id]: definition`).
    case footnoteDefinition(id: String, blocks: [MarkdownBlock])

    /// A horizontal rule (`---`, `***`, `___`).
    case horizontalRule
}

// MARK: - List Items

/// A single item in a markdown list.
///
/// An item may carry nested block content (paragraphs, sublists) and, for GFM
/// task lists, a checkbox state. A task item still has inline content; the
/// parser records the checkbox state without mutating the inline stream.
public struct MarkdownListItem: Equatable, Sendable {
    public let blocks: [MarkdownBlock]
    public let taskState: MarkdownTaskState

    public init(blocks: [MarkdownBlock], taskState: MarkdownTaskState = .none) {
        self.blocks = blocks
        self.taskState = taskState
    }
}

/// Task-list state for a list item.
public enum MarkdownTaskState: Equatable, Sendable {
    /// Not a task item.
    case none
    /// `- [ ]` unchecked task.
    case unchecked
    /// `- [x]` checked task.
    case checked
}

// MARK: - Tables

/// Column alignment for a GFM table.
public enum MarkdownTableAlignment: Equatable, Sendable {
    case none
    case left
    case center
    case right
}

// MARK: - Inline Nodes

/// Inline element inside a paragraph, heading, list item, or table cell.
///
/// Inlines can nest: `.strong([.emphasis([.text("hi")])])` is a valid tree
/// representing `***hi***`. The parser flattens adjacent text runs, so a
/// paragraph never contains two consecutive `.text` cases.
public enum MarkdownInline: Equatable, Sendable {
    /// A run of plain text. Contains no formatting.
    case text(String)

    /// Strong emphasis (`**text**`, `__text__`). May wrap further inlines.
    case strong(inlines: [MarkdownInline])

    /// Italic emphasis (`*text*`, `_text_`). May wrap further inlines.
    case emphasis(inlines: [MarkdownInline])

    /// Inline code span (`` `text` ``). Always stores the raw code text,
    /// never nested inlines (code spans are atomic).
    case code(text: String)

    /// GFM strikethrough (`~~text~~`).
    case strike(inlines: [MarkdownInline])

    /// Highlight (`==text==`).
    case highlight(inlines: [MarkdownInline])

    /// Superscript (`^text^`).
    case superscript(inlines: [MarkdownInline])

    /// Subscript (`~text~`).
    case `subscript`(inlines: [MarkdownInline])

    /// Link with display text and URL. The display text is itself a list of
    /// inlines so `[**bold**](url)` round-trips correctly.
    case link(text: [MarkdownInline], url: String)

    /// Image (`![alt](url)`). The alt text and source URL.
    case image(alt: String, url: String)

    /// Autolink (`<http://...>`). The URL doubles as display text.
    case autolink(url: String)

    /// Footnote reference (`[^id]`).
    case footnoteRef(id: String)

    /// Hard line break (`  \n` or `\\`).
    case lineBreak
}

// MARK: - Invariants

extension MarkdownBlock {

    /// Clamped heading level. Use when constructing heading nodes to ensure
    /// the invariant that level is always in 1...6.
    public static func clampedHeadingLevel(_ raw: Int) -> Int {
        min(6, max(1, raw))
    }
}
