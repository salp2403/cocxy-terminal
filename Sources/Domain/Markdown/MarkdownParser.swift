// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownParser.swift - Block-level markdown parser producing MarkdownBlock trees.

import Foundation

// MARK: - Parser Result

/// Parsing result returned by `MarkdownParser.parse(_:)`.
///
/// Carries the block tree plus the raw source locations of each top-level
/// block. Source locations let the UI syntax highlighter align AST-based
/// styling with the original text without re-parsing.
public struct MarkdownParseResult: Equatable, Sendable {
    /// The parsed top-level blocks (order preserved).
    public let blocks: [MarkdownBlock]

    /// Source line spans (0-based, inclusive) for each block in `blocks`.
    /// `locations.count == blocks.count`.
    public let locations: [MarkdownBlockLocation]

    /// Collected reference-style link definitions keyed by normalized label.
    public let linkDefinitions: [String: String]

    public init(
        blocks: [MarkdownBlock],
        locations: [MarkdownBlockLocation],
        linkDefinitions: [String: String] = [:]
    ) {
        self.blocks = blocks
        self.locations = locations
        self.linkDefinitions = linkDefinitions
    }
}

/// Source location for a parsed block, in zero-based line indices.
public struct MarkdownBlockLocation: Equatable, Sendable {
    public let startLine: Int
    public let endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

// MARK: - Parser

/// GitHub-flavored markdown block parser written in pure Swift.
///
/// The parser operates on a pre-split array of lines and produces a
/// `MarkdownParseResult`. Recognized blocks:
///
/// - ATX headings (`#` .. `######`)
/// - Fenced code blocks (``` and `~~~`) with optional language info
/// - Indented code blocks (four-space indent)
/// - Blockquotes (`> ...`)
/// - Unordered lists (`-`, `*`, `+`)
/// - Ordered lists (`N.` / `N)`)
/// - Task list items (GFM — `[ ]` / `[x]`)
/// - Nested lists via indentation
/// - GFM tables (header + separator + rows)
/// - Horizontal rules (`---`, `***`, `___`)
/// - Paragraphs with inline content
///
/// Frontmatter (`---\n...\n---`) is deliberately NOT handled here; it is
/// extracted by `MarkdownFrontmatter` before `MarkdownParser.parse(_:)` runs
/// so the block parser never has to reason about it.
public struct MarkdownParser {
    private let linkDefinitions: [String: String]

    public init(linkDefinitions: [String: String] = [:]) {
        self.linkDefinitions = linkDefinitions
    }

    // MARK: Entry Point

    /// Parses a markdown document (after frontmatter extraction) into a
    /// block tree.
    ///
    /// - Parameter source: The markdown source, without frontmatter. Line
    ///   endings may be `\n` or `\r\n`; both are normalized internally.
    public func parse(_ source: String) -> MarkdownParseResult {
        let lines = Self.splitLines(source)
        if linkDefinitions.isEmpty {
            let (definitions, skippedLines) = Self.collectReferenceLinkDefinitions(from: lines)
            return MarkdownParser(linkDefinitions: definitions).parseLines(
                lines,
                skippedLines: skippedLines
            )
        }

        return parseLines(lines, skippedLines: [])
    }

    private var inlineParser: MarkdownInlineParser {
        MarkdownInlineParser(linkDefinitions: linkDefinitions)
    }

    private func parseLines(_ lines: [String], skippedLines: Set<Int>) -> MarkdownParseResult {
        var cursor = 0
        var blocks: [MarkdownBlock] = []
        var locations: [MarkdownBlockLocation] = []

        while cursor < lines.count {
            if skippedLines.contains(cursor) {
                cursor += 1
                continue
            }
            if Self.isBlankLine(lines[cursor]) {
                cursor += 1
                continue
            }

            let startLine = cursor
            let (block, consumed) = parseBlock(lines: lines, startingAt: cursor)
            if let block {
                blocks.append(block)
                locations.append(
                    MarkdownBlockLocation(startLine: startLine, endLine: cursor + consumed - 1)
                )
            }
            cursor += consumed
        }

        return MarkdownParseResult(
            blocks: blocks,
            locations: locations,
            linkDefinitions: linkDefinitions
        )
    }

