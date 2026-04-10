// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownFrontmatter.swift - Minimal YAML frontmatter extraction for markdown documents.

import Foundation

// MARK: - Frontmatter

/// Parsed frontmatter metadata extracted from the top of a markdown file.
///
/// Supports the subset of YAML commonly used in markdown frontmatter:
/// scalar values (`key: value`), quoted strings (`key: "value"`), and
/// simple inline lists (`tags: [a, b, c]`). No nested mappings. Values are
/// always exposed as strings or arrays of strings — consumers decide how
/// to interpret them (as dates, bools, etc.).
public struct MarkdownFrontmatter: Equatable, Sendable {

    /// Raw scalar values keyed by top-level key.
    public let scalars: [String: String]

    /// Inline list values (`tags: [a, b]`) keyed by top-level key.
    public let lists: [String: [String]]

    public init(scalars: [String: String] = [:], lists: [String: [String]] = [:]) {
        self.scalars = scalars
        self.lists = lists
    }

    /// Whether the frontmatter had any keys at all.
    public var isEmpty: Bool {
        scalars.isEmpty && lists.isEmpty
    }
}

// MARK: - Extraction Result

/// Result of `MarkdownFrontmatter.extract(from:)`.
public struct MarkdownFrontmatterExtraction: Equatable, Sendable {
    /// The parsed frontmatter (may be empty if the source had none).
    public let frontmatter: MarkdownFrontmatter

    /// The source text with the frontmatter block removed. Consumers feed
    /// this to `MarkdownParser.parse(_:)`.
    public let body: String

    /// Zero-based line offset where the body starts in the original source.
    /// Useful to map parser line numbers back to the original file.
    public let bodyLineOffset: Int
}

// MARK: - Parser

extension MarkdownFrontmatter {

    /// Extracts a YAML frontmatter block from the start of `source`, if
    /// present.
    ///
    /// Frontmatter is recognized when the source starts with a line
    /// containing exactly `---` (after optional whitespace) and is closed
    /// by another `---` line. Everything between is treated as YAML.
    ///
    /// If no frontmatter is present, the result carries an empty
    /// `frontmatter` and the full `body`.
    public static func extract(from source: String) -> MarkdownFrontmatterExtraction {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return MarkdownFrontmatterExtraction(
                frontmatter: MarkdownFrontmatter(),
                body: source,
                bodyLineOffset: 0
            )
        }

        var closeIndex: Int? = nil
        for i in 1..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                closeIndex = i
                break
            }
        }
        guard let close = closeIndex else {
            return MarkdownFrontmatterExtraction(
                frontmatter: MarkdownFrontmatter(),
                body: source,
                bodyLineOffset: 0
            )
        }

        let yamlLines = Array(lines[1..<close])
        let parsed = parseYAML(lines: yamlLines)
        let bodyLines = close + 1 < lines.count ? Array(lines[(close + 1)...]) : []
        let body = bodyLines.joined(separator: "\n")

        return MarkdownFrontmatterExtraction(
            frontmatter: parsed,
            body: body,
            bodyLineOffset: close + 1
        )
    }

    // MARK: - YAML Parser (subset)

    private static func parseYAML(lines: [String]) -> MarkdownFrontmatter {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]

        var pendingListKey: String? = nil
        var pendingList: [String] = []

        func flushPendingList() {
            if let key = pendingListKey {
                lists[key] = pendingList
                pendingListKey = nil
                pendingList = []
            }
        }

        for raw in lines {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            // Pending multi-line list continuation: `- value`.
            if pendingListKey != nil {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed == "-" {
                    let value = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                    pendingList.append(unquote(value))
                    continue
                }
                flushPendingList()
            }

            guard let colonIndex = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if value.isEmpty {
                // Possibly a multi-line list coming next.
                pendingListKey = key
                pendingList = []
                continue
            }

            if value.hasPrefix("["), value.hasSuffix("]") {
                let inside = String(value.dropFirst().dropLast())
                let items = inside
                    .split(separator: ",")
                    .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                lists[key] = items
            } else {
                scalars[key] = unquote(value)
            }
        }

        flushPendingList()
        return MarkdownFrontmatter(scalars: scalars, lists: lists)
    }

    private static func unquote(_ value: String) -> String {
        if value.count >= 2 {
            let first = value.first!
            let last = value.last!
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                return String(value.dropFirst().dropLast())
            }
        }
        return value
    }
}
