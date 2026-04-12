// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownOutline.swift - Heading outline extracted from a parsed markdown document.

import Foundation

// MARK: - Outline

/// A navigable tree of headings extracted from a parsed markdown document.
///
/// The outline is flat (a list of `MarkdownOutlineEntry`) with `level` and
/// `sourceLine` carrying the nesting and position information. UI consumers
/// can render a tree directly from the flat list by grouping consecutive
/// entries at deeper levels under the most recent ancestor.
public struct MarkdownOutline: Equatable, Sendable {

    /// All heading entries in document order.
    public let entries: [MarkdownOutlineEntry]

    public init(entries: [MarkdownOutlineEntry]) {
        self.entries = entries
    }

    /// An empty outline (for documents without headings).
    public static let empty = MarkdownOutline(entries: [])

    /// Whether the outline has any entries.
    public var isEmpty: Bool { entries.isEmpty }

    // MARK: - Extraction

    /// Extracts the outline from a parse result. The source line of each
    /// entry corresponds to the block's starting line in the original
    /// (post-frontmatter) source.
    public static func extract(from parseResult: MarkdownParseResult) -> MarkdownOutline {
        var entries: [MarkdownOutlineEntry] = []
        for (index, block) in parseResult.blocks.enumerated() {
            guard case .heading(let level, let inlines) = block else { continue }
            let text = MarkdownOutline.plainText(from: inlines)
            guard !text.isEmpty else { continue }
            entries.append(
                MarkdownOutlineEntry(
                    level: MarkdownBlock.clampedHeadingLevel(level),
                    title: text,
                    sourceLine: parseResult.locations[index].startLine
                )
            )
        }
        return MarkdownOutline(entries: entries)
    }

    // MARK: - Tree View

    /// Hierarchical tree representation of the outline. Useful for
    /// `NSOutlineView` / `List` rendering where children must be nested.
    public func tree() -> [MarkdownOutlineNode] {
        var roots: [MarkdownOutlineNode] = []
        var stack: [MarkdownOutlineNode] = []

        for entry in entries {
            let node = MarkdownOutlineNode(entry: entry)
            while let top = stack.last, top.entry.level >= entry.level {
                stack.removeLast()
            }
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }
        return roots
    }

    // MARK: - Helpers

    static func plainText(from inlines: [MarkdownInline]) -> String {
        var buffer = ""
        for inline in inlines {
            switch inline {
            case .text(let s):
                buffer.append(s)
            case .strong(let nested),
                 .emphasis(let nested),
                 .strike(let nested):
                buffer.append(plainText(from: nested))
            case .code(let s):
                buffer.append(s)
            case .image(let alt, _):
                buffer.append(alt)
            case .link(let text, _):
                buffer.append(plainText(from: text))
            case .autolink(let url):
                buffer.append(url)
            case .lineBreak:
                buffer.append(" ")
            }
        }
        return buffer.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Outline Entry

/// A single heading in a markdown outline.
public struct MarkdownOutlineEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let level: Int
    public let title: String
    public let sourceLine: Int

    public init(level: Int, title: String, sourceLine: Int, id: UUID = UUID()) {
        self.id = id
        self.level = level
        self.title = title
        self.sourceLine = sourceLine
    }

    public static func == (lhs: MarkdownOutlineEntry, rhs: MarkdownOutlineEntry) -> Bool {
        lhs.level == rhs.level
            && lhs.title == rhs.title
            && lhs.sourceLine == rhs.sourceLine
    }
}

// MARK: - Outline Node (Tree)

/// Reference-type node for hierarchical rendering. Uses a class so AppKit
/// outline views can identify rows by object identity.
public final class MarkdownOutlineNode {
    public let entry: MarkdownOutlineEntry
    public var children: [MarkdownOutlineNode]

    public init(entry: MarkdownOutlineEntry, children: [MarkdownOutlineNode] = []) {
        self.entry = entry
        self.children = children
    }
}