    // MARK: - Block Dispatch

    /// Parses a single top-level block starting at `startingAt`. Returns the
    /// parsed block (or `nil` if the line is skipped silently) and the number
    /// of lines consumed.
    private func parseBlock(
        lines: [String],
        startingAt start: Int
    ) -> (MarkdownBlock?, Int) {
        let line = lines[start]

        if let (block, consumed) = parseHorizontalRule(line) {
            return (block, consumed)
        }
        if let (block, consumed) = parseAtxHeading(line) {
            return (block, consumed)
        }
        if let (block, consumed) = parseFencedCodeBlock(lines: lines, at: start) {
            return (block, consumed)
        }
        if let (block, consumed) = parseIndentedCodeBlock(lines: lines, at: start) {
            return (block, consumed)
        }
        if let (block, consumed) = parseBlockquote(lines: lines, at: start) {
            return (block, consumed)
        }
        if let (block, consumed) = parseFootnoteDefinition(lines: lines, at: start) {
            return (block, consumed)
        }
        if let (block, consumed) = parseList(lines: lines, at: start) {
            return (block, consumed)
        }
        if let (block, consumed) = parseTable(lines: lines, at: start) {
            return (block, consumed)
        }

        // Fallback: paragraph. Consumes consecutive non-empty lines that
        // aren't the start of another block.
        return parseParagraph(lines: lines, at: start)
    }

    // MARK: - Horizontal Rule

    private func parseHorizontalRule(_ line: String) -> (MarkdownBlock, Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        let first = trimmed.first!
        guard first == "-" || first == "*" || first == "_" else { return nil }
        guard trimmed.allSatisfy({ $0 == first || $0 == " " }) else { return nil }
        let markerCount = trimmed.filter { $0 == first }.count
        guard markerCount >= 3 else { return nil }
        return (.horizontalRule, 1)
    }

    // MARK: - ATX Heading

    private func parseAtxHeading(_ line: String) -> (MarkdownBlock, Int)? {
        var level = 0
        let scalars = Array(line)
        var i = 0
        // Up to 3 spaces of leading indent allowed.
        while i < scalars.count && scalars[i] == " " && i < 3 {
            i += 1
        }
        while i < scalars.count, scalars[i] == "#" {
            level += 1
            i += 1
        }
        guard level > 0, level <= 6 else { return nil }

        // ATX heading must have a space after #s (or end-of-line).
        if i < scalars.count, scalars[i] != " ", scalars[i] != "\t" {
            return nil
        }
        // Skip the separating space.
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" {
            i += 1
        }

        // Trim trailing `#` sequence if preceded by a space.
        var text = String(scalars[i...])
        if let tail = text.range(of: "\\s+#+$", options: .regularExpression) {
            text.removeSubrange(tail)
        }
        text = text.trimmingCharacters(in: .whitespaces)

        let inlines = inlineParser.parse(text)
        return (.heading(level: level, inlines: inlines), 1)
    }

    // MARK: - Lists

    /// Matches a list-item marker line and returns the marker, the content
    /// after the marker, and the indent level.
    private struct ListMarkerMatch {
        let ordered: Bool
        let start: Int
        let contentOffset: Int // how many leading characters to strip to get inner content
    }

    private func matchListMarker(_ line: String) -> ListMarkerMatch? {
        var i = 0
        let chars = Array(line)
        while i < chars.count && chars[i] == " " && i < 4 {
            i += 1
        }
        guard i < chars.count else { return nil }

        // Unordered: -, *, + followed by space.
        if chars[i] == "-" || chars[i] == "*" || chars[i] == "+" {
            if i + 1 >= chars.count || chars[i + 1] == " " || chars[i + 1] == "\t" {
                return ListMarkerMatch(
                    ordered: false,
                    start: 1,
                    contentOffset: (i + 2 <= chars.count) ? (i + 2) : (i + 1)
                )
            }
        }

        // Ordered: 1+ digits, then `.` or `)`, then space.
        var digitEnd = i
        while digitEnd < chars.count, chars[digitEnd].isNumber {
            digitEnd += 1
        }
        if digitEnd > i, digitEnd < chars.count,
           chars[digitEnd] == "." || chars[digitEnd] == ")" {
            let afterPunct = digitEnd + 1
            if afterPunct >= chars.count || chars[afterPunct] == " " || chars[afterPunct] == "\t" {
                let startVal = Int(String(chars[i..<digitEnd])) ?? 1
                return ListMarkerMatch(
                    ordered: true,
                    start: startVal,
                    contentOffset: afterPunct + 1 <= chars.count ? afterPunct + 1 : afterPunct
                )
            }
        }
        return nil
    }

    private func parseList(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock, Int)? {
        guard let firstMatch = matchListMarker(lines[start]) else { return nil }

        var items: [MarkdownListItem] = []
        var cursor = start
        let ordered = firstMatch.ordered
        var listStart = firstMatch.start

        while cursor < lines.count {
            if Self.isBlankLine(lines[cursor]) {
                // Blank lines between items are allowed; consume them.
                cursor += 1
                if cursor >= lines.count { break }
                continue
            }
            guard let match = matchListMarker(lines[cursor]) else { break }
            guard match.ordered == ordered else { break }

            // Collect lines of the item: first line body + continuation lines
            // indented further than the marker.
            let firstLineBody = String(lines[cursor].dropFirst(match.contentOffset))
            var bodyLines: [String] = [firstLineBody]
            let continuationIndent = match.contentOffset
            cursor += 1

            while cursor < lines.count {
                let raw = lines[cursor]
                if Self.isBlankLine(raw) {
                    // Lookahead: blank followed by another list item marker
                    // at the same level ends continuation.
                    let next = cursor + 1
                    if next >= lines.count { break }
                    if matchListMarker(lines[next]) != nil { break }
                    if raw.count < continuationIndent { break }
                    bodyLines.append("")
                    cursor += 1
                    continue
                }
                // Continuation requires sufficient indent.
                let prefix = raw.prefix(continuationIndent)
                if prefix.allSatisfy({ $0 == " " }) {
                    bodyLines.append(String(raw.dropFirst(continuationIndent)))
                    cursor += 1
                } else {
                    break
                }
            }

            let item = makeListItem(from: bodyLines)
            items.append(item)
            // Only apply `listStart` once (for the first item).
            if items.count == 1 {
                listStart = match.start
            }
        }

        guard !items.isEmpty else { return nil }
        return (.list(ordered: ordered, start: listStart, items: items), cursor - start)
    }

    private func makeListItem(from bodyLines: [String]) -> MarkdownListItem {
        // Task list detection: first line starts with `[ ]` or `[x]` followed
        // by space.
        var body = bodyLines
        var taskState: MarkdownTaskState = .none

        if let firstLine = body.first {
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[ ]") {
                taskState = .unchecked
                body[0] = String(firstLine.dropFirst(firstLine.distance(
                    from: firstLine.startIndex,
                    to: firstLine.firstRange(of: "[ ]")?.upperBound ?? firstLine.startIndex
                ))).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]") {
                taskState = .checked
                let marker = trimmed.hasPrefix("[x]") ? "[x]" : "[X]"
                body[0] = String(firstLine.dropFirst(firstLine.distance(
                    from: firstLine.startIndex,
                    to: firstLine.firstRange(of: marker)?.upperBound ?? firstLine.startIndex
                ))).trimmingCharacters(in: .whitespaces)
            }
        }

        let joined = body.joined(separator: "\n")
        let nestedBlocks = MarkdownParser(linkDefinitions: linkDefinitions).parse(joined).blocks
        let finalBlocks = nestedBlocks.isEmpty ? [.paragraph(inlines: [])] : nestedBlocks
        return MarkdownListItem(blocks: finalBlocks, taskState: taskState)
    }

    // MARK: - Tables (GFM)

    private func parseTable(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock, Int)? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start]
        let separatorLine = lines[start + 1]

        guard headerLine.contains("|"), separatorLine.contains("|") else {
            return nil
        }
        guard let alignments = parseTableAlignments(separatorLine) else {
            return nil
        }
        let headers = splitTableRow(headerLine).map { inlineParser.parse($0) }
        guard headers.count == alignments.count else { return nil }

        var rows: [[[MarkdownInline]]] = []
        var cursor = start + 2
        while cursor < lines.count {
            let row = lines[cursor]
            if !row.contains("|") { break }
            var cells = splitTableRow(row).map { inlineParser.parse($0) }
            // Pad or trim to match header column count.
            while cells.count < headers.count {
                cells.append([])
            }
            if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            cursor += 1
        }

        return (.table(headers: headers, alignments: alignments, rows: rows), cursor - start)
    }

    private func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var i = line.startIndex
        // Skip leading `|`.
        if line.first == "|" {
            i = line.index(after: i)
        }
        let trailingPipe = line.last == "|"
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\\" && line.index(after: i) < line.endIndex {
                current.append(line[line.index(after: i)])
                i = line.index(i, offsetBy: 2)
                continue
            }
            if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        if !trailingPipe || !current.isEmpty {
            cells.append(current.trimmingCharacters(in: .whitespaces))
        }
        _ = trailingPipe
        return cells
    }

    private func parseTableAlignments(_ line: String) -> [MarkdownTableAlignment]? {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTableAlignment] = []
        for raw in cells {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            // Must be all `-`, possibly with leading/trailing `:` for alignment.
            let left = trimmed.hasPrefix(":")
            let right = trimmed.hasSuffix(":")
            let inner = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !inner.isEmpty, inner.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            switch (left, right) {
            case (true, true): alignments.append(.center)
            case (true, false): alignments.append(.left)
            case (false, true): alignments.append(.right)
            case (false, false): alignments.append(.none)
            }
        }
        return alignments
    }

    // MARK: - Paragraph

    private func parseParagraph(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock?, Int) {
        var collected: [String] = []
        var cursor = start
        while cursor < lines.count {
            let line = lines[cursor]
            if Self.isBlankLine(line) { break }
            // Stop if a new block starts mid-stream.
            if cursor > start {
                if let setextLevel = Self.setextHeadingLevel(line), !collected.isEmpty {
                    let text = collected.joined(separator: "\n")
                    let inlines = inlineParser.parse(text)
                    return (.heading(level: setextLevel, inlines: inlines), cursor + 1 - start)
                }
                if parseHorizontalRule(line) != nil { break }
                if parseAtxHeading(line) != nil { break }
                if Self.leadingSpacesTrimmed(line, max: 3).hasPrefix("```") { break }
                if Self.leadingSpacesTrimmed(line, max: 3).hasPrefix("~~~") { break }
                if Self.isBlockquoteLine(line) { break }
                if parseFootnoteDefinition(lines: lines, at: cursor) != nil { break }
                if matchListMarker(line) != nil { break }
            }
            collected.append(line)
            cursor += 1
        }
        if collected.isEmpty {
            return (nil, 1)
        }
        let text = collected.joined(separator: "\n")
        let inlines = inlineParser.parse(text)
        guard !inlines.isEmpty else { return (nil, cursor - start) }
        return (.paragraph(inlines: inlines), cursor - start)
    }

    // MARK: - Helpers

    private static func splitLines(_ source: String) -> [String] {
        // Normalize `\r\n` → `\n` and split, preserving trailing empties.
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func isBlankLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func setextHeadingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) {
            return trimmed.count >= 1 ? 1 : nil
        }
        if trimmed.allSatisfy({ $0 == "-" }) {
            return trimmed.count >= 1 ? 2 : nil
        }
        return nil
    }

    static func leadingSpacesTrimmed(_ line: String, max: Int) -> String {
        var count = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == " ", count < max {
            index = line.index(after: index)
            count += 1
        }
        return String(line[index...])
    }
}
